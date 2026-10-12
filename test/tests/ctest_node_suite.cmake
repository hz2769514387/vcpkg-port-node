# 把 node 官方测试套件注册成 ctest 用例。
#
# 为什么用官方 tools/test.py，而不是 `node --test`：
#   各套件目录下的 *.status 记录着上游自己标记的 SKIP / FLAKY 用例，**只有 test.py 会读**。
#   直接 `node --test` 会把这些状态全丢掉 —— 于是满屏"失败"，其中绝大多数是上游本来
#   就跳过或不稳定的环境相关用例。那种红没有信息量，会把真问题淹掉。
#
# test.py 的 `--shell=<可执行>` 就是"用别人的 node 跑官方用例"的官方入口，
# 我们的 node_embed 正是为它准备的（同一份 argv 语义 + Windows 上 wmain/UTF-8）：
#   它按 dirname(sys.argv[0])/.. 推 workspace，所以 tools/ 与 test/ 必须同层。
#
# ★ 默认口径 = 上游的 `make jstest`：**一个 test.py 进程**，把要跑的套件全列上，
#   并行度交给 test.py 自己的 `-j`（Makefile:322 `tools/test.py … $(PARALLEL_ARGS) $(JS_SUITES)`）。
#   为什么不能拆成多个并发进程（run #21 的教训）：
#     * test/common/tmpdir.js 用 `.tmp.${TEST_SERIAL_ID||TEST_THREAD_ID}` 命名临时目录，
#       而这两个 id 都是**每个 test.py 进程内部**从 0 起算的 ⇒ 两个并发 test.py 会撞同一个
#       `.tmp.1`，于是 snapshot-warning / report-* 这类用例互相把对方的临时目录删掉
#       （EPERM / unlink ENOENT，run #21 里 3 个失败）。
#     * sequential/ 下的用例是"独占机器"写的（固定端口等），4 片并发跑就是
#       `bind EADDRINUSE :::12346`（run #21 的 sequential-shard3）。
#   想分片也可以（NODE_PORT_TEST_SHARDS>0，仍按 suite×分片注册成多进程），但那时
#   每个进程必须有自己的 --temp-dir，下面已经按用例名生成，避免再踩同一个坑。

if(NOT NODE_PORT_TEST_NODE_SUITE)
  message(STATUS "node 官方套件：已关闭（-DNODE_PORT_TEST_NODE_SUITE=OFF）")
  return()
endif()

if(NOT node_TEST_SUITE_DIR)
  message(WARNING
    "找不到 node 官方套件目录。请给 node 依赖打开 test-suite feature"
    "（见 test/vcpkg.json 里 node 的 features），本次不注册官方套件用例。")
  return()
endif()

if(NOT Python3_Interpreter_FOUND)
  message(WARNING
    "找不到 python3。node 官方套件要靠 tools/test.py 驱动，本次不注册官方套件用例。")
  return()
endif()

set(_node_suite_runner "${node_TEST_SUITE_DIR}/tools/test.py")
set(_node_suite_testroot "${node_TEST_SUITE_DIR}/test")
if(NOT EXISTS "${_node_suite_runner}" OR NOT IS_DIRECTORY "${_node_suite_testroot}")
  message(WARNING "套件目录不完整，跳过：${node_TEST_SUITE_DIR}")
  return()
endif()

# test.py 的通用参数
set(_node_suite_args
    "${_node_suite_runner}"
    "--shell=$<TARGET_FILE:node_embed>"
    "--test-root=${_node_suite_testroot}"
    "--time"
    # 被上游标成 flaky 的用例：跑，但失败不计入结果。我们不是上游 CI，
    # 用默认的 run 会让已知不稳定用例反复把红点亮，把真问题淹掉。
    "--flaky-tests=${NODE_PORT_TEST_FLAKY_MODE}")
if(NODE_PORT_TEST_JOBS)
  list(APPEND _node_suite_args "-j" "${NODE_PORT_TEST_JOBS}")
