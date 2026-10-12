# 单元测试：vcpkg 库自身可用 + 与 node port 共存。
#
# 两个可执行是有意分开的：
#   unit_vcpkg_baseline 只链 vcpkg 库 —— 出问题说明"库自己有毛病"；
#   unit_node_coexist   同时链 unofficial::node::node 与同一批库 —— 出问题说明"共存有毛病"。
# 这样失败时不用猜是库的问题还是共存的问题。

find_package(GTest CONFIG REQUIRED)
find_package(absl CONFIG REQUIRED)
find_package(hwy CONFIG REQUIRED)
find_package(fmt CONFIG REQUIRED)
find_package(ZLIB CONFIG REQUIRED)
find_package(OpenSSL REQUIRED)
find_package(libuv CONFIG REQUIRED)
find_package(simdutf CONFIG REQUIRED)
find_package(simdjson CONFIG REQUIRED)
find_package(unofficial-sqlite3 CONFIG REQUIRED)
find_package(unofficial-brotli CONFIG REQUIRED)
find_package(zstd CONFIG REQUIRED)
find_package(hdr_histogram CONFIG REQUIRED)
find_package(ICU COMPONENTS uc i18n data REQUIRED)

# nghttp2 没有 CMake 包配置（node 的消费配置里也是手工建的 imported target），
# 这里自己找头文件与库。
find_path(NGHTTP2_INCLUDE_DIR nghttp2/nghttp2.h REQUIRED)
find_library(NGHTTP2_LIBRARY NAMES nghttp2 REQUIRED)

# 这批库就是"使用者可能同时想要的"那一批：node 的直接依赖，加上与 v8 内嵌第三方
# （abseil / highway / simdutf / zlib）同名的 vcpkg port。
# ★ absl / hwy 只在"基线"那个可执行里链，不放进与 node 同时链的那批 —— 原因有实测：
# v8 用的是 abseil / highway 的**内部符号**（LNK2019 实测：SetMutexDeadlockDetectionMode /
# container_internal::DeallocateBackingArray<8> / hash_internal::MixingHashState::kSeed），
# 而且**必须**用 v8 自带的那份（换成 vcpkg 的 abseil 会在链接期挂）。于是 v8 自带一份、
# 使用者的 vcpkg 再一份 ⇒ 同一个可执行里两份同名（含内部符号）的 abseil 必然冲突。
# 这是**已知限制**，记在 docs/暂时还没做.md 5g 与 README 里；基线测试（不含 node）照常覆盖它们。
set(NODE_PORT_TEST_VCPKG_LIBS
    ZLIB::ZLIB
    OpenSSL::Crypto
    libuv::uv_a
    fmt::fmt
    simdutf::simdutf
    simdjson::simdjson
    unofficial::sqlite3::sqlite3
    unofficial::brotli::brotlidec
    unofficial::brotli::brotlienc
    unofficial::brotli::brotlicommon
    zstd::libzstd_static
    hdr_histogram::hdr_histogram_static
    ICU::uc
    ICU::i18n
    ICU::data
    "${NGHTTP2_LIBRARY}")

# ---- 基线 --------------------------------------------------------------------
add_executable(unit_vcpkg_baseline test_vcpkg_baseline.cpp)
# 基线（不链 node）里把 abseil / highway 也带上 —— 它们单独用没问题，
# 问题只出在"和 v8 自带那份同处一个可执行"时（见上面的说明）。
target_link_libraries(unit_vcpkg_baseline PRIVATE
    GTest::gtest_main ${NODE_PORT_TEST_VCPKG_LIBS} absl::base absl::strings absl::str_format hwy::hwy)
target_include_directories(unit_vcpkg_baseline PRIVATE "${NGHTTP2_INCLUDE_DIR}")
target_compile_features(unit_vcpkg_baseline PRIVATE cxx_std_20)
if(MSVC)
  # vcpkg 装的 abseil/ICU 等头文件里有 /W4 下会告警的代码；本工程的目的是测共存，
  # 不是替上游挑告警。clang-cl 同理（-Wno-* 只对本工程加上，不影响库）。
  target_compile_options(unit_vcpkg_baseline PRIVATE /W0)
endif()

