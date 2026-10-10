cmake_minimum_required(VERSION 3.28)

# CMP0091 让 CMAKE_MSVC_RUNTIME_LIBRARY 真的生效。
set(CMAKE_POLICY_DEFAULT_CMP0091 NEW)

# ---------------------------------------------------------------------------
# node 的构建工程：把 node v24.21.0 整棵树（含 v8 / v8 third_party / vendored 五库）
# 编成**一个可链接的 `node`**，并把「头文件 + 静态库 + CMake 消费配置」安装出去。
# 这是用户终极目标里的「overlay-port 的 node 部分」：
#
#   * fe 侧（仓库根那个工程）只 find_package(node) + 链 node::node；
#   * node 的依赖（16 个官方 port）由本 port 的 vcpkg.json 声明，fe 经传递依赖拿到。
#
# 这个工程**只编 node**：不编 fe、不编 node 可执行、不编依赖探针 —— 那些是 fe 自己的事。
# 编译配置仍从 gyp 来（generated/*.cmake，由上层 gyp2vcpkg 生成）；只是「在什么时候、
# 由谁构建」从 fe 根工程搬到了这里（port 构建期）。
#
# 输入（由 portfile.cmake / 开发者传进来）：
#   NODE_ROOT        node 源码树根（vcpkg 解压那份，或 dev 时的 deps/node/node-v24.21.0）
#   Python3_EXECUTABLE  构建期 python 解释器（vcpkg 的 python3 tool）
# ---------------------------------------------------------------------------

project(node
  VERSION 24.21.0
  DESCRIPTION "node v24.21.0 的 CMake 构建（产出可链接的 node 库）"
  LANGUAGES C CXX)

if(NOT DEFINED NODE_ROOT)
  message(FATAL_ERROR "要传 -DNODE_ROOT=<node 源码树根>（portfile 传 vcpkg 解压出来的那份）。")
endif()
get_filename_component(NODE_ROOT "${NODE_ROOT}" ABSOLUTE)
if(NOT EXISTS "${NODE_ROOT}/node.gyp")
  message(FATAL_ERROR "NODE_ROOT 不像 node 源码树（没有 node.gyp）：${NODE_ROOT}")
endif()
set(NODE_ROOT "${NODE_ROOT}" CACHE INTERNAL "node 源码树根")

# gyp2vcpkg（python 工具 + 输入）与本工程目录同级（都由 portfile 拷进源码树）。
get_filename_component(NODE_PORT_GYP2VCPKG_TOOL "${CMAKE_CURRENT_SOURCE_DIR}/../gyp2vcpkg" ABSOLUTE)
if(NOT EXISTS "${NODE_PORT_GYP2VCPKG_TOOL}/gyp2vcpkg.py")
  message(FATAL_ERROR "缺 gyp2vcpkg 工具目录：${NODE_PORT_GYP2VCPKG_TOOL}")
endif()
set(NODE_PORT_GYP2VCPKG_TOOL "${NODE_PORT_GYP2VCPKG_TOOL}" CACHE INTERNAL "gyp2vcpkg（python 工具 + 输入）目录")

# 编译配置从哪来（`9.0-T-9`）：gyp（generated/*.cmake）+ 全工程硬约束（本节）
# + 没有 gyp 清单的目标的 patch（NodePortTargetPatch.cmake）。
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}")
include("${CMAKE_CURRENT_SOURCE_DIR}/NodePortTargetPatch.cmake")

# python 是**工具**（不是链接依赖）：gyp2vcpkg 与 node 树自带的 .py 都要它。
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# gyp2vcpkg：生成 V8 / node 的 CMake 片段。产物 `generated/*.cmake` 入库，
# 只在「缺 / 过期」时重新生成（gyp2vcpkg check 拿文件头指纹对账）。
# WORKING_DIRECTORY 固定为本工程目录 —— 指纹行写成相对这里的路径，裁判照此对账。
#
# 变量环境（`--env`）**按平台可用性给**：win/linux 两份随仓库入库；macOS 那份
# （darwin-arm64.json，取自官方 macOS arm64 构建的 process.config）由 CI/使用者在
# macOS 上产出。缺哪一份，那一个平台就不参与生成（片段里对应后缀的变量随之缺失）。
set(NODE_PORT_G2V_ENV
  "--env" "win=../gyp2vcpkg/env/win-x64.json"
  "--env" "linux=../gyp2vcpkg/env/linux-x64.json")
