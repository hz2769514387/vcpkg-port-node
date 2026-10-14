# vcpkg overlay triplet：x64 / macOS / clang / 静态库 / release-only。
#
# 归属：消费端（test）拥有，不是 port 的一部分。
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
# ★ 必须是 `x86_64`，不能写 `x64`：vcpkg 的 vcpkg_configure_cmake 把
#   VCPKG_OSX_ARCHITECTURES 原样转成 -DCMAKE_OSX_ARCHITECTURES，落到 clang
#   就是 `-arch x64` —— clang 只认 x86_64/i386/arm64...，直接
#   `clang: error: invalid arch name '-arch x64'`（2026-10-14 run #38 实测：
#   x64-osx 腿在 vcpkg detect_compiler 阶段 0.58 秒挂掉）。vcpkg 自家的
#   community/x64-osx 与 arm64-osx triplet 用的也是 x86_64 / arm64 这套名字。
#   VCPKG_TARGET_ARCHITECTURE 保持 x64 —— 那是 vcpkg 自己的架构命名
#   （映射到 CMAKE_SYSTEM_PROCESSOR=x86_64），两者不是一套词汇。
set(VCPKG_OSX_ARCHITECTURES x86_64)

# ★ 依赖**永远 release-only**，哪怕要编 node 的 debug。
#   试过让依赖也进 debug（VCPKG_BUILD_TYPE=debug），结果是 brotli 直接 BUILD_FAILED：
#   它的 portfile 调 vcpkg_copy_tools，而 debug-only 时 vcpkg 把可执行放到 debug/tools/，
#   于是 "SEARCH_DIR .../tools/brotli must be a directory"（2026-10-14 实测，arm64-linux）。
#   这类上游 port 不只一个 ⇒ 依赖保持 release；node 自己按 debug 编（见 portfile）。
set(VCPKG_BUILD_TYPE release)
