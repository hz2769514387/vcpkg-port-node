# node port —— 把 Node.js v24.21.0 整棵树编成可链接的 node 静态库。
#
# 干三件事：
#   1. 按 vcpkg 标准下载流取 Node.js v24.21.0 官方源码包（离线时把同文件放进
#      $VCPKG_ROOT/downloads/ 即可，vcpkg 校验 SHA512 后直接复用本地文件）；
#   2. 用本目录自带的构建工程（project/，含 gyp2vcpkg 生成的 CMake 片段）把整棵树
#      编成可链接的 `node`（含 V8 与全部依赖）；
#   3. 安装头文件 + 静态库 + CMake 消费配置（`node`），供消费方
#      `find_package(node)` + `target_link_libraries(<自己的目标> PRIVATE node::node)`。
#
# Node 的官方依赖由本 port 的 vcpkg.json 声明 —— 消费方经传递依赖拿到，
# 自身清单只需依赖本 port。
#
# 构建期 python 只用 vcpkg 的 tools（vcpkg_find_acquire_program）—— 不要求系统装 python。
#
# 口径说明：
#   * CRT 跟随所选三元组（vcpkg 默认 x64-windows 为动态 CRT；静态 CRT 见仓库 triplets/）；
#   * 编译器与三元组一致（Windows 默认 MSVC；clang-cl 口径见仓库 triplets/ 与 toolchains/）。

# 1) 下载（或复用本地 downloads）并校验 SHA512
vcpkg_download_distfile(
    NODE_ARCHIVE
    URLS "https://nodejs.org/dist/v24.21.0/node-v24.21.0.tar.gz"
    SHA512 8bb098aa786298ceaf25797adb5551ff4edcafcdc19a669e530a42c60ca71c1b12da2f93253ded2dd7e9ac5a5d0a922e81789542912905e1c16b1754dcf628b8
    FILENAME nodejs-node-v24.21.0.tar.gz
)

# 2) 解压（去掉顶层 node-v24.21.0/ 一层）
vcpkg_extract_source_archive(
    SOURCE_PATH
    ARCHIVE "${NODE_ARCHIVE}"
    SOURCE_BASE node-v24.21.0
)

# 3) 构建期 python 工具（gyp2vcpkg 与 node 树自带的 .py 脚本都要它）
vcpkg_find_acquire_program(PYTHON3)

# 4) 把本 port 的构建工程与 gyp2vcpkg 工具拷进源码树（构建工程从源码树读源码）
file(COPY "${CMAKE_CURRENT_LIST_DIR}/project" DESTINATION "${SOURCE_PATH}")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/gyp2vcpkg" DESTINATION "${SOURCE_PATH}")

# 5) 配置 + 构建 + 安装
vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}/project"
    OPTIONS
        "-DNODE_ROOT=${SOURCE_PATH}"
        "-DPython3_EXECUTABLE=${PYTHON3}"
    MAYBE_UNUSED_VARIABLES
        Python3_EXECUTABLE
)
vcpkg_cmake_build()
vcpkg_cmake_install()

# 6) 收尾
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")