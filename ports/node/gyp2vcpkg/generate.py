# generate.py —— gyp2vcpkg 第三步：**生成**。
#
# 输入：collect.py 的数据集（**每个平台一份**，平台数由配置的 `platforms` 决定）
# 输出：一串 `.cmake` 片段 —— **只 `set()` 变量**，不含任何 `add_library` /
#       `add_custom_command`。调用方怎么把这些变量变成目标是它自己的事。
#
# 这一步只做"翻译"，**不再做任何 gyp 语义判断**：条件求完了、dependent settings
# 施加完了、命令展开完了、late 变量（mksnapshot_flags 那一类）也就位了 —— 都是
# resolve 那一步由 gyp 自己做的。这里剩下的只是"gyp 的写法 → CMake 的写法"：
#
#   * `__PRODUCT__/<工具>`    → 调用方的"工具路径"表达式（CMake 里是 `$<TARGET_FILE:…>`）
#   * `__SHARED__/x`          → <调用方的中间产物根>/x
#   * `__INTERMEDIATE__/x`    → <调用方的中间产物根>/intermediate/<宿主目标>/x
#   * `<子树前缀>/…`          → 调用方给该子树配的变量（例如 `deps/v8/` → `${NODE_PORT_V8_ROOT}/`）
#   * 其余                    → <调用方的源码根>/…
#   * 命令行里的 `python`     → 调用方的 python 变量
#
# 上面这些"调用方的变量/表达式"全部来自配置的 `cmake` 段 —— 本工具**不认识**任何
# 具体项目，也就不该写死它们的名字。
#
# **多平台（N≥1）**：平台标签取自配置 `platforms[].label`，标签首段就是平台名
# （win / linux / mac，与 gyp 的 flavor 一致）。片段里的变量按平台带后缀：
#   `<前缀>_<目标>_SOURCES_<平台>` / `_DEFINES_<平台>` / `_INCLUDE_DIRS_<平台>` /
#   `_CFLAGS_<平台>` …；两边都相同的进**不带后缀**的那一份（N 平台取交集）。
# 这样 win/linux 的输出与旧的"两平台"实现**逐字节一致**（win 独有 = win 减去其余平台）。
#
# 两处**必须**改写的命令行参数（都是踩过的）：
#   * `--target_os=…`：要跟随执行平台（配置里的 `target_os_var`），
#     写死成某个平台会让别的平台生成错格式的汇编（GAS 编 COFF 直接报错）。
#   * `--inspector_protocol_dir`：code_generator.py:84 会 lstrip('/') 后原样写进
#     #include —— 传绝对路径时生成坏 include（编译期才炸）。只保留子树变量下的
#     相对路径，靠该子树的 -I 命中。
#
# 编译/链接标志只出 **POSIX 那一套**（`_<平台>`）：MSVC 侧的等价物在 gyp 里是
# `msvs_settings`（`MSVS_DISABLED_WARNINGS` / `MSVS_FLAGS` / `LINK_LIBS_WIN`），
# 两套各归各家 —— 把 gyp 在 win 下也留着的那份 POSIX cflags（`-O3`、
# `-fvisibility=hidden`…）喂给 MSVC 就是非法参数。

import os
import posixpath
import re

from collect import SENTINELS, has_sentinel

COMPILE_UNIT = re.compile(r"\.(cc|c|cpp|m|mm|S|asm)$")
# 命令行里"像路径"的参数：带斜杠、或有短扩展名。像 `--config` / `-o` / `python`
# / `Default` / `x64` 这种就不是 —— 按路径翻译会把它们变成源码树下的路径
# （踩过：`python` 变成 `${NODE_ROOT}/tools/v8_gypfiles/python`）。
LIKE_PATH = re.compile(r"\.[A-Za-z0-9_]{1,6}$")


def _looks_like_path(x):
    if "/" in x:
        return True
    return bool(LIKE_PATH.search(x))


def _is_python_token(x):
    """命令行里的那一节是不是"调用方的 python"。

    认的是 **basename 以 `python` 开头**（`python` / `python3` / `python.exe` /
    `/usr/bin/python3` / `C:\\\\…\\\\python.exe`）—— 因为 gyp 侧的 `<(python)` 展开成什么，
    取决于当时 `-Dpython` 给的是什么：Windows 上可能是 `python`，Ubuntu 24.04 上必须是
    `python3` 或绝对路径（那里**没有** `python` 这个名字）。**判据必须跨平台一致**，
    否则同一份清单在两边会生成出不同的片段（那就没法把片段入库了）。
    """
    base = x.replace("\\", "/").rsplit("/", 1)[-1].lower()
    return base.startswith("python")


