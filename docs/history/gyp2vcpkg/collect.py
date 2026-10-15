# collect.py —— gyp2vcpkg 第二步：**收集**（`9.0-T-9`）。
#
# 输入：resolve.py 的 `gyp_resolved.json`（gyp 跑完 14 步之后的 target_dicts）
# 输出：`compile_config_<平台>.json` —— 一个**编译配置数据集**：配置里点名的每个
#       目标/动作，只留 fe 建 CMake 需要的字段，并且**路径全部归一**。
#
# 这一步只做"收"，不做"翻成 CMake"（那是 generate.py 的事）：三步各自能被单独测。
#
# 路径归一（关键，别留给第三步猜）：
#   gyp 把路径相对 **.gyp 文件所在目录** 记下来（v8.gyp 在 `tools/v8_gypfiles/` 下，
#   于是 V8 的源是 `../../deps/v8/src/api/api.cc`）。这里统一成
#   **相对 node 源码树根** + 四类哨兵前缀：
#     `__SHARED__/`      = gyp 的 SHARED_INTERMEDIATE_DIR
#     `__INTERMEDIATE__/`= gyp 的 INTERMEDIATE_DIR（每个宿主目标一个子目录）
#     `__PRODUCT__/`     = gyp 的 PRODUCT_DIR（构建期工具所在）
#     `__LIB__/`         = LIB_DIR / SHARED_LIB_DIR
#   哨兵是 `_dump_generator.py` 里设的互不相同的值 —— 不这么做，第三步就只能靠
#   文件名猜谁是谁（旧的 gyp-to-cmake.js 就是这么干的，猜错过）。
#
# 调研依据：调研-15/16。

import json
import os
import posixpath

SENTINELS = {
    "__GYP_SHARED_INTERMEDIATE__": "__SHARED__",
    "__GYP_INTERMEDIATE__": "__INTERMEDIATE__",
    "__GYP_PRODUCT_DIR__": "__PRODUCT__",
    "__GYP_LIB_DIR__": "__LIB__",
    "__GYP_SHARED_LIB_DIR__": "__LIB__",
}


def _norm(path, gyp_dir):
    """把 gyp 记下的路径归一成 `相对 node 根` 或 `哨兵/相对`。"""
    if not isinstance(path, str):
        return path
    p = path.replace("\\", "/")
    for raw, canon in SENTINELS.items():
        if p == raw:
            return canon + "/"
        if p.startswith(raw + "/"):
            return canon + "/" + p[len(raw) + 1:]
        # 哨兵被塞在**中间**（实测 `tools/v8_gypfiles/__GYP_SHARED_INTERMEDIATE__/
        # inspector-generated-output-root/include`）：gyp 给 include_dirs 加 .gyp
        # 目录前缀时那一节的 `<(SHARED_INTERMEDIATE_DIR)` 还没展开。前缀是假的，
        # 从哨兵处截断 —— 否则生成出来的 include 目录不存在。
        i = p.find("/" + raw)
        if i >= 0:
            return canon + p[i + len(raw) + 1:]
    joined = posixpath.normpath(posixpath.join(gyp_dir, p)) if gyp_dir else posixpath.normpath(p)
    return joined.replace("\\", "/")


CANON_SENTINELS = ("__SHARED__", "__INTERMEDIATE__", "__PRODUCT__", "__LIB__")


def has_sentinel(s):
    """字符串里是否含"还没归位的哨兵"（`__GYP_*__` 或归一后的 `__SHARED__`…）。

    `ldflags` 里那些 `-Wl,-force_load,<(PRODUCT_DIR)/libuv` 就是：它们是"把某个
    静态库整个塞进 exe"，CMake 里得写成 `$<LINK_LIBRARY:WHOLE_ARCHIVE,…>`，
    翻译不了 —— 生成那一步靠这个识别出来、跳过并注明。
    """
    if not isinstance(s, str):
        return False
    return any(k in s for k in SENTINELS) or any(k in s for k in CANON_SENTINELS)


def _norm_list(lst, gyp_dir):
    if not isinstance(lst, list):
        return []
    return [_norm(x, gyp_dir) for x in lst]


def _target_dir(build_file, node_root):
    """build_file 相对 node 根的目录（gyp 记相对路径的基准）。"""
    rel = os.path.relpath(os.path.dirname(build_file), node_root)
    return "" if rel == "." else rel.replace("\\", "/")


def _split_qualified(qt):
    """`C:\\...\\v8.gyp:v8_libbase#target` → (build_file, name, toolset)。"""
    head, _, toolset = qt.rpartition("#")
    build_file, _, name = head.rpartition(":")
    return build_file, name, toolset


