# vcpkg overlay triplet：arm64 / Windows / 静态 CRT / 静态库 / clang-cl。
#
# 归属：消费端（test）拥有，不是 port 的一部分。与 x64 版逐行对应，只有架构不同。
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE static)
set(VCPKG_LIBRARY_LINKAGE static)

set(VCPKG_BUILD_TYPE release)

include("${CMAKE_CURRENT_LIST_DIR}/../toolchains/msvc-command-line-env.cmake")

set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE
    "${CMAKE_CURRENT_LIST_DIR}/../toolchains/clang-cl.cmake")

set(VCPKG_CMAKE_CONFIGURE_OPTIONS "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW")
set(VCPKG_C_FLAGS "-Wno-error=incompatible-pointer-types")
set(VCPKG_CXX_FLAGS "-Wno-error=incompatible-pointer-types")
