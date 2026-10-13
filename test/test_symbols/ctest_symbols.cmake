# 符号审计：机械地检查 node 自带库与 vcpkg 依赖库之间有没有"跨库重复强符号"。
#
# 为什么需要它：**链接成功 ≠ 没有隐患**。
#   * 重复的**强**符号会让链接器直接报错 —— 那种冲突很显眼（我们最希望是这种）；
#   * 但**同名 COMDAT / 弱符号**（inline / template，以及同名第三方库的不同版本，
#     比如 v8 内嵌的 abseil / highway 与 vcpkg 的 abseil / highway）会被**静默折叠**：
#     运行时到底用哪一份由链接器决定。版本不同就是不稳定行为 —— 链接期不报错，
#     只能靠扫符号发现。
#
# 实现在同目录的 symbol_check.js（本目录有 CMakeLists.txt，说明它是一个 ctest 目标），由**本工程自己编出来的 node** 执行：
#   * ctest 里跑的东西都是 C 或 JS，工具也该一致；
#   * 顺带是一次自检 —— 那份脚本能被刚编出来的 node 正确执行，本身就说明
#     它的 fs / child_process / Buffer 是好的。
# 平台：Windows 用 dumpbin，其它用 nm（原来只有 Windows 版，见 docs/暂时还没做.md 的旧账）。

set(_node_port_symbol_audit "${CMAKE_CURRENT_LIST_DIR}/symbol_check.js")
if(NOT EXISTS "${_node_port_symbol_audit}")
  message(WARNING "找不到 ${_node_port_symbol_audit}，本次跳过符号审计")
  return()
endif()

# 工具的绝对路径在**配置期**解析：CMake 进程里 chainload 的 toolchain 已经把 MSVC
# 加进了 PATH，所以这里找得到 dumpbin。ctest 进程本身不在 vcvars 环境里，光靠
# PATH 找不到 —— 必须把绝对路径喂给脚本。
set(_node_port_symtool_arg "")
if(WIN32)
  find_program(NODE_PORT_DUMPBIN NAMES dumpbin)
  if(NOT NODE_PORT_DUMPBIN)
    message(WARNING "找不到 dumpbin，本次跳过符号审计（它需要 MSVC 或 Windows SDK 的 dumpbin）")
    return()
  endif()
  set(_node_port_symtool_arg --dumpbin "${NODE_PORT_DUMPBIN}")
else()
  find_program(NODE_PORT_NM NAMES nm)
  if(NOT NODE_PORT_NM)
    message(WARNING "找不到 nm，本次跳过符号审计")
    return()
  endif()
  set(_node_port_symtool_arg --nm "${NODE_PORT_NM}")
endif()

# node 的静态库目录：node-config.cmake 位于 <prefix>/share/unofficial-node/ 下。
# 库本体在 <prefix>/lib；B1 之后 abseil/highway/crdtp/v8_zlib 等冲突库装到
# <prefix>/lib/manual-link —— 审计两个目录都要扫（脚本接受重复的 --node-lib-dir）。
get_filename_component(_node_port_prefix "${node_DIR}/../.." ABSOLUTE)
set(_node_port_libdir "${_node_port_prefix}/lib")

# 关键：只把**node 自己装进来**的那些库当成"node 侧"。<prefix>/lib 在 manifest 模式下
# 是整个工程共用的，里面还混着本工程自己声明的 gtest / fmt / ...；不区分的话审计会
# 拿它们去和 vcpkg packages 里的同名库比，等于"自己比自己"，满屏假阳性。
# node-config.cmake 导出的 node_INSTALLED_LIBRARIES 就是这份清单。
set(_node_port_libs_csv "")
if(DEFINED node_INSTALLED_LIBRARIES AND NOT node_INSTALLED_LIBRARIES STREQUAL "")
  string(REPLACE ";" "," _node_port_libs_csv "${node_INSTALLED_LIBRARIES}")
else()
  message(WARNING "node-config.cmake 没有导出 node_INSTALLED_LIBRARIES；"
                  "符号审计将扫描整个 lib 目录，可能报出'自己比自己'的假阳性")
endif()

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
         COMMAND node_embed "${_node_port_symbol_audit}"
                 --node-lib-dir "${_node_port_libdir}"
                 --node-lib-dir "${_node_port_libdir}/manual-link"
                 --node-libs "${_node_port_libs_csv}"
                 --dep-root "${_node_port_packages}"
                 --triplet "${VCPKG_TARGET_TRIPLET}"
                 ${_node_port_symtool_arg}
                 --json "${CMAKE_CURRENT_BINARY_DIR}/symbol-audit.json"
                 --fail-on-duplicates)
set_tests_properties(symbols-no-duplicate-strong PROPERTIES
  LABELS "symbols;coexist;tools"
  TIMEOUT 3600)

message(STATUS "符号审计：已注册（脚本=${_node_port_symbol_audit}，node 库=${_node_port_libdir}，"
               "vcpkg packages=${_node_port_packages}，工具=${_node_port_symtool_arg}）")
