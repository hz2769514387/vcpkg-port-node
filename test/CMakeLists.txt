# node port 的消费端验证工程（主项目）。
#
# 这个工程站在**使用者**视角回答两个问题：
#   1) node port 能不能被正常接入？（overlay-port + manifest + CMake preset）
#   2) 把 node port 和一堆 vcpkg 库（含与 v8 内嵌同名的 abseil / highway / simdutf / zlib）
#      一起链进同一个使用者工程，会不会出问题？
#
# 它**不是**最小冒烟，而是真跑东西：
#   app/     最小但忠实的 node 嵌入可执行（也是官方套件的 shell）
#   unit/    gtest 单元测试：vcpkg 库自身可用 + 与 node 共存（版本交叉核对）
#   coexist/ 行为级共存：一段 JS 把 zlib/brotli/crypto/ICU/ada/nghttp2/llhttp/sqlite/
#            worker_threads/wasm 全走一遍，全部由链接进来的那份库提供
#   tests/   把 node 官方测试套件（tools/test.py --shell=<本工程的可执行>）与
#            符号审计注册成 ctest 用例
#
# 依赖方向只有一条：本工程 ──(overlay-ports)──> ports/node。
cmake_minimum_required(VERSION 3.21)

project(node_port_test LANGUAGES CXX)

# ---------------------------------------------------------------------------
# 可调项（CI 用 -D 覆盖）
# ---------------------------------------------------------------------------
option(NODE_PORT_TEST_NODE_SUITE
       "注册 node 官方测试套件为 ctest 用例（需要 node 的 test-suite feature）" ON)

set(NODE_PORT_TEST_SUITES
    "parallel,sequential,message,abort,async-hooks,known_issues,module-hooks,es-module,report"
    CACHE STRING "要跑的 node 官方套件（逗号分隔）。空 = 用 test.py 的默认集合")

set(NODE_PORT_TEST_SHARDS
    ""
    CACHE STRING "把每个套件切成 N 片（test.py --run=<片>,<N>）；空 = 不分片")

set(NODE_PORT_TEST_SKIP
    ""
    CACHE STRING
    "**额外**的跳过表（逗号分隔），追加到本工程自己的跳过清单之后。
本工程长期有效的跳过清单在 cmake/node-suite-skips.txt —— 单一来源、按平台生效、每条必须写理由。
这个变量只放临时/一次性的额外跳过：长期条目要挪进那个文件，否则绕过了“理由必须写清”的检查。")

set(NODE_PORT_TEST_JOBS
    ""
    CACHE STRING "test.py 的 -j；空 = 交给 test.py 按核数决定")

set(NODE_PORT_TEST_SUITE_TIMEOUT
    5400
    CACHE STRING "单个套件/分片的 ctest 超时（秒）")

set(NODE_PORT_TEST_FLAKY_MODE
    "dontcare"
    CACHE STRING "test.py --flaky-tests 的取值（run|skip|dontcare|keep_retrying）。我们不是上游 CI，默认 dontcare：被上游标成 flaky 的用例照跑，但不拿它的失败去点红灯。")

# node 由 vcpkg 装出，提供 CONFIG 包（`find_package(unofficial-node CONFIG)`）与 imported 目标
# `unofficial::node::node`（含传递依赖与平台链接选项）。
find_package(unofficial-node CONFIG REQUIRED)

# 跑官方套件与符号审计都要 python（node 自带的 driver 就是 python）。
find_package(Python3 COMPONENTS Interpreter)

enable_testing()

add_subdirectory(app)
add_subdirectory(unit)
add_subdirectory(coexist)

include(${CMAKE_CURRENT_LIST_DIR}/tests/ctest_node_suite.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/tests/ctest_symbols.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/tests/ctest_tools.cmake)

# ---------------------------------------------------------------------------
# 一眼看清这次会跑什么（CI 日志里很有用）
# ---------------------------------------------------------------------------
message(STATUS "node port 测试工程：")
# ★ 改名后这两个变量的前缀也跟着变（否则会**静默变空**：CMake 按 find_package 的名字设 `<pkg>_VERSION` / `<pkg>_DIR`）。
#   这里索性两个都打出来，改一次命名空间就能立刻看出有没有漏改。
message(STATUS "  node 版本        : ${unofficial-node_VERSION}（旧名变量 ${node_VERSION} 应为空）")
message(STATUS "  node 头文件      : ${unofficial-node_DIR}")
message(STATUS "  官方套件目录     : ${node_TEST_SUITE_DIR}")
message(STATUS "  套件             : ${NODE_PORT_TEST_SUITES}")
message(STATUS "  分片             : '${NODE_PORT_TEST_SHARDS}'")
message(STATUS "  python3          : ${Python3_EXECUTABLE}")
