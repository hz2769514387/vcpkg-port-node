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

# 这里原本加了 `-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY`（交叉编译的常规做法：
# CMake 默认会**运行** try_compile 产出的可执行来验证，而 x64 宿主跑不了 arm64 的 exe，
# 实测 zstd 报 `FAILED: cmTC_0ffd6.exe ... unknown error`）。
#
# **但它已被撤掉**，因为它有更坏的副作用：设成 STATIC_LIBRARY 之后 try_compile 不再链接，
# 于是所有"库存在性"检查（check_library_exists 这类）都会**误报成功** —— 实测 brotli 因此
# 以为 libm 存在，往链接行加了 `-lm`，最终 `lld-link: could not open 'm.lib'`。
# 也就是说：这一档目前没有干净的走法，真正的障碍在 node 自己（构建期工具 mksnapshot /
# torque 必须在宿主上**运行**，交叉构建需要单独的 host toolset）——
# 详见 docs/暂时还没做.md 第 2 项。宁可让它挂在"跑不了 arm64 exe"这个一眼能懂的地方。
set(VCPKG_CMAKE_CONFIGURE_OPTIONS "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW")
# 与 x64 版逐条对应；两条的来由见 x64-windows-static-clang.cmake 的注释
#（incompatible-pointer-types：upstream C 代码真不匹配；unused-command-line-argument：
# clang-cl 不实现 /MP 而上游 CMake 会加它，遇到 /WX 就变硬错误 —— gtest 即如此）。
# 必须是空格分隔的单个字符串，不能用 list(APPEND)（那会拼成 `a;b` 一个参数）。
set(VCPKG_C_FLAGS "-Wno-error=incompatible-pointer-types -Wno-unused-command-line-argument")
set(VCPKG_CXX_FLAGS "-Wno-error=incompatible-pointer-types -Wno-unused-command-line-argument")
