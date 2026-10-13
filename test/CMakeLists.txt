# node port 的消费端验证工程（主项目）。
#
# 这个工程站在**使用者**视角回答两个问题：
#   1) node port 能不能被正常接入？（overlay-port + manifest + CMake preset）
#   2) 把 node port 和一堆 vcpkg 库（含与 v8 内嵌同名的 abseil / highway / simdutf / zlib）
#      一起链进同一个使用者工程，会不会出问题？
#
# ---------------------------------------------------------------------------
# 目录分成**两组**，看前缀就能分清：
#
#   example_*  = 给**消费方**看的示例。每个示例只演示一种使用场景，而且**自带测试**
#                （示例必须能跑通；顺带也给消费方做个"项目该有测试"的样子）。
#                example_embed          把 node 嵌进自己的可执行（主线程直调）
#                example_coexist        node 与 vcpkg 同名库共存（行为级）
#                example_host_exit      宿主收场：node 的退出码语义（0/1/N）
#                example_thread_loop    消息循环分离：node 在 worker 线程，宿主主循环照跳
#                example_spawn_child    不链接，把 tools feature 的 node 当子进程
#                example_worker_threads 嵌入运行时里 worker_threads 仍完整
#                example_multitarget    分层工程：静态库 PRIVATE 藏 node + 多目标两种接法
#
#   test_*     = **本仓库自己**的内部测试（验证这个 port 有没有做对）：
#                test_vcpkg_baseline  vcpkg 那批库自身正常（不链 node）
#                test_node_coexist    node 报的依赖是不是 vcpkg 装的那份（交叉核对）
#                test_official_suite  node 官方测试套件
#                test_symbols         符号审计（重复强符号）
#                test_tools           tools feature 的 npm/npx/corepack 冒烟
#
#   两条纪律：
#     * 不重复：同一件事只在一个地方做（示例演示"怎么用"，内部测试核对"对不对"）；
#     * 不耦合：任何 example_* / test_* 都可以单独删掉，不影响其它任何一个。
#
#   cmake/ 是共享的（triplets / toolchains / 跳过清单），不属于上面两组。
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

set(NODE_PORT_TEST_NODE_ARGS
    ""
    CACHE STRING
    "透传给**每个**官方套件用例的 node 参数（逗号分隔，即 test.py 的 --node-args 口径）。
用途：崩溃诊断。CI 上设成 `--report-on-fatalerror,--report-directory=<目录>`，
让“零输出 + 非零退出”那种静默 fast-fail 能留下一份带 nativeStack 的报告
（run #32 实测：Windows 上 http/https 一族 7 条以 0xC0000409 静默死掉，日志里只有退出码）。")

# ★ 防“docstring 里未转义的 ASCII 引号把 set() 参数冲散”这类静默损坏。
#   2026-10-14 实测中招：NODE_PORT_TEST_NODE_ARGS 的 docstring 里写了
#   让"零输出 + 非零退出"那种（ASCII 引号没转义）⇒ CMake 在那里截断字符串，
#   cache 值变成 `CACHE;STRING;透传…;零输出;+;非零退出;…` 碎片 ⇒ test.py 把
#   `+` 当成测试名模式，Python 3.13 直接 re.PatternError 炸在官方套件门口。
#   这种错误**任何 CMake 解析都不报**（语法完全合法），只有值变了。
#   所以在这里对全部开关变量做一次形状检查：正常取值不可能含 CACHE/STRING
#   这两个词；含了就是被冲散了，配置期当场 FATAL，别等套件跑起来才红。
foreach(_node_port_var
    NODE_PORT_TEST_NODE_SUITE
    NODE_PORT_TEST_SUITES
    NODE_PORT_TEST_SHARDS
    NODE_PORT_TEST_SKIP
    NODE_PORT_TEST_JOBS
    NODE_PORT_TEST_SUITE_TIMEOUT
    NODE_PORT_TEST_FLAKY_MODE
    NODE_PORT_TEST_NODE_ARGS)
  if("${${_node_port_var}}" MATCHES "CACHE|STRING")
    message(FATAL_ERROR
      "${_node_port_var} 的值被 docstring 里的未转义引号冲碎了：\n"
      "  ${${_node_port_var}}\n"
      "两件事：\n"
      "  1) 修 test/CMakeLists.txt 里对应的 set(... CACHE STRING \"...\") —— "
      "docstring 内的 ASCII 双引号必须写成 \\\" 或改用中文引号“”；\n"
      "  2) 清掉构建目录里被污染的 cache 值（cache 不会因为改了源码自己恢复）：\n"
      "     cmake --preset <名字> -D${_node_port_var}=<正确值>")
  endif()
endforeach()
unset(_node_port_var)

# node 由 vcpkg 装出，提供 CONFIG 包（`find_package(unofficial-node CONFIG)`）与 imported 目标
# `unofficial::node::node`（含传递依赖与平台链接选项）。
find_package(unofficial-node CONFIG REQUIRED)

# ★ Windows：消费方**任何**构建类型（Debug 也不例外）都用 release 静态 CRT（/MT）。
#   本工程依赖的 vcpkg 库（node 及其全部依赖）被 triplet 钉死 release-only
#   （VCPKG_BUILD_TYPE=release，见 cmake/triplets/*.cmake —— 那是 a92c781 的决策：
#   一批上游 port 的 debug-only 构建是坏的）。而 CMake/vcpkg 的默认值带 CONFIG
#   genex（MultiThreaded$<$<CONFIG:Debug>:Debug>…），Debug 配置下会把消费方切成
#   /MTd，于是链接期直接红：
#     lld-link: error: /failifmismatch: mismatch detected for '_ITERATOR_DEBUG_LEVEL':
#     >>> libcpmtd.lib(xthrow.obj) has value 2
#     >>> node_base.lib(...) has value 0
#   （2026-10-14 ci debug 首跑 x64-windows 实测；就算绕过这关，一个进程里两份 CRT
#    也是 heap / locale 各自一套的灾难。）这里用普通变量覆盖工具链的 cache 默认值：
#   target 都在后面的 add_subdirectory 里创建，届时读到的就是覆盖后的值。
if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")
endif()

# 跑官方套件与符号审计都要 python（node 自带的 driver 就是 python）。
find_package(Python3 COMPONENTS Interpreter)

enable_testing()

# ---- 消费方示例（每个都自带测试）-------------------------------------------
add_subdirectory(example_embed)
add_subdirectory(example_coexist)
add_subdirectory(example_host_exit)
add_subdirectory(example_thread_loop)
add_subdirectory(example_spawn_child)
add_subdirectory(example_worker_threads)
add_subdirectory(example_multitarget)

# ---- 本仓库的内部测试（每组一个 ctest 目标/目标组）---------------------------
add_subdirectory(test_vcpkg_baseline)
add_subdirectory(test_node_coexist)
add_subdirectory(test_official_suite)
add_subdirectory(test_symbols)
add_subdirectory(test_tools)

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