foreach(_seed "win-x64" "linux-x64")
  # win/linux 两份是仓库自带的，必须存在 —— 缺了说明仓库不完整。
  if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../gyp2vcpkg/env/${_seed}.json")
    message(FATAL_ERROR "缺变量环境：gyp2vcpkg/env/${_seed}.json")
  endif()
endforeach()
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../gyp2vcpkg/env/darwin-arm64.json")
  list(APPEND NODE_PORT_G2V_ENV
    "--env" "mac=../gyp2vcpkg/env/darwin-arm64.json")
endif()

execute_process(
  COMMAND "${Python3_EXECUTABLE}" "${NODE_PORT_GYP2VCPKG_TOOL}/gyp2vcpkg.py" check
          "--config" "../gyp2vcpkg/config.json"
          "--node-root" "${NODE_ROOT}"
          ${NODE_PORT_G2V_ENV}
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
  RESULT_VARIABLE _g2v_fresh
  OUTPUT_VARIABLE _g2v_check_out
  ERROR_VARIABLE _g2v_check_err)
if(NOT _g2v_fresh EQUAL 0)
  # 把"为什么判过期"打出来 —— check 的每一行都写着具体原因，不打出来的话 CI 上
  # 只看到"清单缺失或过期，重新生成……"，没法排查。新鲜时这段不会输出。
  string(REPLACE ";" "\\;" _g2v_check_msg "${_g2v_check_out}${_g2v_check_err}")
  message(STATUS "gyp2vcpkg check 判为过期/缺失：\n${_g2v_check_msg}")
  message(STATUS "gyp2vcpkg：清单缺失或过期，重新生成……")
  execute_process(
    COMMAND "${Python3_EXECUTABLE}" "${NODE_PORT_GYP2VCPKG_TOOL}/gyp2vcpkg.py" all
            "--config" "../gyp2vcpkg/config.json"
            "--node-root" "${NODE_ROOT}"
            ${NODE_PORT_G2V_ENV}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    RESULT_VARIABLE _g2v_rc)
  if(NOT _g2v_rc EQUAL 0)
    message(FATAL_ERROR "gyp2vcpkg 生成失败（见上面输出）")
  endif()
  message(STATUS "gyp2vcpkg：清单已重新生成")
endif()

# gyp2vcpkg 的消费层（node_port_add_v8_target / node_port_add_v8_action / node_port_drop_bundled_include…）
include("${CMAKE_CURRENT_SOURCE_DIR}/consume.cmake")

# node: common.gypi 的 cflags_cc 里是 `-std=gnu++20`（GNU 扩展开着，别关）。
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# CRT 口径**跟随 triplet**（不在这里写死）：vcpkg 的 Windows toolchain 会按
# VCPKG_CRT_LINKAGE 设好 CMAKE_MSVC_RUNTIME_LIBRARY —— 默认 triplet（x64-windows）
# 是动态 CRT（/MD），自定义的 static 口径是静态 CRT（/MT）。port 自己只负责
# "编出一致的库"，具体用哪种由使用者选的三元组决定。
# （若想用静态 CRT，见本仓库 triplets/ 下随附的 overlay triplet 用法说明。）

# 全工程的 Windows 宏（UNICODE / V8 源码前提，理由见原 fe 根 CMakeLists 的长注释）。
if(WIN32)
  add_compile_definitions(UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)
endif()

# 产物统一出口。
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/$<CONFIG>/bin")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/$<CONFIG>/lib")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/$<CONFIG>/lib")

# clang 的 compiler-rt 内建库（踩坑-20）：**仅在使用 clang-cl 时**才需要 ——
# lld-link 直链时驱动不会自动带上这些内建库。用默认的 MSVC（cl.exe）时不存在这个问题，
# 所以这里是"有则用、无则跳过"，不再无条件要求。
# 使用者若用 clang-cl 口径（见本仓库 triplets/），把该路径经
# -DNODE_PORT_CLANG_RT_BUILTINS=<clang/lib/clang/<ver>/lib/windows/clang_rt.builtins-x86_64.lib>
# 传进来即可。
if(WIN32 AND NODE_PORT_CLANG_RT_BUILTINS AND EXISTS "${NODE_PORT_CLANG_RT_BUILTINS}")
  link_libraries("${NODE_PORT_CLANG_RT_BUILTINS}")
