# vcpkg overlay triplet：arm64 / Windows / 静态 CRT / 静态库 / clang-cl。
#
# 归属：消费端（test）拥有，不是 port 的一部分。与 x64 版逐行对应，只有架构不同。
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE static)
set(VCPKG_LIBRARY_LINKAGE static)

# ★ 依赖**永远 release-only**，哪怕要编 node 的 debug。
#   试过让依赖也进 debug（VCPKG_BUILD_TYPE=debug），结果是 brotli 直接 BUILD_FAILED：
#   它的 portfile 调 vcpkg_copy_tools，而 debug-only 时 vcpkg 把可执行放到 debug/tools/，
#   于是 "SEARCH_DIR .../tools/brotli must be a directory"（2026-10-14 实测，arm64-linux）。
#   这类上游 port 不只一个 ⇒ 依赖保持 release；node 自己按 debug 编（见 portfile）。
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
#
# ★ `--target=aarch64-pc-windows-msvc` 是**交叉编译的必需项**，不是冗余：
#   CMake 端口由 chainload toolchain 里的 CMAKE_C_COMPILER_TARGET 覆盖（CMake 自己会
#   加 --target=），但**不经 CMake 的端口**只看 triplet 的 VCPKG_C_FLAGS/CXX_FLAGS ——
#   icu 走 autotools（vcpkg-make）就是这种。少了它 clang-cl 退回宿主默认的
#   x86_64-pc-windows-msvc，编出 x64 目标文件，链接期报
#     lld-link: error: …\conftest-….obj: machine type x64 conflicts with arm64
#   而 autotools 只会把它读成 "error: C compiler cannot create executables"
#   （run #21 实测，config.log 里那一行才是真因）。
set(VCPKG_C_FLAGS "-Wno-error=incompatible-pointer-types -Wno-unused-command-line-argument --target=aarch64-pc-windows-msvc")
set(VCPKG_CXX_FLAGS "-Wno-error=incompatible-pointer-types -Wno-unused-command-line-argument --target=aarch64-pc-windows-msvc")

# ★ 把 --target 塞进 ENV{CC}/ENV{CXX} —— autotools 端口（如 icu）的链接测试靠它。
#
# 背景：vcpkg_configure_make 的 z_vcpkg_configure_make_process_flags 会把 CFLAGS 和
# CXXFLAGS 的公共部分（--target=…）移到 CPPFLAGS。但 configure 的链接测试
# （"C compiler cannot create executables"）不带 $CPPFLAGS，只看 $CC + $CFLAGS，
# 于是 --target 丢失 → clang-cl 退回宿主默认的 x86_64 →
#   lld-link: error: …\conftest-….obj: machine type x64 conflicts with arm64
#
# 修法：z_vcpkg_append_to_configure_environment 在 CMAKE_HOST_WIN32 上会**优先用
# ENV{CC}** 而不是默认的 `compile ${VCPKG_DETECTED_CMAKE_C_COMPILER}`。
# 把 ENV{CC} 设成 `compile clang-cl.exe --target=…`，automake 的 compile 包装器
# 会把 --target=… 透传给 clang-cl.exe（`-*` 分支直通，见 automake lib/compile），
# 链接测试就能编出 ARM64 目标文件。
#
# 为什么放三元组而不是 toolchain：z_vcpkg_get_cmake_vars 跑的是**子进程**，
# toolchain 文件在那个子进程里加载——set(ENV{CC} …) 只影响子进程，
# 回到 portfile 的 CMake 进程时 ENV{CC} 已经没了。三元组文件在 portfile
# 的 CMake 进程里加载，ENV{CC} 能活到 z_vcpkg_append_to_configure_environment 检查它。
# compile 和 clang-cl.exe 在 configure 运行时都在 PATH 里（vcpkg_configure_make
# 会把 make_wrapper / automake 目录和编译器目录加到 PATH）。
set(ENV{CC} "compile clang-cl.exe --target=aarch64-pc-windows-msvc")
set(ENV{CXX} "compile clang-cl.exe --target=aarch64-pc-windows-msvc")
