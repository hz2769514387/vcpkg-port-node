"""符号检测：node port 自带库 vs vcpkg 依赖库，是否存在重复符号。

用法（须在 vcvars 环境下）：
  python symbol_check.py <node_lib_dir> <vcpkg_packages_dir> <triplet>
                         [--json out.json] [--dumpbin <路径>] [--fail-on-duplicates]

  --dumpbin：dumpbin.exe 的完整路径。不传就用 PATH 上的 dumpbin。ctest 用例会从
             CMake 侧把配置期找到的绝对路径传进来（ctest 进程本身不在 vcvars 环境里，
             光靠 PATH 找不到）。
  --fail-on-duplicates：发现跨库重复强符号时以退出码 1 结束（CI / ctest 当闸门用）。
                        不加这个开关时只报告，退出码恒为 0（当调查工具用）。

原理：
  dumpbin /symbols 导出每个 .lib 的定义符号。只保留 **External + 真实段 + 非 COMDAT**
  的符号（COMDAT 可合法重复，属 inline/template 正常现象），再做跨库交集。
  交集非空 = 两个库都定义了同一个强符号 → 链接期 ODR / 重复定义风险。

为什么排除 COMDAT：
  dumpbin 输出里 `selection  2 (pick any)` / `selection  1 (pick no duplicates)`
  出现在 Section length 那一行，表示该段是 COMDAT。COMDAT 重复是设计允许的。
"""
import json
import os
import re
import subprocess
import sys
from collections import defaultdict

# 一行：000 00000000 SECT4  notype       Static       | .text
SECTION_LINE = re.compile(r"^\s*[0-9A-F]+\s+[0-9A-F]+\s+(?P<sect>SECT\S*)\s+.*?\|\s*(?P<name>\.\S+)\s*$")
# console 行（带 selection 的是 COMDAT）
CONSOLE_LINE = re.compile(r"^\s*(?P<id>[0-9A-F]+)\s+[0-9A-F]+\s+(?P<sect>SECT\S*)\s+.*?\|")
# 定义符号行：008 00000000 SECT4  notype ()    External     | ?name (...)
SYM_LINE = re.compile(r"^\s*[0-9A-F]+\s+[0-9A-F]+\s+(?P<sect>SECT\S*)\s+.*?\s+(?P<bind>External|WeakExternal|Static)\s+\|\s*(?P<name>\S+)")

COMDAT = re.compile(r"selection\s+\d")

# MSVC 的字符串字面量 COMDAT：`??_C@_...@...?$AA@`。它们**允许跨库重复**
# （每个 obj 各带一份，链接器按 COMDAT 折叠），必须排除，否则全是假阳性。
STRING_LITERAL = re.compile(r"^\?\?_C@")


