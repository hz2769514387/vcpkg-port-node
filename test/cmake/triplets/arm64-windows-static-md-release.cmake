# CI cell, not a consumer recipe - see test/README.md and issue #61.
# The stock `arm64-windows-static-md` triplet (static libnode, dynamic CRT), Release only
# (docs/ci.md §2.1).
set(VCPKG_BUILD_TYPE release)

set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
