# CI cell, not a consumer recipe - see test/README.md and issue #61.
# `arm64-windows-static`, rebuilt with clang-cl for the whole dependency graph, Release only.
#
# The chainloaded toolchain is the part worth copying (test/cmake/toolchains/clang-cl.cmake);
# docs/consumer-recipes.md section 6 explains the shape.
set(VCPKG_BUILD_TYPE release)

set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE static)
set(VCPKG_LIBRARY_LINKAGE static)

set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${CMAKE_CURRENT_LIST_DIR}/../toolchains/clang-cl.cmake")
set(VCPKG_LOAD_VCVARS_ENV ON)
