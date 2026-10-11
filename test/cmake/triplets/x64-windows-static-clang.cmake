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
set(VCPKG_C_FLAGS "-Wno-error=incompatible-pointer-types")
set(VCPKG_CXX_FLAGS "-Wno-error=incompatible-pointer-types")