# `--key=<路径>` / `key=<路径>` 的**键**（后者是 gyp 里的
# `--config_value protocol.path=deps/v8/include/js_protocol.pdl` —— 键不带 `-`）。
KEY_LIKE = re.compile(r"^-{0,2}[A-Za-z_][A-Za-z0-9_.]*$")


def _join(rel, gyp_dir):
    """命令行里的一节相对路径 → collect 的归一写法（先认哨兵，再按 .gyp 归位）。

    collect 对 `action` 命令行是**原样保留**的（它是"参数混合体"），所以归位这一
    步留到这里做 —— 也只有这里知道哪些节是路径。
    """
    p = rel.replace("\\", "/")
    for raw, canon in SENTINELS.items():
        if p == raw:
            return canon + "/"
        if p.startswith(raw + "/"):
            return canon + "/" + p[len(raw) + 1:]
    joined = posixpath.normpath(posixpath.join(gyp_dir, p)) if gyp_dir else posixpath.normpath(p)
    return joined.replace("\\", "/")


# 配置里 `cmake` 段的默认值（调用方不写也能跑，只是名字通用）
DEFAULT_CMAKE = {
    "var_prefix": "G2V",
    "action_var_prefix": "G2V",
    "node_root_var": "${G2V_SOURCE_ROOT}",
    "shared_intermediate_var": "${G2V_GENERATED}",
    "intermediate_var": "${G2V_GENERATED}/intermediate",
    "python_var": "${Python3_EXECUTABLE}",
    "target_os_var": "${G2V_TARGET_OS}",
    "tool_expr": "$<TARGET_FILE:%s>",
    "subtree_vars": [],
}


class Ctx:
    """生成时要用到的"调用方的写法"。"""

    def __init__(self, cfg):
        c = dict(DEFAULT_CMAKE)
        c.update(cfg.get("cmake") or {})
        self.var_prefix = c["var_prefix"]
        self.action_var_prefix = c["action_var_prefix"]
        self.node_root_var = c["node_root_var"]
        self.shared = c["shared_intermediate_var"]
        self.intermediate = c["intermediate_var"]
        self.python = c["python_var"]
        self.target_os = c["target_os_var"]
        self.tool_expr = c["tool_expr"]
        # 子树映射按前缀长度从长到短匹配（先配的优先）
        self.subtrees = [(p, v) for p, v in c["subtree_vars"]]
        # 源码树根的**绝对路径** —— 判断"命令行里的相对路径能不能定位到"要用
        self.source_root = cfg.get("_node_root")

    def path(self, p, shared_var=None, host=None):
        """归一后的路径 → CMake 写法。"""
        canon, rest = _split_canon(p)
        if canon == "__PRODUCT__":
            return self.tool_expr % rest
        if canon == "__SHARED__":
            base = shared_var or self.shared
            return "%s/%s" % (base, rest) if rest else base
        if canon == "__INTERMEDIATE__":
            base = "%s/%s" % (self.intermediate, host or "")
            return "%s/%s" % (base, rest) if rest else base
        if canon == "__LIB__":
            base = shared_var or self.shared
            return "%s/lib/%s" % (base, rest)
        for prefix, var in self.subtrees:
            if rest == prefix.rstrip("/"):
                return var.rstrip("/")
            if rest.startswith(prefix):
                return var + rest[len(prefix):]
        return "%s/%s" % (self.node_root_var, rest)

    def arg_to_cmake(self, x, gyp_dir, shared_var=None, host=None):
        """命令行里的**一个**参数 → CMake 写法。

        三类：字面量（`python` / `--config` / `-o` / `x64` / `Default`）、路径、
        `key=<路径>`。判据见 `_looks_like_path` / `KEY_LIKE`。

        路径按哪个根解释是个坑：gyp **不**对 `action` 命令行做路径处理，写在里面
        的相对路径归谁解释是 .gyp 自己定的 —— 多数按 .gyp 所在目录（`V8_ROOT`
        就是这么算出来的），但 torque 的 `.tq` 列表**刻意**相对 `-v8-root` 写。
        所以这里是"**能定位到源码树里才翻译**，定位不到的原样保留"（保留的那部分
        由工具自己按 `-v8-root` 解析 —— 翻译成绝对路径反而会错）。
        """
        if not isinstance(x, str):
            return x
        if _is_python_token(x):
            return self.python
        if "=" in x and KEY_LIKE.match(x.split("=", 1)[0]):
            k, _, v = x.partition("=")
            p = self._locate(v, gyp_dir) if _looks_like_path(v) else None
            return "%s=%s" % (k, self.path(p, shared_var, host)) if p else x
        if not _looks_like_path(x):
            return x
        p = self._locate(x, gyp_dir)
        return self.path(p, shared_var, host) if p else x

    def _locate(self, rel, gyp_dir):
        """命令行里的相对路径 → collect 的归一写法；定位不到返回 None。"""
        p = _join(rel, gyp_dir)
        if _split_canon(p)[0]:
            return p                     # 哨兵（SHARED_INTERMEDIATE_DIR / PRODUCT_DIR…）
        root = self.source_root
        if not root:
            return p
        if os.path.exists(os.path.join(root, p)):
            return p
        # 退一步：直接按源码根解释（有些列表是相对**别的**根写的，恰好也在源码根下）
        q = posixpath.normpath(rel)
        if q != p and os.path.exists(os.path.join(root, q)):
            return q
        return None

    def subtree_vars_set(self):
        return {v.rstrip("/") for _, v in self.subtrees}