endif()

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ---------------------------------------------------------------------------
# 依赖层（`9.0-P-2`）。顺序有要求：v8 先建 simdutf（被 tools / vendored 链）。
# ---------------------------------------------------------------------------
add_subdirectory(config)
add_subdirectory(v8)
add_subdirectory(tools)
add_subdirectory(vendored)
add_subdirectory(node)

# ---------------------------------------------------------------------------
# 安装 / 导出：给消费者（fe）一个可链接的 `node::node`。
#
# 不用 install(EXPORT)：gyp 的 'none' 目标在 CMake 里是 INTERFACE 库，INTERFACE_SOURCES
# 指向本工程构建树里的源文件 —— 导出给消费者等于让消费者去编这些源。所以**手写消费配置**：
# 装出真实静态库 + 头，配置里 find_dependency 第三方、定义 imported 目标、按当前口径接链接。
# ---------------------------------------------------------------------------
# 真静态库（有 .a/.lib）。`node_main` 是快照（+ Linux postmortem）的载体 —— 它的源
# 是代码生成物，编在这里。node_text_start 是 INTERFACE（.S 并进 node_main），不是库。
set(NODE_ARCHIVES
  node_base
  node_main
  v8_base_without_compiler
  v8_compiler
  v8_init
  v8_initializers
  v8_initializers_slow
  v8_snapshot
  v8_libbase
  v8_libplatform
  v8_zlib
  simdutf
  highway
  abseil
  ncrypto
  ncrypto_engine
  nbytes
  merve
  uvwasi
  crdtp)

install(TARGETS ${NODE_ARCHIVES} ARCHIVE DESTINATION lib)

# 头文件：node 的嵌入头（src/）+ v8 的公开头。
install(DIRECTORY "${NODE_ROOT}/src/" DESTINATION include/node
  FILES_MATCHING PATTERN "*.h" PATTERN "*.hpp")
install(DIRECTORY "${NODE_PORT_V8_ROOT}/include/" DESTINATION include)

# Windows 平台兼容性清单：fe 也要嵌（缺了一跑退出码 216，踩坑-21）。
install(FILES "${NODE_ROOT}/src/res/node.exe.extra.manifest"
  DESTINATION share/node RENAME node.exe.extra.manifest)

# ---- 手写消费配置 ----------------------------------------------------------
set(_cfg "# 由 node port 生成：node 的 CMake 消费配置（手写，不用 install(EXPORT)）。\n")
string(APPEND _cfg "include(CMakeFindDependencyMacro)\n")
foreach(_dep "OpenSSL" "libuv CONFIG" "llhttp CONFIG" "c-ares CONFIG"
             "unofficial-brotli CONFIG" "ZLIB" "ada CONFIG" "simdjson CONFIG"
             "ngtcp2 CONFIG" "zstd CONFIG" "ICU COMPONENTS uc i18n data"
             "unofficial-sqlite3 CONFIG" "hdr_histogram CONFIG")
  string(APPEND _cfg "find_dependency(${_dep})\n")
endforeach()
string(APPEND _cfg
  "get_filename_component(_node_prefix \"\${CMAKE_CURRENT_LIST_DIR}/../..\" ABSOLUTE)\n")
string(APPEND _cfg "set(_node_lib \"\${_node_prefix}/lib\")\n")
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  string(APPEND _cfg "set(_node_pre \"lib\")\nset(_node_suf \".a\")\n")
else()
  string(APPEND _cfg "set(_node_pre \"\")\nset(_node_suf \".lib\")\n")
endif()
foreach(_a IN LISTS NODE_ARCHIVES)
  string(APPEND _cfg
    "if(NOT TARGET node::${_a})\n"
    "  add_library(node::${_a} STATIC IMPORTED)\n"
    "  set_target_properties(node::${_a} PROPERTIES IMPORTED_LOCATION"
    " \"\${_node_lib}/\${_node_pre}${_a}\${_node_suf}\")\n"
    "endif()\n")
