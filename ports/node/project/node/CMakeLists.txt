# node 主体：C++ 核心编成 `node_base` 静态库，最终由 `node_main` + `libnode`
# 汇成可链接的 `node`（安装与消费配置在顶层 CMakeLists 里）。
#
# 蓝本：node.gyp 的 `node_base` 目标（static_library）。清单由 gyp2vcpkg 从 node.gyp 实测展开。
# 两样清单里没有、要在这里补：
#   1. `node_javascript.cc`：node_js2c 的生成物（挂在 src/tools 的 node_javascript 上）；
#   2. V8 的头文件路径：经 v8_internal_headers / v8_headers 等 INTERFACE 目标传递。
#
# **与原 fe 侧的区别**：这里不编 node 可执行、不编 fe —— 那两样是消费者（fe）的事。

set(NODE_PORT_NODE_GENERATED "${CMAKE_BINARY_DIR}/generated")

# V8 的目标带 `$<$<COMPILE_LANGUAGE:ASM_MASM>:...>` 这类 genex，链进本目录的目标时
# CMake 要求**本目录**也启用了对应语言（否则 generate 报 Missing variable CMAKE_ASM_MASM_COMPILE_OBJECT）。
if(WIN32)
  enable_language(ASM_MASM)
else()
  enable_language(ASM)
endif()

# 协议链的命令要用 python（生成片段里是 ${Python3_EXECUTABLE}）—— 兄弟目录看不见这个变量，
# 这里重新 find 一次。
find_package(Python3 REQUIRED COMPONENTS Interpreter)

node_port_add_v8_target(node_base)

target_sources(node_base PRIVATE "${NODE_PORT_NODE_GENERATED}/node_javascript.cc")
add_dependencies(node_base node_javascript)

# 跨文件依赖（gyp 里写在 `deps/*.gyp:<目标>` 形式，清单工具不跨文件解析，这里逐条补）：
find_package(hdr_histogram CONFIG REQUIRED)

# node 自己的 inspector 协议链（4 个 action）。顺序靠 add_dependencies 串起来。
node_port_add_v8_action(convert_node_protocol_to_json)
node_port_add_v8_action(node_protocol_generated_sources)
node_port_add_v8_action(concatenate_protocols)
node_port_add_v8_action(v8_inspector_compress_protocol_json)
add_dependencies(node_protocol_generated_sources convert_node_protocol_to_json)
add_dependencies(concatenate_protocols convert_node_protocol_to_json)
add_dependencies(v8_inspector_compress_protocol_json concatenate_protocols)

# node 自己的 crdtp 副本必须**排在最前**（V8 那份也提供 crdtp/*.h）。
target_include_directories(node_base BEFORE PRIVATE "${NODE_ROOT}/deps/inspector_protocol")

target_include_directories(node_base PRIVATE
  "${NODE_PORT_NODE_GENERATED}"
  "${NODE_ROOT}/src"
  "${NODE_ROOT}/deps/postject"
  "${NODE_ROOT}/deps/googletest/include"
  "${NODE_PORT_V8_GENERATED}/src"
  "${NODE_PORT_V8_GENERATED}/include"
  "${NODE_PORT_V8_GENERATED}")

add_dependencies(node_base node_protocol_generated_sources
                           v8_inspector_compress_protocol_json)

target_link_libraries(node_base PRIVATE
  v8_headers
  v8_shared_internal_headers
  v8_internal_headers
  v8_inspector_headers
  v8_maybe_icu
  abseil
  v8_libbase
  v8_libplatform
  ncrypto
  nbytes
  merve
  uvwasi
  crdtp
  hdr_histogram::hdr_histogram_static)

# libnode（node_shared=false → 静态库；gyp 里它的"源"是 JS，不参与编译，故为 INTERFACE）。
add_library(libnode INTERFACE)

# V8 的静态库之间有**环**：GNU ld 单遍解析会漏 → Linux 用 LINK_GROUP:RESCAN；
# Apple 的链接器**不支持** RESCAN（用"库列表重复一遍"代替）；Windows 直接列。
set(NODE_PORT_NODE_V8_STATIC_LIBS
  node_base
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
  abseil)
set(NODE_PORT_NODE_V8_INTERFACE_LIBS
  v8_bigint
  v8_heap_base
  cppgc_base
  fp16
  torque_runtime_support
  torque_generated_initializers)
if(WIN32)
  # Windows：MSVC 的 link.exe 不认 LINK_GROUP，直接列（它自己会按需重扫归档）。
  target_link_libraries(libnode INTERFACE ${NODE_PORT_NODE_V8_STATIC_LIBS} ${NODE_PORT_NODE_V8_INTERFACE_LIBS})
elseif(APPLE)
  # Apple：链接器**不支持** $<LINK_GROUP:RESCAN>（CMake 直接报
  # "Feature 'RESCAN' … is not supported for the 'CXX' link language"，mac CI 实测）。
  # 而 V8 这批静态库之间确实有环 —— 用"把库列表再列一遍"代替 rescan。
  target_link_libraries(libnode INTERFACE
    ${NODE_PORT_NODE_V8_STATIC_LIBS}
    ${NODE_PORT_NODE_V8_INTERFACE_LIBS}
    ${NODE_PORT_NODE_V8_STATIC_LIBS})
else()
  # Linux：GNU ld 单遍解析会漏掉环里的符号 → 用 LINK_GROUP:RESCAN（ld 支持它）。
  target_link_libraries(libnode INTERFACE
    "$<LINK_GROUP:RESCAN,${NODE_PORT_NODE_V8_STATIC_LIBS}>"
    ${NODE_PORT_NODE_V8_INTERFACE_LIBS})
endif()

