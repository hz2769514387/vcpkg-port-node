# 把 node 官方测试套件注册成 ctest 用例。
#
# 为什么用官方 tools/test.py，而不是 `node --test`：
#   各套件目录下的 *.status 记录着上游自己标记的 SKIP / FLAKY 用例，**只有 test.py 会读**。
#   直接 `node --test` 会把这些状态全丢掉 —— 于是满屏"失败"，其中绝大多数是上游本来
#   就跳过或不稳定的环境相关用例。那种红没有信息量，会把真问题淹掉。
#
# test.py 的 `--shell=<可执行>` 就是"用别人的 node 跑官方用例"的官方入口，
# 我们的 node_embed 正是为它准备的（同一份 argv 语义 + Windows 上 wmain/UTF-8）。
#
# 分片：test.py 原生支持 `--run=<第几片>,<总片数>`，所以直接把它映射成多个 ctest 用例，
# 让 ctest 的 -j 去并行，而不是在一个进程里靠 test.py 自己调度。

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

set(_node_suite_count 0)
foreach(_suite IN LISTS _node_suite_list)
  if(NODE_PORT_TEST_SHARDS)
    math(EXPR _shard_last "${NODE_PORT_TEST_SHARDS} - 1")
    foreach(_shard RANGE 0 ${_shard_last})
      add_test(NAME "node-suite-${_suite}-shard${_shard}"
               COMMAND ${Python3_EXECUTABLE} ${_node_suite_args}
                       "--run=${_shard},${NODE_PORT_TEST_SHARDS}" "${_suite}")
      set_tests_properties("node-suite-${_suite}-shard${_shard}" PROPERTIES
        LABELS "node-suite;node-suite-${_suite}"
        TIMEOUT ${NODE_PORT_TEST_SUITE_TIMEOUT}
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        # node 官方套件的 test/common/index.js 会检查"有没有冒出它不认识的全局"
        # （Unexpected global(s) found）。宿主环境里任何 NODE_OPTIONS=--require 的
        # 预载（本机就是 WorkBuddy 注入的 node-language-shim.cjs）都会往每个 node
        # 进程里塞 __CODEBUDDY_NODE_* 全局，一跑就红 257 个 —— 全是环境问题，
        # 不是库的问题（实测：直接跑同一个用例，清掉 NODE_OPTIONS 就过）。
        # 所以这里把 NODE_OPTIONS 清空，套件进程不继承宿主的任何预载。
        ENVIRONMENT "NODE_OPTIONS=")
      math(EXPR _node_suite_count "${_node_suite_count} + 1")
    endforeach()
  else()
    add_test(NAME "node-suite-${_suite}"
             COMMAND ${Python3_EXECUTABLE} ${_node_suite_args} "${_suite}")
    set_tests_properties("node-suite-${_suite}" PROPERTIES
      LABELS "node-suite;node-suite-${_suite}"
      TIMEOUT ${NODE_PORT_TEST_SUITE_TIMEOUT}
      WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
      ENVIRONMENT "NODE_OPTIONS=")
    math(EXPR _node_suite_count "${_node_suite_count} + 1")
  endif()
endforeach()

message(STATUS "node 官方套件：注册了 ${_node_suite_count} 个 ctest 用例"
               "（套件：${NODE_PORT_TEST_SUITES}；分片：'${NODE_PORT_TEST_SHARDS}'）")
message(STATUS "  driver : ${_node_suite_runner}")
message(STATUS "  shell  : $<TARGET_FILE:node_embed>")
