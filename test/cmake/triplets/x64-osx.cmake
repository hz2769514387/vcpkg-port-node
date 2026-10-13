# vcpkg overlay triplet：x64 / macOS / clang / 静态库 / release-only。
#
# 归属：消费端（test）拥有，不是 port 的一部分。
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
set(VCPKG_OSX_ARCHITECTURES x64)

# ★ 依赖**永远 release-only**，哪怕要编 node 的 debug。
#   试过让依赖也进 debug（VCPKG_BUILD_TYPE=debug），结果是 brotli 直接 BUILD_FAILED：
#   它的 portfile 调 vcpkg_copy_tools，而 debug-only 时 vcpkg 把可执行放到 debug/tools/，
#   于是 "SEARCH_DIR .../tools/brotli must be a directory"（2026-10-14 实测，arm64-linux）。
#   这类上游 port 不只一个 ⇒ 依赖保持 release；node 自己按 debug 编（见 portfile）。
set(VCPKG_BUILD_TYPE release)
