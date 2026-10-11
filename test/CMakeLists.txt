# node port 的消费端示例（主项目）。
#
# 这是一个**独立于 port** 的示例工程，站在"使用者"的视角演示推荐接入方式：
#   * 依赖声明用 vcpkg manifest（`vcpkg.json`）；
#   * overlay-port / overlay-triplet 由 `vcpkg-configuration.json` 指向本仓库；
#   * 构建入口统一走 `CMakePresets.json` 的 preset（不必手敲一长串 -D）。
#
# 依赖方向只有一条：本工程 ──> ports/node（经 overlay-ports）。
# port 目录里没有任何 triplet / toolchain，也不引用 port 目录外的文件；
# 本工程自己拥有 cmake/{toolchains,triplets}，并在 triplet 里用 vcpkg 的标准变量
# VCPKG_CHAINLOAD_TOOLCHAIN_FILE 把 clang-cl 工具链交接给 port。
#
# 用法（本目录下，按 host 选 preset）：
#   cmake --preset windows-clang-cl        # Windows x64
#   cmake --preset windows-clang-cl-arm64  # Windows arm64（未实测）
#   cmake --preset linux                   # Linux x64
#   cmake --preset linux-arm64             # Linux arm64
#   cmake --preset macos                   # macOS arm64
#   cmake --preset macos-x64               # macOS x64（未实测）
#   cmake --build --preset <同上的 preset>
#   ./build/<preset>/app/smoke -e "console.log(process.versions.node)"
#
# 需要环境变量 VCPKG_ROOT 指向 vcpkg 安装根（preset 里用它定位 toolchain）。
#
# 工程结构是"主项目 + 子项目"：
#   test/           主项目：只做 find_package(node)（依赖查找）
#   test/app/       子项目：真正嵌入 node 的可执行（链接 node::node）
# 使用者自己的多目标工程可以照此把 node 依赖收敛在主项目里。
cmake_minimum_required(VERSION 3.21)

project(node_port_smoke LANGUAGES CXX)

# node 由 vcpkg 装出，提供 CONFIG 包（`find_package(node CONFIG)`）与
# imported 目标 `node::node`（含传递依赖与平台链接选项）。
find_package(node CONFIG REQUIRED)

add_subdirectory(app)
