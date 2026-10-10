# node port 的消费端冒烟工程。
#
# 它**不是** port 的一部分，而是"以使用者的方式"验证 port：
#   find_package(node) + 链接 node::node + 真跑一段 JS。
#
# 用法（classic 模式，先装依赖再配置；CI 也是这么用）：
#   vcpkg install node:<triplet> --overlay-ports=<repo>/ports
#   cmake -S test -B build -G Ninja \
#         -DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake \
#         -DVCPKG_TARGET_TRIPLET=<triplet> -DVCPKG_MANIFEST_MODE=OFF
#   cmake --build build
#   ./build/smoke -e "console.log(process.versions.node)"
cmake_minimum_required(VERSION 3.20)

project(node_port_smoke LANGUAGES CXX)

find_package(node CONFIG REQUIRED)

add_executable(smoke main.cpp)
target_link_libraries(smoke PRIVATE node::node)
target_compile_features(smoke PRIVATE cxx_std_17)

# Windows：目标必须嵌 node 的平台兼容性清单，否则进程一启动就退出码 216（实测）。
# node 的消费配置导出了清单路径变量 `node_NODE_SOURCE_MANIFEST`。
if(WIN32 AND DEFINED node_NODE_SOURCE_MANIFEST AND EXISTS "${node_NODE_SOURCE_MANIFEST}")
  target_link_options(smoke PRIVATE
    "/MANIFEST:EMBED"
    "/MANIFESTINPUT:${node_NODE_SOURCE_MANIFEST}")
endif()