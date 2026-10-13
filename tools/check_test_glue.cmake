# Gate: make sure test/tests/*.cmake (the configure-time glue of the test project)
# can actually be *loaded to the end*, and that it really registers test cases.
#
# Why a separate gate (it cost a whole CI round on 2026-10-13):
#   The glue files start with a chain of `if(NOT <var>) ... return()` early exits.
#   Our existing syntax gate is `cmake -P <file>`, and in script mode it *always*
#   stops at the first early exit -- so any syntax or flow-control error *after*
#   those early returns is invisible to it.  That day a duplicated `if()` line made
#   CMake report "Flow control statements are not properly nested" only when the
#   Windows configure ran, and all six CI jobs of that run were wasted.
#
# What this does: build a minimal fixture that satisfies every early-exit
# condition, shadow `add_test` / `set_tests_properties` with same-named macros
# (they are not scriptable), include the glue for real, then assert that it
# registered at least one test -- otherwise some early return swallowed it and
# this gate must fail too.
#
# Usage: cmake -P tools/check_test_glue.cmake     (from the repository root)

cmake_minimum_required(VERSION 3.21)

set(_repo_root "${CMAKE_CURRENT_LIST_DIR}/..")
get_filename_component(_repo_root "${_repo_root}" ABSOLUTE)

# 一切临时产物都放进一个一次性 fixture 目录，不污染仓库。
if(DEFINED ENV{RUNNER_TEMP} AND NOT "$ENV{RUNNER_TEMP}" STREQUAL "")
  set(_work "$ENV{RUNNER_TEMP}/test-glue-gate")
else()
  set(_work "${_repo_root}/.tmp/test-glue-gate")
endif()
file(REMOVE_RECURSE "${_work}")
file(MAKE_DIRECTORY "${_work}")

# --- fixture：满足胶水的每一处早退条件 -------------------------------------
file(MAKE_DIRECTORY "${_work}/suite/tools")
file(MAKE_DIRECTORY "${_work}/suite/test/fixtures/run-script/node_modules/.bin")
file(WRITE "${_work}/suite/tools/test.py" "# fixture for the gate\n")
# 执行位那条红线（UNIX）会 GLOB 这个目录并要求可执行，所以造一个可执行文件。
file(WRITE "${_work}/suite/test/fixtures/run-script/node_modules/.bin/positional-args" "#!/bin/sh\ntrue\n")
file(CHMOD "${_work}/suite/test/fixtures/run-script/node_modules/.bin/positional-args"
     PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
file(MAKE_DIRECTORY "${_work}/tmp")

# 胶水需要的输入变量（都是它自己声明/上游导出的名字）。
set(NODE_PORT_TEST_NODE_SUITE ON)
set(node_TEST_SUITE_DIR "${_work}/suite")
set(Python3_Interpreter_FOUND TRUE)
set(Python3_EXECUTABLE "python3")   # 只进 add_test 的参数列表（已被顶掉），值不重要
set(NODE_PORT_TEST_FLAKY_MODE "dontcare")
set(NODE_PORT_TEST_JOBS "")
set(NODE_PORT_TEST_SUITES "parallel")
set(NODE_PORT_TEST_SHARDS "")
set(NODE_PORT_TEST_SKIP "")
set(NODE_PORT_TEST_SUITE_TIMEOUT 3600)
set(NODE_PORT_TEST_NODE_ARGS "")
set(NODE_PORT_TEST_TMPBASE "${_work}/tmp")

# --- 顶掉两个"脚本模式不可用"的命令，并数一数注册了几个用例 ---------------
# 计数用文件而不是变量：胶水是在 `function(_node_suite_register ...)` 里调 add_test 的，
# 而宏里的 math()/set() 只会改到**那个函数的作用域**，全局变量永远是 0（第一版就栽在这）。
set(_glue_count_file "${_work}/registered.txt")
file(WRITE "${_glue_count_file}" "")
macro(add_test)
  file(APPEND "${_glue_count_file}" "x")
endmacro()
macro(set_tests_properties)
endmacro()

include("${_repo_root}/test/tests/ctest_node_suite.cmake")

file(SIZE "${_glue_count_file}" _glue_registered)

unset(NODE_PORT_TEST_NODE_SUITE)
unset(node_TEST_SUITE_DIR)
unset(Python3_Interpreter_FOUND)
unset(Python3_EXECUTABLE)
unset(NODE_PORT_TEST_FLAKY_MODE)
unset(NODE_PORT_TEST_JOBS)
unset(NODE_PORT_TEST_SUITES)
unset(NODE_PORT_TEST_SHARDS)
unset(NODE_PORT_TEST_SKIP)
unset(NODE_PORT_TEST_SUITE_TIMEOUT)
unset(NODE_PORT_TEST_NODE_ARGS)
unset(NODE_PORT_TEST_TMPBASE)

if(_glue_registered LESS 1)
  message(FATAL_ERROR
    "test/tests/ctest_node_suite.cmake 被加载了，但**一个用例都没注册** ——\n"
    "说明它在某处 early return 掉了（fixture 已经满足全部早退条件，所以这是胶水自己的问题）。\n"
    "这个闸门存在的意义就是不让早退把语法/流控错误藏起来（2026-10-13 为此废掉一整轮 CI）。")
endif()

message(STATUS "test glue 可完整加载：注册了 ${_glue_registered} 个用例")
file(REMOVE_RECURSE "${_work}")
