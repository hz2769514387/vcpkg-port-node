# 本仓库的内部测试 · vcpkg 库自身的基线（**不链 node**）
#
# 它回答的是"库自己有没有毛病"：这一批 vcpkg 库（node 的直接依赖 + 与 v8 内嵌第三方
# 同名的 abseil / highway / simdutf / zlib）单独用的时候是不是好的。
# 一旦这里红了，而链了 node 的那组没红 ⇒ 问题在**共存**，不在库本身。
# （与它配对的是 test_node_coexist：那边同时链 node。）
#
# 与 example_embed / example_coexist 的关系：**没有**。删掉任何一个示例，本测试照跑。
#
# absl / hwy 只在这个"基线"里链：
# v8 用的是 abseil / highway 的**内部符号**（LNK2019 实测：SetMutexDeadlockDetectionMode /
# container_internal::DeallocateBackingArray<8> / hash_internal::MixingHashState::kSeed），
# 而且**必须**用 v8 自带那份（换成 vcpkg 的 abseil 会在链接期挂）⇒
# v8 自带一份、使用者的 vcpkg 再一份，同一个可执行里两份同名（含内部符号）的 abseil
# 必然冲突。这是**已知限制**，记在 docs/暂时还没做.md 5g 与 README 里；
# 基线测试（不含 node）照常覆盖它们。

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

# nghttp2 没有 CMake 包配置（node 的消费配置里也是手工建的 imported target），自己找。
find_path(NGHTTP2_INCLUDE_DIR nghttp2/nghttp2.h REQUIRED)
find_library(NGHTTP2_LIBRARY NAMES nghttp2 REQUIRED)

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

add_executable(test_vcpkg_baseline test_vcpkg_baseline.cpp)
target_link_libraries(test_vcpkg_baseline PRIVATE
    GTest::gtest_main ${NODE_PORT_TEST_VCPKG_LIBS} absl::base absl::strings absl::str_format hwy::hwy)
target_include_directories(test_vcpkg_baseline PRIVATE "${NGHTTP2_INCLUDE_DIR}")
target_compile_features(test_vcpkg_baseline PRIVATE cxx_std_20)
if(MSVC)
  # vcpkg 装的 abseil/ICU 等头文件在 /W4 下会告警；目的是测共存，不是替上游挑告警。
  target_compile_options(test_vcpkg_baseline PRIVATE /W0)
endif()

# hdr_histogram 用 __builtin_cpu_supports ⇒ 引用 __cpu_model，而这个符号在 clang 的
# compiler-rt 内建库里。MSVC 前端下 CMake 直接调 lld-link、**绕过了 clang 驱动**，
# 内建库不会自动带上（node 的消费配置里也是手工补的，同一处原因）。
# 链 node 的那组经由 unofficial::node::node 已经拿到了，这里（不链 node）得自己补。
if(WIN32)
  if(DEFINED NODE_PORT_CLANG_RT_BUILTINS AND EXISTS "${NODE_PORT_CLANG_RT_BUILTINS}")
    target_link_libraries(test_vcpkg_baseline PRIVATE "${NODE_PORT_CLANG_RT_BUILTINS}")
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
    target_link_libraries(test_vcpkg_baseline PRIVATE "clang_rt.builtins-${_node_test_rt_arch}")
  endif()
endif()

add_test(NAME test-vcpkg-baseline COMMAND test_vcpkg_baseline)
set_tests_properties(test-vcpkg-baseline PROPERTIES LABELS "internal;vcpkg" TIMEOUT 600)
