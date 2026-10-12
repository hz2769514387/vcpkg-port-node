# vcpkg overlay triplet：x64 / Windows / 静态 CRT / 静态库 / clang-cl。
#
# 归属：这是 **消费端（test 项目）拥有** 的构建配置，不是 port 的一部分。按 vcpkg 规则，
# triplet / toolchain 属于使用者一侧；port 自带 triplet 会让它无法在别人的 triplet 下工作，
# 也无法提交到 registry。依赖链只有单向：test ──(overlay-ports)──> ports/node。
#
# 为什么是 clang-cl：node 24+ 官方在 Windows 上强制 ClangCL
# （vcbuild.bat 里 `if NODE_MAJOR_VERSION GEQ 24 → set clang_cl=1`），port 沿用同一口径。

set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE static)
set(VCPKG_LIBRARY_LINKAGE static)

# 只出发布构建（少一半产物，CI/本地都省磁盘）。
set(VCPKG_BUILD_TYPE release)

# nmake 与 INCLUDE/LIB 必须在任何 port 构建之前就位 —— 包括那些不走 CMake、
# 因而不会加载 chainload toolchain 的 port（openssl 用 nmake 构建）。
# triplet 由 vcpkg 在 portfile.cmake 之前 include（scripts/ports.cmake），所以这里设的
# 环境变量对 portfile 也可见 —— port 只读环境，不需要自己携带 toolchain 文件。
include("${CMAKE_CURRENT_LIST_DIR}/../toolchains/msvc-command-line-env.cmake")

# 为什么用 VCPKG_CHAINLOAD_TOOLCHAIN_FILE（而不是在本文件里直接 include clang-cl）：
# 这是 vcpkg 的标准机制 —— vcpkg 会把这里的值作为 `-DVCPKG_CHAINLOAD_TOOLCHAIN_FILE=…`
# 传给该 port 的 cmake。直接 include 会让工具链落在"编译探测之前"这个不确定的时机上。
# 附带收益：portfile.cmake 从同一个变量拿到 clang-cl 路径，于是 port 里没有任何 toolchain。
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE
    "${CMAKE_CURRENT_LIST_DIR}/../toolchains/clang-cl.cmake")

# CMAKE_MSVC_RUNTIME_LIBRARY 只在 CMP0091 为 NEW 时有效，而 cmake_minimum_required() 早于
# 3.15 的 port 会拿到 OLD —— c-ares 要的是 3.5。那种 port 会按 DLL CRT 编译，
# 而我们最终链接一律静态 CRT，两边的错配只在链接期暴露：port 的目标文件从 msvcrt.lib
# 导入，而静态 CRT 的链接本来根本不会去要那些 UCRT 入口（c-ares 的 strncat 是第一个）。
# 在 configure 命令行上传策略才有效 —— 写在 chainload 的 toolchain 里已经太晚，
# 那个文件是被 project() 读的，而 cmake_minimum_required() 早就选完了。
set(VCPKG_CMAKE_CONFIGURE_OPTIONS "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW")

# clang-cl 22.x（VS 18 自带）比 19.x 严格：-Wincompatible-pointer-types 默认是 error。
# hdr-histogram 等 upstream C 代码有真实的类型不匹配（uint32_t* vs unsigned long*），
# 在 MSVC 上是 warning，在 clang-cl 上是 error。降为 warning 以便构建通过。
#
# ★ VCPKG_C_FLAGS / VCPKG_CXX_FLAGS 必须是**空格分隔的单个字符串**，不能用
#   list(APPEND)。它们会被直接拼进编译命令，列表会被写成 `-Wno-a;-Wno-b` 这种
#   **一个**参数（分号没被拆开），clang-cl 只会报 "argument unused" —— 实测就是这么
#   把 gtest 搞挂的。
#
# ★ `--target=x86_64-pc-windows-msvc` 是**显式写出来的**（虽然 clang-cl 的宿主默认
#   就是它，不写也能过）：不经 CMake 的端口（icu 走 autotools/vcpkg-make）只看这两个
#   变量，没有目标三元组就会退回宿主默认值 —— arm64 那一档就是这么死的
#   （见 arm64-windows-static-clang.cmake 里的 config.log 证据）。
#   写清楚，别让"默认值恰好对"成为一档平台的隐性依赖。
set(VCPKG_C_FLAGS "-Wno-error=incompatible-pointer-types -Wno-unused-command-line-argument --target=x86_64-pc-windows-msvc")
set(VCPKG_CXX_FLAGS "-Wno-error=incompatible-pointer-types -Wno-unused-command-line-argument --target=x86_64-pc-windows-msvc")

# 第二条抑制开关（-Wno-unused-command-line-argument）的来由：
# clang-cl 不实现 MSVC 的 /MP（多进程编译），而上游 CMake 工程只要 `if(MSVC)` 就会加它，
# 工程自己再开 /WX（warnings as errors）时，这条 warning 就成了硬错误。实测 gtest 的
# CMake（googlemock / googletest）正是这么挂的：
#     clang-cl: error: argument unused during compilation: '/MP' [-Werror,-Wunused-command-line-argument]
# 用 -Wno-（彻底关掉）而不是 -Wno-error=：工程自己的 /WX 排在后面，会把 -Wno-error= 重新
# 打开，而 -Wno- 关掉的警告不会被通用的 -Werror 复活。只关这一条，不做"把 /W4 降成 /W0"
# 那种大扫除 —— 那会把真问题一起盖掉。
