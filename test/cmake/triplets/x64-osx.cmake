# vcpkg overlay triplet：x64 / macOS / clang / 静态库 / release-only。
#
# 归属：消费端（test）拥有，不是 port 的一部分。
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
set(VCPKG_OSX_ARCHITECTURES x64)

set(VCPKG_BUILD_TYPE release)
