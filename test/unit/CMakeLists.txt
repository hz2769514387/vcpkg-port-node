# 单元测试：vcpkg 库自身可用 + 与 node port 共存。
#
# 两个可执行是有意分开的：
#   unit_vcpkg_baseline 只链 vcpkg 库 —— 出问题说明"库自己有毛病"；
#   unit_node_coexist   同时链 node::node 与同一批库 —— 出问题说明"共存有毛病"。
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
set(NODE_PORT_TEST_VCPKG_LIBS
    ZLIB::ZLIB
    OpenSSL::Crypto
    libuv::uv_a
    fmt::fmt
    absl::base
    absl::strings
    absl::str_format
    hwy::hwy
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
target_link_libraries(unit_vcpkg_baseline PRIVATE GTest::gtest_main ${NODE_PORT_TEST_VCPKG_LIBS})
target_include_directories(unit_vcpkg_baseline PRIVATE "${NGHTTP2_INCLUDE_DIR}")
target_compile_features(unit_vcpkg_baseline PRIVATE cxx_std_20)
if(MSVC)
  # vcpkg 装的 abseil/ICU 等头文件里有 /W4 下会告警的代码；本工程的目的是测共存，
  # 不是替上游挑告警。clang-cl 同理（-Wno-* 只对本工程加上，不影响库）。
  target_compile_options(unit_vcpkg_baseline PRIVATE /W0)
endif()

add_test(NAME unit-vcpkg-baseline COMMAND unit_vcpkg_baseline)
set_tests_properties(unit-vcpkg-baseline PROPERTIES LABELS "unit" TIMEOUT 600)

# ---- 共存 --------------------------------------------------------------------
add_executable(unit_node_coexist test_node_coexist.cpp)
target_link_libraries(unit_node_coexist PRIVATE
    GTest::gtest_main
    node::node          # 把 node 的整棵静态库（含 v8 与 uvwasi/merve/nbytes/...）链进来
    node::nghttp2
    ${NODE_PORT_TEST_VCPKG_LIBS})
target_include_directories(unit_node_coexist PRIVATE "${NGHTTP2_INCLUDE_DIR}")
target_compile_features(unit_node_coexist PRIVATE cxx_std_20)
# 用它来起子进程问 node "你用的是哪一份依赖"（交叉核对，见测试源码里的说明）。
target_compile_definitions(unit_node_coexist PRIVATE
    "NODE_EMBED_PATH=\"$<TARGET_FILE:node_embed>\"")
if(MSVC)
  target_compile_options(unit_node_coexist PRIVATE /W0)
endif()

add_test(NAME unit-node-coexist COMMAND unit_node_coexist)
set_tests_properties(unit-node-coexist PROPERTIES LABELS "unit;coexist" TIMEOUT 1800)
