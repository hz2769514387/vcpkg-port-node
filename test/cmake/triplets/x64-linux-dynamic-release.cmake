# CI cell, not a consumer recipe - see test/README.md and issue #61.
# The stock `x64-linux-dynamic` triplet, Release only (docs/ci.md §2.1).
set(VCPKG_BUILD_TYPE release)

set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)

set(VCPKG_CMAKE_SYSTEM_NAME Linux)

set(VCPKG_FIXUP_ELF_RPATH ON)
