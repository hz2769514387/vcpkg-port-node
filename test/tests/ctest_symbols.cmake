# 符号审计（T4）：机械地检查 node 自带库与 vcpkg 依赖库之间有没有"重复强符号"。
#
# 为什么需要它：**链接成功 ≠ 没有隐患**。
#   * 重复的**强**符号会让链接器直接报错 —— 那种冲突很显眼（我们最希望是这种）；
#   * 但**同名 COMDAT**（inline / template，以及同名第三方库的不同版本，比如 v8 内嵌的
#     abseil / highway 与 vcpkg 的 abseil / highway）会被**静默折叠**：运行时到底用哪一份
#     由链接器决定。版本不同就是不稳定行为 —— 这个只能靠扫符号发现，链接期不报错。
#
# 目前是 Windows/dumpbin 专用（Linux 的 nm 版本还没写，见 docs/暂时还没做.md）。
if(NOT WIN32)
  message(STATUS "符号审计：仅 Windows（dumpbin）实现，本平台跳过（见 docs/暂时还没做.md）")
  return()
endif()

if(NOT Python3_Interpreter_FOUND)
  message(WARNING "符号审计需要 python3，本次跳过")
  return()
endif()

set(_node_port_symbol_audit "${CMAKE_CURRENT_LIST_DIR}/../../tools/symbol_check.py")
if(NOT EXISTS "${_node_port_symbol_audit}")
  message(WARNING "找不到 ${_node_port_symbol_audit}，本次跳过符号审计")
  return()
endif()

# dumpbin 的绝对路径在**配置期**解析：CMake 进程里 chainload 的 toolchain 已经把 MSVC
# 加进了 PATH，所以这里找得到。ctest 进程本身不在 vcvars 环境里，光靠 PATH 找不到。
find_program(NODE_PORT_DUMPBIN NAMES dumpbin)
if(NOT NODE_PORT_DUMPBIN)
  message(WARNING "找不到 dumpbin，本次跳过符号审计（它需要 MSVC 或 Windows SDK 的 dumpbin）")
  return()
endif()

# node 的静态库目录：node-config.cmake 位于 <prefix>/share/node/ 下。
get_filename_component(_node_port_prefix "${node_DIR}/../.." ABSOLUTE)
set(_node_port_libdir "${_node_port_prefix}/lib")

# vcpkg 的 packages 目录：从 toolchain 路径反推 VCPKG_ROOT。
if(DEFINED CMAKE_TOOLCHAIN_FILE)
  get_filename_component(_node_port_vcpkg_root "${CMAKE_TOOLCHAIN_FILE}/../../.." ABSOLUTE)
endif()
set(_node_port_packages "${_node_port_vcpkg_root}/packages")

if(NOT IS_DIRECTORY "${_node_port_packages}")
  message(WARNING "找不到 vcpkg packages 目录（'${_node_port_packages}'），本次跳过符号审计")
  return()
endif()

add_test(NAME symbols-no-duplicate-strong
         COMMAND ${Python3_EXECUTABLE} "${_node_port_symbol_audit}"
                 "${_node_port_libdir}"
                 "${_node_port_packages}"
                 "${VCPKG_TARGET_TRIPLET}"
                 --dumpbin "${NODE_PORT_DUMPBIN}"
                 --json "${CMAKE_CURRENT_BINARY_DIR}/symbol-audit.json"
                 --fail-on-duplicates)
set_tests_properties(symbols-no-duplicate-strong PROPERTIES
  LABELS "symbols;coexist"
  TIMEOUT 3600)

message(STATUS "符号审计：已注册（node 库=${_node_port_libdir}，vcpkg packages=${_node_port_packages}，dumpbin=${NODE_PORT_DUMPBIN}）")
