# CI 用 overlay triplet：**只出 Release**。
#
# 为什么需要它：`VCPKG_BUILD_TYPE` 是 **triplet 变量**，不是环境变量 —— 光在 workflow 的
# `env:` 里设 `VCPKG_BUILD_TYPE=release` **不生效**（mac CI 实测：debug 也在编）。而默认
# triplet 会同时编 debug+release，对本 port（V8 整棵树）等于磁盘/时长翻倍。
#
# 其余口径**等于 vcpkg 内置的 x64-windows**（MSVC + 动态 CRT + 动态库）。
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)
set(VCPKG_PROVIDED_FORTRAN ON)

set(VCPKG_BUILD_TYPE release)