def _split_canon(p):
    """`__SHARED__/x` → ('__SHARED__', 'x')；否则 (None, p)。"""
    for canon in ("__SHARED__", "__INTERMEDIATE__", "__PRODUCT__", "__LIB__"):
        if p == canon + "/":
            return canon, ""
        if p.startswith(canon + "/"):
            return canon, p[len(canon) + 1:]
    return None, p


def cmake_quote(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def _list_of(d, key):
    return (d.get("config") or {}).get(key) or []


def _msvs(d, tool):
    return ((d.get("config") or {}).get("msvs_settings") or {}).get(tool) or {}


def _exceptions(d):
    cc = _msvs(d, "VCCLCompilerTool")
    xcode = (d.get("config") or {}).get("xcode_settings") or {}
    return (cc.get("ExceptionHandling") == 1
            or str(cc.get("RuntimeTypeInfo")) == "true"
            or "-fexceptions" in _list_of(d, "cflags_cc")
            or str(xcode.get("GCC_ENABLE_CPP_EXCEPTIONS")) == "YES")


def _plat_suffix(label):
    """平台标签 → 变量后缀：`win`/`linux`/`mac`（标签首段，与 gyp flavor 同口径）。"""
    return label.split("-")[0].upper()


def _split_common(per_plat_lists):
    """N 平台的"公共 / 各平台独有"。

    返回 `(common, [每平台独有一份])`：
      * `common` = 所有平台的交集（按第一个平台的顺序）；
      * 第 i 份 = 第 i 个平台里"其余平台都没有"的那些（按该平台自己的顺序）。
    两平台时与旧的 `_common_and_only(a, b)` 结果一致（win 独有 = win − linux）。
    """
    if len(per_plat_lists) == 1:
        return list(per_plat_lists[0]), [[]]
    sets = [set(x) for x in per_plat_lists]
    inter = set.intersection(*sets)
    common = [x for x in per_plat_lists[0] if x in inter]
    per = []
    for i, lst in enumerate(per_plat_lists):
        others = set()
        for j, s in enumerate(sets):
            if j != i:
                others |= s
        per.append([x for x in lst if x not in others])
    return common, per


def _emit_set(L, name, values, quote=False):
    L.append("set(%s" % name)
    for v in values:
        L.append("  " + (cmake_quote(v) if quote else v))
    L.append(")")


# ---------------------------------------------------------------- 目标

def emit_target_file(name, datas, labels, head_lines, gyp_rel, cfg):
    """datas / labels：**同一顺序**的各平台数据集与标签（N≥1）。"""
    ctx = Ctx(cfg)
    U = "%s_%s" % (ctx.var_prefix, name.upper())
    sufs = [_plat_suffix(x) for x in labels]
    tw = datas[0]["targets"][name]
    L = list(head_lines)
    L.append("#   蓝本    ：%s（目标 %s，gyp 里的类型 %s）" % (gyp_rel, name, tw["type"]))
    labs = [x.split("-")[0] for x in labels]
    L.append("#   编译单元：" + " / ".join(
        "%s %d" % (lab, _n(d["targets"][name], True)) for lab, d in zip(labs, datas))
        + "（另外 " + "、".join(
            "%s %d" % (lab, _n(d["targets"][name], False)) for lab, d in zip(labs, datas))
        + " 个是头文件）")
    L.append("")

    is_interface = tw["type"] == "none"
    is_executable = tw["type"] == "executable"
    L.append("set(%s_IS_INTERFACE %s)" % (U, "TRUE" if is_interface else "FALSE"))
    L.append("set(%s_IS_EXECUTABLE %s)" % (U, "TRUE" if is_executable else "FALSE"))
    L.append("")

    for suf, d in zip(sufs, datas):
        td = d["targets"][name]
        _emit_set(L, "%s_SOURCES_%s" % (U, suf),
                  [ctx.path(p, host=name) for p in td["sources"] if _is_unit(p)])
    L.append("")

    common, per = _split_common([_list_of(d["targets"][name], "defines") for d in datas])
    # MSVC 侧"关异常"是**两件事一起做**：`/EHs-c-` 之外还得让 STL 也别用异常，
    # 否则 <vector> 之类会蹦 C4530。gyp 里只写了 `ExceptionHandling: 0` ——
    # 这一条是翻译出来的组合，不是发明（POSIX 侧同理，靠 cflags_cc 的 -fno-exceptions）。
    # 只对 win 那一份补（其余平台靠 cflags_cc）。
    for i, suf in enumerate(sufs):
        if suf != "WIN":
            continue
        if str(_msvs(datas[i]["targets"][name], "VCCLCompilerTool").get("ExceptionHandling")) == "0" \
                and "_HAS_EXCEPTIONS=0" not in per[i]:
            per[i].append("_HAS_EXCEPTIONS=0")
    _emit_set(L, "%s_DEFINES" % U, common, quote=True)
    for suf, values in zip(sufs, per):
        _emit_set(L, "%s_DEFINES_%s" % (U, suf), values, quote=True)
    L.append("")

    common, per = _split_common([_list_of(d["targets"][name], "include_dirs") for d in datas])
    _emit_set(L, "%s_INCLUDE_DIRS" % U, [ctx.path(p, host=name) for p in common])
    for suf, values in zip(sufs, per):
        _emit_set(L, "%s_INCLUDE_DIRS_%s" % (U, suf),
                  [ctx.path(p, host=name) for p in values])
    L.append("")

    # gyp 的 `dependencies` —— 目标依赖图。**只给名字**（去掉 .gyp 路径与 `#host`/`#target`）：
    # 名字才是调用方认得的东西，toolset 只影响用哪套工具链（我们不交叉编译，无所谓）。
    # 跨平台取并集：差别只在中途的条件分支。
    #
    # 怎么变成链接/构建顺序**是调用方的事**（哪些 dep 用 vcpkg 那份顶替、哪些是动作目标
    # 只需要 add_dependencies）—— 本工具只保证"事实完整"。
    deps = _dep_names(*[d["targets"][name] for d in datas])
    if deps:
        L.append("# gyp 的 `dependencies`（跨平台取并集；按名字去重，调用方自己映射）")
        _emit_set(L, "%s_DEPS" % U, deps)
        L.append("")

    # 编译/链接标志：**逐平台**（POSIX 那一套；win 侧走 msvs_settings）。
    posix = False
    for field in ("cflags", "cflags_cc", "ldflags", "libraries"):
        for lbl, suf, d in zip(labels, sufs, datas):
            if suf == "WIN":
                continue
            v = _list_of(d["targets"][name], field)
            # macOS：gyp 用 `xcode_settings.OTHER_LDFLAGS` 表达"要链的框架/链接开关"
            # （例：`-framework CoreFoundation`、`-Wl,-search_paths_first`）—— POSIX 的
            # `ldflags` 里**没有**它们。不取就会在链接期报 `_CFRelease` 一类未定义符号
            # （mac CI 实测：abseil 的 cctz 在 macOS 上用 CoreFoundation）。
            #
            # **只对 mac 平台取**：`xcode_settings` 是 .gyp 里的静态内容，三平台的解析
            # 结果里都带着它；无脑取会把 `-framework` 喂给 Linux（ld 直接报错）。
            #
            # 值里可能是"一项含空格"（`'-framework CoreFoundation'`）—— 拆成两项再给
            # CMake，否则会变成一个带空格的 argv、驱动认不出来。
            if field == "ldflags" and lbl.split("-")[0].lower() == "mac":
                _xs = (d["targets"][name].get("config") or {}).get("xcode_settings") or {}
                for _f in _xs.get("OTHER_LDFLAGS") or []:
                    v = list(v) + (_f.split() if isinstance(_f, str) else [_f])
            if not v:
                continue
            # `-Wl,-force_load,<(PRODUCT_DIR)/libuv` / `-Wl,--whole-archive
            # <(PRODUCT_DIR)/obj/…/libv8_snapshot.a` 这一类：写的是"gyp 产物目录下的
            # 静态库"，CMake 里得写成 `$<LINK_LIBRARY:WHOLE_ARCHIVE,…>` —— 本工具
            # 翻不了（翻出来是个不存在的路径），跳掉并在文件里注明，交给调用方自己写。
            #
            # **打包的开关要一起跳**：`--whole-archive` / `--no-whole-archive` 是一对
            # 括号，被包住的库路径跳掉之后括号就不成对了 —— 剩下一个**没闭合**的
            # `-Wl,--whole-archive` 会把后面所有库都整份拉进产物。
            PACK = ("-Wl,--whole-archive", "-Wl,--no-whole-archive")
            dropped = [x for x in v if has_sentinel(x) or x in PACK]
            v = [x for x in v if not has_sentinel(x) and x not in PACK]
            if dropped:
                L.append("#   gyp 的 %s 里有 %d 项是把构建产物整份塞进链接的写法"
                         "（%s…），翻不成 CMake，调用方要自己写 $<LINK_LIBRARY:WHOLE_ARCHIVE,…>"
                         % (field, len(dropped), dropped[0]))
            if v:
                posix = True
                _emit_set(L, "%s_%s_%s" % (U, field.upper(), suf), v, quote=True)
    if posix:
        L.append("")

    exceptions_on = any(_exceptions(d["targets"][name]) for d in datas)
    if exceptions_on:
        L.append("# gyp 把这个目标的异常/RTTI 又打开了（msvs ExceptionHandling:1 / cflags_cc -fexceptions /")
        L.append("# xcode GCC_ENABLE_CPP_EXCEPTIONS）—— 全工程默认是关的，要显式开回去")
    L.append("set(%s_EXCEPTIONS %s)" % (U, "TRUE" if exceptions_on else "FALSE"))

    # ---- 只写在 msvs_settings 里的那几样（gyp 的 `libraries` / `cflags` 里没有）----
    # 这些**只对 win 有意义**，所以取 win 那一份（没有 win 平台就不出）。
    win_i = next((i for i, s in enumerate(sufs) if s == "WIN"), None)
    if win_i is not None:
        twd = datas[win_i]["targets"][name]
        disabled = _list_of(twd, "msvs_disabled_warnings")
        if disabled:
            L.append("# gyp 的 msvs_disabled_warnings（禁 %d 个警告，不传就全刷屏）" % len(disabled))
            _emit_set(L, "%s_MSVS_DISABLED_WARNINGS" % U, ["/wd%s" % w for w in disabled])
        # AdditionalOptions 只是 msvs_settings 里的一半：WarningLevel / RuntimeTypeInfo /
        # ExceptionHandling 是**另三个键**，不翻就等于"全工程默认是什么就是什么"。
        msvs_flags = list(_msvs(twd, "VCCLCompilerTool").get("AdditionalOptions") or [])
        msvs_flags += _msvs_switches(_msvs(twd, "VCCLCompilerTool"))
        if msvs_flags:
            L.append("# msvs_settings.VCCLCompilerTool：AdditionalOptions + WarningLevel /")
            L.append("# RuntimeTypeInfo / ExceptionHandling 翻出来的开关（Windows 专用）")
            _emit_set(L, "%s_MSVS_FLAGS" % U, msvs_flags, quote=True)
        link_libs = []
        for d in datas:
            for l in _msvs(d["targets"][name], "VCLinkerTool").get("AdditionalDependencies") or []:
                if l not in link_libs:
                    link_libs.append(l)
        if link_libs:
            L.append("# 只写在 msvs_settings.VCLinkerTool.AdditionalDependencies 里的系统库")
            _emit_set(L, "%s_LINK_LIBS_WIN" % U, link_libs)
    L.append("")
    return "\n".join(L) + "\n"


def _dep_names(*dicts):
    """`dependencies` → 目标名（去重、排序）。

    gyp 里一条依赖长这样：`<.gyp 的绝对路径>:<目标名>#<toolset>`。名字在最后一个
    `:` 之后、`#` 之前；路径里的盘符冒号（Windows）不能当分隔符用，所以是从右往左找。
    """
    seen = set()
    for d in dicts:
        for dep in d.get("dependencies") or []:
            if not isinstance(dep, str):
                continue
            head = dep.split("#", 1)[0]
            name = head.rsplit(":", 1)[-1]
            if name:
                seen.add(name)
    return sorted(seen)


def _is_unit(p):
    return bool(COMPILE_UNIT.search(p))


# msvs_settings.VCCLCompilerTool 里那三个**不是** AdditionalOptions 的键。
# 值在 gyp 里是字符串（common.gypi 给的就是 `'WarningLevel': '3'` 这种）。
_MSVS_EH = {"0": "/EHs-c-", "1": "/EHsc", "2": "/EHa"}


def _msvs_switches(cc):
    """WarningLevel / RuntimeTypeInfo / ExceptionHandling → MSVC 开关。"""
    out = []
    wl = cc.get("WarningLevel")
    if wl not in (None, ""):
        out.append("/W%s" % wl)
    rtti = str(cc.get("RuntimeTypeInfo"))
    if rtti == "false":
        out.append("/GR-")
    elif rtti == "true":
        out.append("/GR")
    eh = _MSVS_EH.get(str(cc.get("ExceptionHandling")))
    if eh:
        out.append(eh)
    return out


def _n(d, units):
    return sum(1 for p in d["sources"] if _is_unit(p) == units)


# ---------------------------------------------------------------- 动作

def emit_action_file(key, datas, labels, head_lines, gyp_rel, cfg):
    ctx = Ctx(cfg)
    U = "%s_%s" % (ctx.action_var_prefix, key.upper())
    sufs = [_plat_suffix(x) for x in labels]
    # 动作可以**只在某些平台上存在**（asm_to_inline_asm 就是 `OS=="win" and clang==1`
    # 才有的）。base 取第一个真有它的平台；没有任何平台有它时返回 None（调用方不建）。
    acts = [(s, d["actions"].get(key)) for s, d in zip(sufs, datas)]
    acts = [(s, a) for s, a in acts if a]
    if not acts:
        return None
    base_suf, aw = acts[0]
    host = aw["host"]
    gen = "${%s_GEN}" % U

    L = list(head_lines)
    L.append("#   蓝本    ：%s 里 %s 的 action「%s」"
             % (gyp_rel, host, aw["action_name"]))

    # 平台间不一样的那一两个动作（torque 的 .tq 集合会随条件变）取**并集**：
    # 多声明一个输出，工具也会多产出一个（它按输入逐个生成），所以是安全的；
    # 反过来少声明，构建系统就会报"没有规则生成它"。
    inputs = list(aw["inputs"])
    outputs = list(aw["outputs"])
    for _, a in acts[1:]:
        for x in a["inputs"]:
            if x not in inputs:
                inputs.append(x)
        for x in a["outputs"]:
            if x not in outputs:
                outputs.append(x)

    # 第一个输入通常是"要跑的那个工具"：`__PRODUCT__/torque`
    tool = None
    if inputs:
        canon, rest = _split_canon(inputs[0])
        if canon == "__PRODUCT__":
            tool = rest
    rest_inputs = inputs[1:] if tool else inputs

    cmd = [ctx.arg_to_cmake(x, aw["gyp_dir"], gen, host) for x in aw["action"]]
    # code_generator.py:84 对 --inspector_protocol_dir 做 lstrip('/') 后原样写进
    # #include —— 传绝对路径时生成坏 include。这里只保留子树变量下的相对路径。
    for var in ctx.subtree_vars_set():
        for i in range(len(cmd) - 1):
            if cmd[i] == "--inspector_protocol_dir" and cmd[i + 1].startswith(var.rstrip("/") + "/"):
                cmd[i + 1] = cmd[i + 1][len(var.rstrip("/")) + 1:]
    # --target_os 必须跟随执行平台（见文件头）。
    for i, c in enumerate(cmd):
        if c.startswith("--target_os="):
            cmd[i] = "--target_os=" + ctx.target_os

    out_rel = []
    for o in outputs:
        canon, r = _split_canon(o)
        if canon == "__INTERMEDIATE__":
            out_rel.append("intermediate/%s/%s" % (host, r) if r else "intermediate/%s" % host)
        else:
            out_rel.append(r)
    dirs = sorted({o.rsplit("/", 1)[0] for o in out_rel if "/" in o})

    # 工具往哪个目录写：命令行里有 `-o <dir>` 就用它（走同一套翻译），
    # 否则取第一个输出所在的目录。
    out_dir = None
    for i in range(len(aw["action"]) - 1):
        if aw["action"][i] == "-o":
            out_dir = ctx.arg_to_cmake(aw["action"][i + 1], aw["gyp_dir"], gen, host)
    if out_dir is None:
        first = out_rel[0] if out_rel else ""
        d = first.rsplit("/", 1)[0] if "/" in first else ""
        out_dir = ("%s/%s" % (gen, d)) if d else gen

    L.append("#   输入 %d 个；输出 %d 个（%d 个目录）" % (len(rest_inputs), len(out_rel), len(dirs)))
    L.append("")
    if tool:
        L.append("set(%s_TOOL %s)" % (U, tool))
    L.append("# gyp 的 SHARED_INTERMEDIATE_DIR")
    L.append("set(%s_GEN %s)" % (U, ctx.shared))
    L.append("# 工具往这里写（-o 那个参数；没有 -o 时就是第一个输出所在的目录）")
    L.append("set(%s_OUTDIR %s)" % (U, out_dir))
    _emit_set(L, "%s_INPUTS" % U, [ctx.path(p, shared_var=gen, host=host) for p in rest_inputs])
    _emit_set(L, "%s_OUTPUTS" % U, ["%s/%s" % (gen, o) for o in out_rel])
    _emit_set(L, "%s_OUTPUT_DIRS" % U, ["%s/%s" % (gen, d) for d in dirs])
    L.append("set(%s_INTERMEDIATE %s/%s)" % (U, ctx.intermediate, host))
    L.append("# gyp 的 _inputs（命令行里引用的那批，含工具）")
    _emit_set(L, "%s_IN_ALL" % U,
              [ctx.path(p, shared_var=gen, host=host) for p in inputs], quote=True)
    # 这些 set() 必须都在 CMD 之前：include() 是顺序展开的，CMD 引用的变量若在后面
    # 才定义就会展开成空串（工具只收到 exe、收不到输出文件名）。
    _emit_set(L, "%s_CMD" % U, cmd, quote=True)
    L.append("")
    return "\n".join(L) + "\n"


# ---------------------------------------------------------------- 入口

def generate(datasets, config, out_dir, head_lines):
    """datasets：数据集列表（每个已激活平台一份）。返回写出的文件路径清单。"""
    by_label = {d["platform"]: d for d in datasets}
    labels = [p["label"] for p in config["platforms"]]
    datas = [by_label[l] for l in labels]
    os.makedirs(out_dir, exist_ok=True)
    written = []

    def gyp_rel(rec):
        bf = rec.get("build_file", "")
        root = config.get("_node_root")
        if root and os.path.isabs(bf):
            rel = os.path.relpath(bf, root).replace("\\", "/")
            return ("%s/%s" % (os.path.basename(root), rel)) if not rel.startswith("..") else bf
        return bf

    rel0 = gyp_rel(datas[0]["targets"][config["targets"][0]]) if config["targets"] else ""

    for name in config["targets"]:
        text = emit_target_file(name, datas, labels, head_lines,
                                gyp_rel(datas[0]["targets"][name]), config)
        p = os.path.join(out_dir, "%s.cmake" % name)
        _write(p, text)
        written.append(p)

    for spec in config["actions"]:
        key = spec.get("name", spec["action"])
        base = next((d["actions"][key] for d in datas if d["actions"].get(key)), None)
        rel = gyp_rel(base) if base else rel0
        text = emit_action_file(key, datas, labels, head_lines, rel, config)
        if text is None:
            continue
        p = os.path.join(out_dir, "%s_action.cmake" % key)
        _write(p, text)
        written.append(p)
    return written


def _write(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)