# 最终链接需要的第三方（vcpkg）：静态单 exe 的口径（工程约定第 1 条）。
find_package(OpenSSL REQUIRED)
find_package(libuv CONFIG REQUIRED)
find_package(llhttp CONFIG REQUIRED)
find_package(c-ares CONFIG REQUIRED)
find_package(unofficial-brotli CONFIG REQUIRED)
find_package(ZLIB REQUIRED)
find_package(ada CONFIG REQUIRED)
find_package(simdjson CONFIG REQUIRED)
find_package(ngtcp2 CONFIG REQUIRED)
find_package(zstd CONFIG REQUIRED)
find_package(ICU REQUIRED COMPONENTS uc i18n data)
find_package(unofficial-sqlite3 CONFIG REQUIRED)
# nghttp2 的 port 不带 CMake config 包 —— 直接按库路径链。
find_library(NODE_PORT_NGHTTP2_LIB nghttp2 PATHS
  "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH REQUIRED)

# 目标名随口径变的那几个（静态 `_static` / 动态不带）—— 见 consume.cmake 的
# `node_port_pick_target`。CI 的 `x64-windows`（动态）实测炸过 `libuv::uv_a`、`ngtcp2::ngtcp2_static`。
node_port_pick_target(_node_uv     libuv::uv_a                libuv::uv)
node_port_pick_target(_node_llhttp llhttp::llhttp_static      llhttp::llhttp)
node_port_pick_target(_node_ngtcp2 ngtcp2::ngtcp2_static      ngtcp2::ngtcp2)
node_port_pick_target(_node_zstd   zstd::libzstd_static       zstd::libzstd_shared zstd::libzstd)

add_library(node_third_party INTERFACE)
target_link_libraries(node_third_party INTERFACE
  OpenSSL::SSL
  OpenSSL::Crypto
  ${_node_uv}
  ${_node_llhttp}
  c-ares::cares
  unofficial::brotli::brotlidec
  unofficial::brotli::brotlienc
  unofficial::brotli::brotlicommon
  ZLIB::ZLIB
  ada::ada
  simdjson::simdjson
  ${_node_ngtcp2}
  ${_node_zstd}
  ICU::uc
  ICU::i18n
  ICU::data
  unofficial::sqlite3::sqlite3
  "${NODE_PORT_NGHTTP2_LIB}")

if(WIN32)
  target_link_libraries(node_third_party INTERFACE
    Dbghelp Psapi Winmm Ws2_32 Shlwapi Iphlpapi Userenv Advapi32)
endif()

# ---- node 自己的快照 --------------------------------------------------------
#
# node_use_node_snapshot=="true" 时，先链出 node_mksnapshot 工具、跑一遍 JS 启动逻辑，
# 把内建模块的堆快照落成 node_snapshot.cc，再把它当**源**编进主体。
# node_mksnapshot 自己是 `src/node_snapshot_stub.cc` + `tools/snapshot/node_mksnapshot.cc`；
# 真正的定义由生成物提供 —— 两边**必须**是两个目标，否则违反 ODR。
node_port_add_v8_target(node_mksnapshot)
target_link_libraries(node_mksnapshot PRIVATE libnode node_third_party)

# 动作的 CMake 目标要改名（动作名 node_mksnapshot 已是可执行目标）。
node_port_add_v8_action(node_mksnapshot TARGET node_mksnapshot_action)

# ---- Linux 专属的两处 -------------------------------------------------------
# 也说明 macOS 为什么**不**在这里：node_text_start 在 gyp 里只在
# `OS in "linux freebsd solaris openharmony" 且 x64` 才是 static_library，macOS 上是
# `type: none`（无源）—— 生成片段里它会存在但没有源，所以不需要建目标。
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  # node_text_start（node.gyp:555-566）：提供 __node_text_start 弱符号 + .text 对齐。
  node_port_add_v8_target(node_text_start)
endif()

# ---- node_main：快照（+ Linux postmortem）的载体，链上全部实现 --------------
#
# 它的源是**代码生成物**（node_snapshot.cc / debug-support.cc），必须与它们的动作同目录
# 才能挂依赖。node_text_start 的 .S 也经 INTERFACE 并进这里编。
add_library(node_main STATIC)
target_link_libraries(node_main PUBLIC libnode node_third_party)
node_port_patch_own_target(node_main)

target_sources(node_main PRIVATE "${NODE_PORT_V8_GENERATED}/node_snapshot.cc")
add_dependencies(node_main node_mksnapshot_action)

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  target_link_libraries(node_main PUBLIC node_text_start)
  target_sources(node_main PRIVATE "${NODE_PORT_V8_GENERATED}/debug-support.cc")
  add_dependencies(node_main postmortem-metadata)
endif()
# macOS 走不到上面这一支：debug-support.cc 是 Linux 侧的 postmortem 载体。
# （macOS 首轮 CI 若报缺符号，优先怀疑这里 —— 见 docs/调研文档.md §8.3。）

# 生成的 inspector 协议源（9 个 .cpp）也要编进 node_base。
get_property(_node_port_gen GLOBAL PROPERTY NODE_PORT_V8_GEN_DIR)
include("${_node_port_gen}/node_protocol_generated_sources_action.cmake")
target_sources(node_base PRIVATE ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_OUTPUTS})
add_dependencies(node_base node_protocol_generated_sources)

# 第三方头文件一致性：把 node 树自带副本的 include 目录从目标上摘掉。
set(_node_port_node_own_targets node_base node_mksnapshot node_main)
foreach(_t IN LISTS _node_port_node_own_targets)
  node_port_drop_bundled_include(${_t} ${NODE_PORT_BUNDLED_INCLUDE_DROP})
endforeach()