endif()
if(NODE_PORT_TEST_SKIP)
  list(APPEND _node_suite_args "--skip-tests=${NODE_PORT_TEST_SKIP}")
endif()

string(REPLACE "," ";" _node_suite_list "${NODE_PORT_TEST_SUITES}")
if(NOT _node_suite_list)
  # 空 = 用 test.py 的默认集合（它会自己排除 addons/internet/node-api 等非 JS 套件）
  set(_node_suite_list "default")
endif()

# 每个用例一个独立的临时根目录（NODE_TEST_DIR / test/common/tmpdir.js 都认它）。
# 只有一个 test.py 进程时其实撞不上，但这是给"分片/多进程"留的安全带，成本一个目录。
set(_node_suite_tmproot "${CMAKE_CURRENT_BINARY_DIR}/node-suite-tmp")
file(MAKE_DIRECTORY "${_node_suite_tmproot}")
# _node_suite_register(<用例名> <label 后缀> <test.py 的位置参数…>)
function(_node_suite_register _name _label)
  add_test(NAME "${_name}"
           COMMAND ${Python3_EXECUTABLE} ${_node_suite_args}
                   "--temp-dir=${_node_suite_tmproot}/${_name}"
                   ${ARGN})
  set_tests_properties("${_name}" PROPERTIES
    LABELS "node-suite;node-suite-${_label}"
    TIMEOUT ${NODE_PORT_TEST_SUITE_TIMEOUT}
    WORKING_DIRECTORY "${node_TEST_SUITE_DIR}"
    # node 官方套件的 test/common/index.js 会检查"有没有冒出它不认识的全局"
    # （Unexpected global(s) found）。宿主环境里任何 NODE_OPTIONS=--require 的
    # 预载（本机就是 WorkBuddy 注入的 node-language-shim.cjs）都会往每个 node
    # 进程里塞 __CODEBUDDY_NODE_* 全局，一跑就红 257 个 —— 全是环境问题，
    # 不是库的问题（实测：直接跑同一个用例，清掉 NODE_OPTIONS 就过）。
    # 所以这里把 NODE_OPTIONS 清空，套件进程不继承宿主的任何预载。
    ENVIRONMENT "NODE_OPTIONS=")
endfunction()

set(_node_suite_count 0)
if(NODE_PORT_TEST_SHARDS)
  foreach(_suite IN LISTS _node_suite_list)
    math(EXPR _shard_last "${NODE_PORT_TEST_SHARDS} - 1")
    foreach(_shard RANGE 0 ${_shard_last})
      set(_node_suite_name "node-suite-${_suite}-shard${_shard}")
      _node_suite_register("${_node_suite_name}" "${_suite}"
                           "--run=${_shard},${NODE_PORT_TEST_SHARDS}" "${_suite}")
      # sequential/ 是"独占机器"写的（固定端口）：分片并发会在同一台机上互相抢端口，
      # 所以这一组让 ctest 一次只跑一个（RUN_SERIAL：不与其他任何用例并发）。
      if(_suite STREQUAL "sequential")
        set_tests_properties("${_node_suite_name}" PROPERTIES RUN_SERIAL TRUE)
      endif()
      math(EXPR _node_suite_count "${_node_suite_count} + 1")
    endforeach()
  endforeach()
else()
  # 上游 make jstest 的口径：一个进程，套件按位置参数一次全给。
  _node_suite_register("node-suite" "all" ${_node_suite_list})
  # 这个用例内部已经 -j 起满并行，再和别的用例抢机器只会引入端口/临时目录噪音。
  set_tests_properties("node-suite" PROPERTIES RUN_SERIAL TRUE)
  set(_node_suite_count 1)
endif()

message(STATUS "node 官方套件：注册了 ${_node_suite_count} 个 ctest 用例"
               "（套件：${NODE_PORT_TEST_SUITES}；分片：'${NODE_PORT_TEST_SHARDS}'）")
message(STATUS "  driver : ${_node_suite_runner}")
message(STATUS "  shell  : $<TARGET_FILE:node_embed>")
message(STATUS "  临时根 : ${_node_suite_tmproot}")