# hdr_histogram 用 __builtin_cpu_supports ⇒ 引用 __cpu_model，而这个符号在 clang 的
# compiler-rt 内建库里。MSVC 前端下 CMake 直接调 lld-link、**绕过了 clang 驱动**，
# 内建库不会自动带上（node 的消费配置里也是手工补的，同一处原因）。
# 链 node 的那个可执行经由 unofficial::node::node 已经拿到了，这里（不链 node）得自己补。
if(WIN32)
  if(DEFINED NODE_PORT_CLANG_RT_BUILTINS AND EXISTS "${NODE_PORT_CLANG_RT_BUILTINS}")
    target_link_libraries(unit_vcpkg_baseline PRIVATE "${NODE_PORT_CLANG_RT_BUILTINS}")
  else()
    # 库名按架构取（与 node port 的口径一致）：x64 → x86_64，arm64 → aarch64
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
      if("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "ARM64|aarch64|AARCH64")
        set(_node_test_rt_arch "aarch64")
      else()
        set(_node_test_rt_arch "x86_64")
      endif()
    else()
      set(_node_test_rt_arch "i386")
    endif()
    target_link_libraries(unit_vcpkg_baseline PRIVATE "clang_rt.builtins-${_node_test_rt_arch}")
  endif()
endif()

add_test(NAME unit-vcpkg-baseline COMMAND unit_vcpkg_baseline)
set_tests_properties(unit-vcpkg-baseline PROPERTIES LABELS "unit" TIMEOUT 600)

# ---- 共存 --------------------------------------------------------------------
add_executable(unit_node_coexist test_node_coexist.cpp)
# ★ 只链 unofficial::node::node 本身、以及它**没有**覆盖到的东西 —— 绝不再重复列 node 已经提供的库。
#
# 为什么（这是 run #23 把 x64-linux 硬门弄红的原因，写下来防复发）：
#   node 的静态库与它依赖的 vcpkg 库由 node-config.cmake 组装成一条链接接口；
#   GNU 平台上是 CMake 的 $<LINK_GROUP:RESCAN,…>（落到链接器就是 --start-group/--end-group，
#   因为 GNU ld 单趟左到右、组内反复扫）。
#   CMake 会对链接项**去重**：这里若又显式列了组里的某个库，那次会被判成"同一份"，
#   于是**组内那份被删掉、只剩组外这份**；而组外的位置在 node 的静态库**之前**，
#   单趟扫描时它早就扫过去了 ⇒ 组内那个库的符号全部解析不了。
#   本文件原先正是这么写的 —— `node::nghttp2` 与 `"${NGHTTP2_LIBRARY}"` 是同一个
#   libnghttp2.a，各列了一遍，结果是 174 条 undefined reference 里 173 条是 nghttp2。
#
# 所以这里只留三样：
#   * GTest::gtest_main —— 测试框架；
#   * unofficial::node::node         —— node 的整棵静态库（含 v8 与 uvwasi/merve/nbytes/…）
#                           **以及它自己的依赖**（nghttp2 / ICU / OpenSSL / zlib / brotli /
#                           sqlite3 / libuv / simdjson / simdutf / zstd / c-ares / ada / llhttp）；
#   * fmt::fmt           —— node 不用 fmt，所以它不在 node 的链接接口里（本测试要单独验它）。
# nghttp2 的**头文件**不在 unofficial::node::node 的 INTERFACE 里（node::nghttp2 是手工建的 imported
# target，只给了库、没给 INTERFACE_INCLUDE_DIRECTORIES），所以头单独给；
# **符号**（源码里要调 nghttp2_version()）照样由 unofficial::node::node 的链接接口提供。
target_link_libraries(unit_node_coexist PRIVATE
    GTest::gtest_main
    unofficial::node::node          # 把 node 的整棵静态库（含 v8 与 uvwasi/merve/nbytes/...）链进来
    fmt::fmt)
target_include_directories(unit_node_coexist PRIVATE "${NGHTTP2_INCLUDE_DIR}")
target_compile_features(unit_node_coexist PRIVATE cxx_std_20)
# 用它来起子进程问 node "你用的是哪一份依赖"（交叉核对，见测试源码里的说明）。
# node_embed 的路径交给 C++ 侧拼命令行用。
# ★ 走 file(GENERATE) 写成头文件，**不要**用 target_compile_definitions：
#   * 写成 `-DNODE_EMBED_PATH="C:\...\node.exe"`（带转义引号）→ MSVC 的响应文件会把
#     开头那个 \" 吃掉，实际值是 `C:\...\node.exe"`（少一个前引号），cmd 于是报
#     "不是内部或外部命令"，现象看起来像"node 跑不起来"（实测踩到过）；
#   * 干脆不写引号（-DNODE_EMBED_PATH=C:/.../node.exe）→ 被 C++ 当 token 拆开，
#     报 `use of undeclared identifier 'C'` / 'work' / 'git' …（实测踩到过）。
#   写进头文件就没有响应文件那一层转义，字符串字面量原样落盘。
#   另外 file(GENERATE) 会展开生成器表达式，configure_file 不会。
file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/node_embed_path.h"
     CONTENT "#pragma once\n#define NODE_EMBED_PATH \"$<TARGET_FILE:node_embed>\"\n")
target_include_directories(unit_node_coexist PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
if(MSVC)
  target_compile_options(unit_node_coexist PRIVATE /W0)
endif()

add_test(NAME unit-node-coexist COMMAND unit_node_coexist)
set_tests_properties(unit-node-coexist PROPERTIES LABELS "unit;coexist" TIMEOUT 1800)