endforeach()
# nghttp2 的 port 不带 CMake config 包 —— 按裸库名链（与原 src/node 的做法一致）。
string(APPEND _cfg
  "find_library(_node_nghttp2 NAMES nghttp2 PATHS \"\${_node_lib}\" NO_DEFAULT_PATH)\n"
  "if(NOT _node_nghttp2)\n  set(_node_nghttp2 nghttp2)\nendif()\n")

# libuv 的目标名随口径变（见 consume.cmake 的 `node_port_uv_lib`）。这里（顶层）看不到
# 导入目标 —— 各子目录自己 find_package —— 所以把解析放进**生成的配置**，由消费方在
# 自己的环境里定夺用哪个名字。
string(APPEND _cfg
  "if(TARGET libuv::uv_a)\n  set(_node_uv libuv::uv_a)\nelse()\n  set(_node_uv libuv::uv)\nendif()\n")

# V8 静态库之间有环（GNU ld 单遍解析会漏）→ Linux 用 LINK_GROUP:RESCAN；
# Apple 的链接器不支持 RESCAN → 库列表重复一遍；Windows 直接列。
set(_static
  node::node_base node::v8_base_without_compiler node::v8_compiler
  node::v8_init node::v8_initializers node::v8_initializers_slow
  node::v8_snapshot node::v8_libbase node::v8_libplatform
  node::v8_zlib node::simdutf node::highway node::abseil)
set(_own_rest
  node::node_main node::ncrypto node::ncrypto_engine
  node::nbytes node::merve node::uvwasi node::crdtp)
set(_third
  OpenSSL::SSL OpenSSL::Crypto "\${_node_uv}" llhttp::llhttp_static c-ares::cares
  unofficial::brotli::brotlidec unofficial::brotli::brotlienc unofficial::brotli::brotlicommon
  ZLIB::ZLIB ada::ada simdjson::simdjson ngtcp2::ngtcp2_static zstd::libzstd_static
  ICU::uc ICU::i18n ICU::data unofficial::sqlite3::sqlite3 hdr_histogram::hdr_histogram_static)

string(APPEND _cfg "add_library(node::node INTERFACE IMPORTED)\n")
string(APPEND _cfg
  "set_target_properties(node::node PROPERTIES"
  " INTERFACE_INCLUDE_DIRECTORIES \"\${_node_prefix}/include;\${_node_prefix}/include/node\")\n")
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  string(APPEND _cfg
    "target_link_libraries(node::node INTERFACE"
    " \"$<LINK_GROUP:RESCAN,${_static}>\" ${_own_rest} ${_third} \"\${_node_nghttp2}\")\n")
elseif(APPLE)
  # Apple 不支持 $<LINK_GROUP:RESCAN>（见 src/node 的同一处说明）→ 库列表重复一遍。
  string(APPEND _cfg
    "target_link_libraries(node::node INTERFACE"
    " ${_static} ${_own_rest} ${_third} \"\${_node_nghttp2}\" ${_static})\n")
  # macOS 上 abseil 的 cctz 引用 CoreFoundation（`_CFRelease` 等）；构建期由
  # `xcode_settings.OTHER_LDFLAGS` 提供（见 gyp2vcpkg/generate.py）。而手写的
  # imported 目标带不了构建期的 INTERFACE_LINK_OPTIONS —— 所以在消费配置里显式补。
  string(APPEND _cfg
    "target_link_options(node::node INTERFACE -framework CoreFoundation)\n")
else()
  string(APPEND _cfg
    "target_link_libraries(node::node INTERFACE"
    " ${_static} ${_own_rest} ${_third} \"\${_node_nghttp2}\""
    " Dbghelp Psapi Winmm Ws2_32 Shlwapi Iphlpapi Userenv Advapi32)\n")
endif()
string(APPEND _cfg
  "set(node_NODE_SOURCE_MANIFEST \"\${CMAKE_CURRENT_LIST_DIR}/node.exe.extra.manifest\")\n")

file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/node-config.cmake" "${_cfg}")
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/node-config.cmake" DESTINATION share/node)