def lib_symbols(lib, dumpbin):
    """返回 (强符号集合, 错误信息)。只保留 External 定义 + 非 COMDAT 段。"""
    try:
        r = subprocess.run([dumpbin, "/symbols", "/nologo", lib],
                           capture_output=True, text=True, errors="replace",
                           timeout=900)
    except Exception as e:
        return None, str(e)
    out = r.stdout
    if not out or "COFF SYMBOL TABLE" not in out:
        return None, "no COFF table"

    # dumpbin /symbols 的每个段是**两行**：
    #   F3F 00000000 SECT3BE notype       Static       | .rdata
    #       Section length  2A0, ..., selection    2 (pick any)
    # 第二行**不带** SECT 编号 —— 所以要顺序扫描、记住上一行提到的段。
    SECT_HEAD = re.compile(r"^\s*[0-9A-F]+\s+[0-9A-F]+\s+(SECT\S+)\s")
    comdat = set()
    last_sect = None
    for line in out.splitlines():
        if "Section length" in line:
            if COMDAT.search(line) and last_sect:
                comdat.add(last_sect)
            continue
        m = SECT_HEAD.match(line)
        if m:
            last_sect = m.group(1)

    strong = set()
    for line in out.splitlines():
        m = SYM_LINE.match(line)
        if not m:
            continue
        if m.group("bind") != "External":
            continue
        sect = m.group("sect")
        name = m.group("name")
        if sect in comdat:              # COMDAT：允许重复
            continue
        if name.startswith("."):        # 段名 / 内部
            continue
        if STRING_LITERAL.match(name):  # MSVC 字符串字面量 COMDAT
            continue
        strong.add(name)
    return strong, None


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    node_lib_dir, pkg_dir, triplet = argv[0], argv[1], argv[2]
    json_out = None
    if "--json" in argv:
        json_out = argv[argv.index("--json") + 1]
    # CI 要把它当闸门用：有跨库重复强符号就红。默认仍是"只报告、退出 0"，
    # 因为这个脚本平时也当调查工具用，不该因为发现问题就打断别人的手头动作。
    fail_on_duplicates = "--fail-on-duplicates" in argv
    dumpbin = "dumpbin"
    if "--dumpbin" in argv:
        dumpbin = argv[argv.index("--dumpbin") + 1]

    node_libs, dep_libs = {}, {}
    for f in sorted(os.listdir(node_lib_dir)):
        if f.lower().endswith(".lib"):
            s, err = lib_symbols(os.path.join(node_lib_dir, f), dumpbin)
            if s is not None:
                node_libs[f] = s
            else:
                print("  ! %s: %s" % (f, err), file=sys.stderr)

    for pkg in sorted(os.listdir(pkg_dir)):
        if triplet not in pkg:
            continue
        libdir = os.path.join(pkg_dir, pkg, "lib")
        if not os.path.isdir(libdir):
            continue
        for f in sorted(os.listdir(libdir)):
            if f.lower().endswith(".lib"):
                s, err = lib_symbols(os.path.join(libdir, f), dumpbin)
                if s is not None:
                    dep_libs["%s/%s" % (pkg, f)] = s

    print("== node 自带库 %d 个（强符号合计 %d）==" % (
        len(node_libs), sum(len(v) for v in node_libs.values())))
    for k, v in sorted(node_libs.items(), key=lambda x: -len(x[1])):
        print("   %-46s %6d 个强符号" % (k, len(v)))
    print()
    print("== vcpkg 依赖库 %d 个（强符号合计 %d）==" % (
        len(dep_libs), sum(len(v) for v in dep_libs.values())))
    for k, v in sorted(dep_libs.items(), key=lambda x: -len(x[1])):
        print("   %-46s %6d 个强符号" % (k, len(v)))

    print()
    print("== 跨库重复强符号 ==")
    found = []
    for nl, ns in node_libs.items():
        for dl, ds in dep_libs.items():
            common = ns & ds
            if common:
                found.append((nl, dl, common))
    if not found:
        print("(无)")
    else:
        for nl, dl, common in sorted(found, key=lambda x: -len(x[2])):
            print("  %-40s  vs  %-40s  %d 个" % (nl, dl, len(common)))
        for nl, dl, common in sorted(found, key=lambda x: -len(x[2]))[:3]:
            print("\n--- %s  vs  %s（前 25）---" % (nl, dl))
            for c in sorted(common)[:25]:
                print("   ", c)

    if json_out:
        with open(json_out, "w", encoding="utf-8") as f:
            json.dump({
                "node_libs": {k: sorted(v) for k, v in node_libs.items()},
                "dep_libs": {k: sorted(v) for k, v in dep_libs.items()},
                "duplicates": [{"node": n, "dep": d, "syms": sorted(s)}
                               for n, d, s in found],
            }, f, ensure_ascii=False, indent=1)
        print("\nJSON 写入 %s" % json_out)
    if fail_on_duplicates and found:
        print("\n::error:: 发现 %d 组跨库重复强符号（--fail-on-duplicates）" % len(found))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
