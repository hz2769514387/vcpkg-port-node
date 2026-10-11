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

# 这里是**交叉**编译（x64 宿主上编 arm64 目标），所以要比 x64 版多一条：
# CMake 的 try_compile 默认会把产出的可执行**跑起来**验证；而 x64 宿主上根本执行不了
# arm64 的 exe —— 实测 zstd 的编译器检查就是这样挂的：
#     FAILED: [code=4294967295] cmTC_0ffd6.exe ... unknown error
# 设成 STATIC_LIBRARY 后 try_compile 只编译不运行（交叉编译的标准做法）。
# 注意 VCPKG_CMAKE_CONFIGURE_OPTIONS 是用 vcpkg_list 展开的，所以这里用 `;` 列表是安全的
# （与 VCPKG_C_/CXX_FLAGS 不同 —— 那两个必须写成空格分隔的单个字符串）。
set(VCPKG_CMAKE_CONFIGURE_OPTIONS
    "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW;-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY")
# 与 x64 版逐条对应；两条的来由见 x64-windows-static-clang.cmake 的注释
#（incompatible-pointer-types：upstream C 代码真不匹配；unused-command-line-argument：
# clang-cl 不实现 /MP 而上游 CMake 会加它，遇到 /WX 就变硬错误 —— gtest 即如此）。
# 必须是空格分隔的单个字符串，不能用 list(APPEND)（那会拼成 `a;b` 一个参数）。
set(VCPKG_C_FLAGS "-Wno-error=incompatible-pointer-types -Wno-unused-command-line-argument")
set(VCPKG_CXX_FLAGS "-Wno-error=incompatible-pointer-types -Wno-unused-command-line-argument")
