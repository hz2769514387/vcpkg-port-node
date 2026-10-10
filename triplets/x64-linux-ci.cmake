# CI 用 overlay triplet：**只出 Release**（理由见 x64-windows-ci.cmake 的说明）。
# 其余口径等于 vcpkg 内置的 x64-linux。
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Linux)

set(VCPKG_BUILD_TYPE release)