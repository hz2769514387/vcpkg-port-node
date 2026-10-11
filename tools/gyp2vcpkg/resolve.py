# resolve.py —— gyp2vcpkg 第一步：**解析**。
#
# 用 node 自带的 gyp（gyp-next 0.22.2，`<node_root>/tools/gyp/pylib`）解析入口 .gyp，
# 把 gyp 跑完 14 步处理之后的 target_dicts dump 成 JSON。
# 不复制、不自写 gyp 解析器 —— 自写解析器正是最容易出错的做法（gyp 的语义散在
# `input.py` 三千行里：合并后缀、singleton 去重、路径相对化、early/late/latelate
# 三阶段、dependent settings、list filters、命令展开…）。
#
# 入口一般只写一个（node.gyp）：它的 `dependencies` 会把 `tools/v8_gypfiles/v8.gyp`、
# `abseil.gyp`、`deps/inspector_protocol/inspector_protocol.gyp` 一起拉进来。
#
# 变量环境怎么喂进去（两件事，都踩过）：
#
# 1. **`-D` 传不了列表**。`NameValueListToDict` 只会把值转成 int 或字符串 ——
#    于是 `<@(node_library_files)`（一个 list）被 `str()` 成 python 列表字面量后
#    再按空格切开，结果是 `'[lib/_http_agent.js,'` 这种碎块。所以：
#    标量走 `-D`，**非标量写进一份 `-I` 的 gypi**，形状照 node 自己的 `config.gypi`
#    （`gyp_node.py` 就是 `-I` 它的）。
# 2. **bool 落成字符串 `"true"/"false"`**。node.gyp 的条件写的是
#    `node_use_openssl=="true"`（比字符串），而 node 的 config.gypi 里
#    `"node_use_openssl": "true"` 也确实是字符串。
#
# `-D` 与文件里的 `variables` 谁赢？**文件赢** —— 所以"覆盖某个变量"要走
# `define_overrides`（写进那份 `-I` gypi 的最后），不能靠 `-D`。

import json
import os
import sys


def _env_value(v):
    """把 JSON 里的值转成 gyp 期望的形状（见文件头第 2 条）。"""
    if isinstance(v, bool):
        return "true" if v else "false"
    return v


def write_env_gypi(env_file, out_file, overrides=None, flavor=None):
    """把变量环境（+ 覆盖项）写成 `-I` 用的 gypi。

    env_file 是**官方包跑出来的 `process.config`**（形状 `{"variables": {...},
    "target_defaults": {...}}`，由调用方的前置步产出）—— 这里只取它的 `variables`。

    `flavor`（win/linux/mac）会补成 `OS` 变量：gyp 的 `GetFlavor` 认 `OS`，而
    **`OS` 不在官方 process.config 里**（它是 gyp 自己 setdefault 出来的）——
    跨平台一次跑两平台解析时，Windows 上解析 linux 必须显式给，否则会被算成 win。
    """
    with open(env_file, encoding="utf-8") as f:
        raw = json.load(f)
    env = dict(raw.get("variables", raw))
    if flavor:
        env["OS"] = flavor
    if overrides:
        env.update(overrides)

    lines = ["# 由 gyp2vcpkg/resolve.py 生成 —— 不要手改。",
             "# 形状照 node 的 config.gypi（gyp_node.py 用 -I 注入的那份）：",
             "#   bool → 字符串 \"true\"/\"false\"（node.gyp 的条件是比字符串的），",
             "#   int  → 原样；list/dict → 原样（`-D` 传不了，只能走 -I）。",
             "{",
             "  'variables': {"]
    for k in sorted(env):
        lines.append("    %s: %s," % (repr(k), repr(_env_value(env[k]))))
    lines.append("  },")
    lines.append("}")
    os.makedirs(os.path.dirname(out_file), exist_ok=True)
    with open(out_file, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return out_file


def resolve(node_root, gyp_file, env_file, out_dir, define_overrides=None, flavor=None):
    """解析 .gyp，dump gyp_resolved.json。返回输出文件路径。"""
    gyp_pylib = os.path.join(node_root, "tools", "gyp", "pylib")
    here = os.path.dirname(os.path.abspath(__file__))
    generator = os.path.join(here, "_dump_generator.py")

    if gyp_pylib not in sys.path:
        sys.path.insert(0, gyp_pylib)
    v8_gypfiles = os.path.join(node_root, "tools", "v8_gypfiles")
    if os.path.isdir(v8_gypfiles) and v8_gypfiles not in sys.path:
        sys.path.insert(0, v8_gypfiles)

    import gyp

    # 自定义 generator 用**模块名**喂给 gyp，而不是文件路径。
    #
    # 为什么：gyp 的 `-f` 把值里的第一个 `-` 当 flavor 分隔符（`gyp/__init__.py:90-91`
    # `format, flavor = format.split("-", 1)`）—— 而本工具所在目录现在叫 `node`
    # （不含 `-`，但保险起见仍走这条路径），绝对路径里带 `-` 就会被拆坏，报 `ModuleNotFoundError: gyp.generator.C:\…\fe`。
    # 所以先把 generator 作为模块加载进 `sys.modules['gyp.generator.<无横杠名>']`，
    # 再 `-f <无横杠名>` —— gyp 走 else 分支 `__import__("gyp.generator." + format)`，
    # 命中我们登记的那份。
    import importlib.util
    import gyp.generator  # noqa: F401  —— 让 gyp.generator 包先就位
    _gen_name = "g2v_dump_generator"
    _spec = importlib.util.spec_from_file_location(_gen_name, generator)
    _mod = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_mod)
    sys.modules["gyp.generator." + _gen_name] = _mod

    os.makedirs(out_dir, exist_ok=True)
    env_gypi = write_env_gypi(env_file, os.path.join(out_dir, "node-port-env.gypi"), define_overrides, flavor)

    args = ["-f", _gen_name, "--depth=" + node_root, "--no-parallel",
            "-I", os.path.join(node_root, "common.gypi"),
            "-I", env_gypi,
            "-Dcomponent=static_library", "-Dlibrary=static_library",
            # `<(python)` 用**正在跑本工具的那个解释器**（理由见文件头）。
            "-Dpython=" + sys.executable,
            "-Goutput_dir=" + out_dir, gyp_file]

    rc = gyp.main(args)
    if rc != 0:
        raise RuntimeError("gyp 失败（退出码 %d）" % rc)

    return os.path.join(out_dir, "gyp_resolved.json")
