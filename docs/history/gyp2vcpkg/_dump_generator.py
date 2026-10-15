# _dump_generator.py —— gyp2vcpkg 的自定义 gyp generator（`9.0-T-9a`）。
#
# 文件名用下划线：gyp 的 -f 参数把 `-` 当 flavor 分隔符（__init__.py:90-91），
# 含 `-` 的文件名会被拆成 format+flavor 导致 ModuleNotFoundError。
#
# 把 gyp 解析器返回的 (target_list, target_dicts) dump 成 JSON。gyp 会跑完全部
# 14 步处理（合并后缀、singleton 去重、路径相对化、early/late/latelate 三阶段、
# dependent settings 施加、static lib 调整、list filters、命令展开…）后调
# GenerateOutput，拿到的是最终、完整、正确的 target_dicts。
#
# gyp 的内建目录变量（PRODUCT_DIR / SHARED_INTERMEDIATE_DIR / INTERMEDIATE_DIR …）
# 一律落成**互不相同**的哨兵字符串：这些位置在 CMake 侧各有各的落点
# （PRODUCT_DIR → $<TARGET_FILE:...>、SHARED_INTERMEDIATE_DIR → ${NODE_PORT_V8_GENERATED}、
# INTERMEDIATE_DIR → ${NODE_PORT_V8_GENERATED}/intermediate/<宿主目标>…），
# 用同一个值（gypd.py 里那个 'dir'）就没法在后面分辨谁是谁 —— 第一步就要
# 把事实保留下来，别到第三步再猜。
#
# 调研依据：调研-15（gyp 规则与现成解析器）。

import json
import os

import gyp
import gyp.common

generator_supports_multiple_toolsets = True
generator_wants_static_library_dependencies_adjusted = False

# 目录类变量 → 哨兵（后面靠它把路径翻译成 CMake 变量）
generator_default_variables = {
    "PRODUCT_DIR": "__GYP_PRODUCT_DIR__",
    "LIB_DIR": "__GYP_LIB_DIR__",
    "SHARED_LIB_DIR": "__GYP_SHARED_LIB_DIR__",
    "INTERMEDIATE_DIR": "__GYP_INTERMEDIATE__",
    "SHARED_INTERMEDIATE_DIR": "__GYP_SHARED_INTERMEDIATE__",
}
# 与路径无关的内建：留空串（gypd.py 也是这么干的）
for _unused in ["RULE_INPUT_PATH", "RULE_INPUT_ROOT", "RULE_INPUT_NAME",
                "RULE_INPUT_DIRNAME", "RULE_INPUT_EXT", "EXECUTABLE_PREFIX",
                "EXECUTABLE_SUFFIX", "STATIC_LIB_PREFIX", "STATIC_LIB_SUFFIX",
                "SHARED_LIB_PREFIX", "SHARED_LIB_SUFFIX", "CONFIGURATION_NAME"]:
    generator_default_variables[_unused] = ""


def CalculateVariables(default_variables, params):
    generator_flags = params.get("generator_flags", {})
    for key, val in generator_flags.items():
        default_variables.setdefault(key, val)
    default_variables.setdefault("OS", gyp.common.GetFlavor(params))


def CalculateGeneratorInputInfo(params):
    pass


def GenerateOutput(target_list, target_dicts, data, params):
    out = {"target_list": target_list, "target_dicts": target_dicts}
    filepath = params.get("generator_flags", {}).get("output_dir", ".")
    os.makedirs(filepath, exist_ok=True)
    filename = os.path.join(filepath, "gyp_resolved.json")
    with open(filename, "w", encoding="utf-8") as f:
        json.dump(out, f, default=str, indent=2, ensure_ascii=False)
    print("gyp2vcpkg: wrote %s (%d targets)" % (filename, len(target_list)))
