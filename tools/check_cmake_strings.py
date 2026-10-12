#!/usr/bin/env python3
"""检查 CMake 脚本里"引号内的变量引用有没有闭合"。

## 为什么需要它（一次真实的 2 小时 37 分钟）

2026-10-13：portfile 里出现了一处笔误 —— `file(WRITE ... "${_cfg")`，
少了一个收尾的 `}`。它让 x64-windows 那个硬门在 CI 上：

    * 每次尝试都**完整构建 32 分钟**（依赖 + node 全量），
    * 最后倒在 portfile 的安装阶段（`Syntax error ... "${_cfg" ... unterminated
      variable reference`），
    * 而 CI 的"下载重试"又把它**重试了 4 次** ⇒ 一个字符 = **2h37m** 的 CI 时间。

## 为什么 `cmake -P`（另一条 lint）抓不到它

`cmake -P <portfile>` 确实会报同样的错误，**但它是"执行到那一行"时才报**。
portfile 执行到第 22 行 `vcpkg_check_linkage` 就因"未知命令"停下（那是预期的，
portfile 本来就只能在 vcpkg 上下文里跑）⇒ 出错的那一行**永远执行不到** ✗。
所以 `cmake -P` 只能挡住"文件级词法错误"（例如整行少一个引号），
挡不住这种"引号配平、但里面的 `${` 没闭合"的错误。这个脚本补的就是这个盲区。

## 判据

逐字符扫描，跟踪"是否在双引号字符串里"（`\\` 转义要认），
在字符串内部遇到 `${` 就记一层深度，遇 `}` 减一层；
**字符串闭合时深度必须归零**，否则报错并给出文件:行号。
`\\$` 是 CMake 的转义（写进生成文件的字面 `$`），不算变量引用，跳过。

## 用法

    python3 tools/check_cmake_strings.py ports/node/**/*.cmake   # 或直接给目录
    python3 tools/check_cmake_strings.py --self-test             # 跑内置自测

退出码：0 = 全过；1 = 有文件不通过；2 = 用法错误。
"""

from __future__ import annotations

import argparse
import pathlib
import sys


def check_text(text: str, name: str) -> list[tuple[int, str]]:
    """返回 [(行号, 说明)]；空列表表示通过。"""
    problems: list[tuple[int, str]] = []
    in_string = False
    depth = 0            # 字符串内未闭合的 ${ 层数
    depth_line = 0       # 该层开始的所在行
    line = 1
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "\n":
            line += 1
        if in_string:
            if ch == "\\":
                # 转义下一个字符（\$ 就是"写进文件的字面 $"）—— 整对跳过
                if i + 1 < n and text[i + 1] == "\n":
                    line += 1
                i += 2
                continue
            if ch == '"':
                if depth != 0:
                    problems.append(
                        (depth_line,
                         "第 %d 行起的字符串里有一个没闭合的 `${`（到这里少了 `}`）" % depth_line)
                    )
                in_string = False
                depth = 0
            elif ch == "$" and i + 1 < n and text[i + 1] == "{":
                if depth == 0:
                    depth_line = line
                depth += 1
                i += 2
                continue
            elif ch == "}" and depth > 0:
                depth -= 1
        else:
            if ch == "#":
                # 注释直到行尾（CMake 的 # 注释里不解析任何东西）
                while i < n and text[i] != "\n":
                    i += 1
                continue
            if ch == '"':
                in_string = True
                depth = 0
        i += 1
    if in_string:
        problems.append((line, "文件结束时双引号字符串仍未闭合（整行少一个引号？）"))
    return problems


_SELF_TEST_CASES = [
    # (内容, 期望有没有问题)
    ('file(WRITE "${out}" "${cfg}")\n', False),
    ('file(WRITE "${out}" "${cfg")\n', True),          # 就是那次 2h37m 的笔误
    ('set(x "a${b}c")\n', False),
    ('set(x "a\\${b}c")\n', False),                     # \$ 是转义，不算引用
    ('set(x "unterminated)\n', True),                   # 引号本身没闭合
    ('# 注释里 "${_cfg" 无所谓\nset(x "ok")\n', False),  # 注释不参与
    ('string(APPEND _cfg "a\\n" "b${c}d\\n")\n', False),
]


def self_test() -> int:
    bad = 0
    for text, expect_problem in _SELF_TEST_CASES:
        got = bool(check_text(text, "<self-test>"))
        ok = got == expect_problem
        print("%s %r → 有问题=%s（期望 %s）" % ("✓" if ok else "✗", text, got, expect_problem))
        if not ok:
            bad += 1
    print("自测：%d/%d 通过" % (len(_SELF_TEST_CASES) - bad, len(_SELF_TEST_CASES)))
    return 1 if bad else 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("paths", nargs="*", help="要检查的文件或目录")
    ap.add_argument("--self-test", action="store_true", help="跑内置自测")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()
    if not args.paths:
        ap.error("要么给路径，要么用 --self-test")

    files: list[pathlib.Path] = []
    for raw in args.paths:
        p = pathlib.Path(raw)
        if p.is_dir():
            files.extend(sorted(p.rglob("*.cmake")))
        else:
            files.append(p)

    failed = 0
    for f in files:
        try:
            text = f.read_text(encoding="utf-8")
        except OSError as exc:
            print("::warning file=%s::读不到文件：%s" % (f, exc))
            continue
        for lineno, why in check_text(text, str(f)):
            print("::error file=%s,line=%d::%s" % (f, lineno, why))
            failed += 1
    print("检查了 %d 个 cmake 文件，%d 处问题" % (len(files), failed))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