def _pick(target_dicts, name, toolset="target"):
    """按目标名取 target_dict；多个文件里有同名时取 toolset 匹配的那一个。"""
    hits = []
    for qt, td in target_dicts.items():
        bf, n, ts = _split_qualified(qt)
        if n == name:
            hits.append((qt, bf, ts, td))
    if not hits:
        return None, None
    for qt, bf, ts, td in hits:
        if ts == toolset:
            return qt, td
    qt, bf, ts, td = hits[0]
    return qt, td


_CONFIG_FIELDS = [
    "defines", "defines_excluded", "include_dirs", "include_dirs_excluded",
    "cflags", "cflags_c", "cflags_cc", "cflags_objc", "cflags_objcc",
    "ldflags", "libraries",
    "msvs_disabled_warnings", "msvs_settings", "msvs_precompiled_header",
    "msvs_precompiled_source", "xcode_settings",
]


# 只有这几个字段**是路径**，需要按 .gyp 所在目录归一；
# 其余（defines / cflags / msvs_disabled_warnings …）都是字面量，动了就错了
# （把 `_GLIBCXX_USE_CXX11_ABI=1` 归一成 `tools/v8_gypfiles/_GLIBCXX...` 这种事
#  只有真跑一遍才会发现）。
_PATH_FIELDS = {"include_dirs", "include_dirs_excluded"}


def _extract_config(td, gyp_dir, config_name):
    cfg = (td.get("configurations") or {}).get(config_name, {})
    out = {}
    for f in _CONFIG_FIELDS:
        v = cfg.get(f)
        if v in (None, [], {}):
            continue
        if isinstance(v, list):
            out[f] = _norm_list(v, gyp_dir) if f in _PATH_FIELDS else list(v)
        else:
            out[f] = v
    return out


def collect(resolved_file, node_root, config, platform, config_name="Release"):
    """从 gyp_resolved.json 收出编译配置数据集。返回 (输出文件路径, 数据集)。"""
    with open(resolved_file, encoding="utf-8") as f:
        resolved = json.load(f)
    target_dicts = resolved["target_dicts"]

    dataset = {
        "platform": platform["label"],
        "env": platform["env"],
        "config": config_name,
        "targets": {},
        "actions": {},
    }

    # ---- 目标 ------------------------------------------------------------
    for name in config["targets"]:
        qt, td = _pick(target_dicts, name)
        if td is None:
            raise KeyError("gyp 解析结果里没有目标 %s（平台 %s）" % (name, platform["label"]))
        gyp_dir = _target_dir(_split_qualified(qt)[0], node_root)
        dataset["targets"][name] = {
            "build_file": _split_qualified(qt)[0],
            "gyp_dir": gyp_dir,
            "type": td.get("type", ""),
            "toolset": td.get("toolset", ""),
            "sources": _norm_list(td.get("sources") or [], gyp_dir),
            "dependencies": td.get("dependencies") or [],
            "config": _extract_config(td, gyp_dir, config_name),
        }

    # ---- 动作 ------------------------------------------------------------
    for spec in config["actions"]:
        host = spec["host"]
        action_name = spec["action"]
        key = spec.get("name", action_name)
        qt, td = _pick(target_dicts, host)
        # 动作可以**只在某些平台上存在**（asm_to_inline_asm 就是
        # `OS=="win" and clang==1` 才有的）。缺了就记 None —— 生成那一步以第一个
        # 平台为准、再与其它平台取并集，不会因为某平台没有它而丢掉片段。
        if td is None:
            dataset["actions"][key] = None
            continue
        gyp_dir = _target_dir(_split_qualified(qt)[0], node_root)
        acts = td.get("actions") or []
        found = None
        for a in acts:
            if a.get("action_name") == action_name:
                found = a
                break
        if found is None:
            dataset["actions"][key] = None
            continue
        dataset["actions"][key] = {
            "host": host,
            "action_name": action_name,
            "build_file": _split_qualified(qt)[0],
            "gyp_dir": gyp_dir,
            "inputs": _norm_list(found.get("inputs") or [], gyp_dir),
            "outputs": _norm_list(found.get("outputs") or [], gyp_dir),
            # 命令行**保持 gyp 的原样**：它是"参数混合体"（`python`、`--config`、
            # `-o`、`src/builtins/x.tq` 混在一起），在这里按路径归一会把
            # `--stamp` 变成 `tools/v8_gypfiles/--stamp`。哪些是路径由 generate
            # 那一步判断（它需要 gyp_dir，所以一并带上）。
            "action": [x.replace("\\", "/") if isinstance(x, str) else x
                       for x in (found.get("action") or [])],
        }

    return dataset


def write(dataset, out_dir, label):
    os.makedirs(out_dir, exist_ok=True)
    out_file = os.path.join(out_dir, "compile_config_%s.json" % label)
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(dataset, f, indent=2, ensure_ascii=False, default=str)
    return out_file
