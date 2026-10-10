# CI 用 overlay triplet：**只出 Release**（理由见 x64-windows-ci.cmake 的说明）。
# 其余口径等于 vcpkg 内置的 arm64-osx。
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
set(VCPKG_OSX_ARCHITECTURES arm64)

set(VCPKG_BUILD_TYPE release)