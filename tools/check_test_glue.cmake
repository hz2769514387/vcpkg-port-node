# Gate: make sure test/test_official_suite/*.cmake (the configure-time glue of the test project)
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
#
# ★ 2026-10-14 扩展：跑**两遍**（release 口径 + debug 口径）。
#   起因：debug 跳过清单（cmake/node-suite-skips-debug.txt）的加载被包在
#   `if(CMAKE_BUILD_TYPE MATCHES debug)` 里，属于**这个闸门原本覆盖不到的分支** ——
#   而闸门存在的全部意义就是"早退之后的代码也要被真加载一次"。
#   只跑 release 的话，那段代码里的语法/流控错误仍然会等到真实 CI 的 Windows
#   配置期才炸（那正是 2026-10-13 废掉一整轮 CI 的同一种失败）。
#   所以这里把 fixture 参数化，用 include() 把胶水加载两遍。

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

# 真实工程里胶水用 CMAKE_SOURCE_DIR 定位 test/cmake/ 下的两个跳过清单。
# 脚本模式下 CMAKE_SOURCE_DIR 是**调用 cmake -P 的那个目录**（仓库根），
# 而清单在 test/cmake/ ⇒ 这里显式指过去，与真实配置期一致。
set(CMAKE_SOURCE_DIR "${_repo_root}/test")

# --- 真正加载胶水的一遍 -----------------------------------------------------
# 参数：口径名 + CMAKE_BUILD_TYPE。返回 0。
function(_gate_load_glue _label _build_type)
  # 胶水需要的输入变量（都是它自己声明/上游导出的名字）。
  set(NODE_PORT_TEST_NODE_SUITE ON)
  set(node_TEST_SUITE_DIR "${_work}/suite")
  set(Python3_Interpreter_FOUND TRUE)
  set(Python3_EXECUTABLE "python3")   # 只进 add_test 的参数列表（已被顶掉），值不重要
  # 官方套件要给 test.py 一个 shell：这里指向 fixture 里**确实存在**的那个文件
  # （真实构建里是示例编出来的 node_embed，或端口装出来的 node_EXECUTABLE）。
  set(node_EXECUTABLE "${_work}/suite/tools/test.py")
  set(NODE_PORT_TEST_FLAKY_MODE "dontcare")
  set(NODE_PORT_TEST_JOBS "")
  set(NODE_PORT_TEST_SUITES "parallel")
  set(NODE_PORT_TEST_SHARDS "")
  set(NODE_PORT_TEST_SKIP "")
  set(NODE_PORT_TEST_SUITE_TIMEOUT 3600)
  set(NODE_PORT_TEST_NODE_ARGS "")
  set(NODE_PORT_TEST_TMPBASE "${_work}/tmp")
  set(CMAKE_BUILD_TYPE "${_build_type}")
  # 真实 CI 六个腿都给 VCPKG_TARGET_TRIPLET（见 test/CMakePresets.json），跳过清单的
  # 架构维度（`<平台>-<架构>`）正是靠它的首段判架构。fixture 也给一个，让闸门
  # 跟真实配置期走同一条 arch 解析分支，而不是 `_node_suite_arch` 恒空那条捷径。
  set(VCPKG_TARGET_TRIPLET "x64-linux")
  # 脚本模式下 CMAKE_SYSTEM_NAME 是空的（没有 project()），而胶水靠它定平台。
  # 给一个与上面 triplet 一致的值，让闸门真的走 os+arch 那条匹配分支，
  # 而不是 `_node_suite_os` 恒空、所有非 all 条目一律不命中那条捷径。
  set(CMAKE_SYSTEM_NAME "Linux")

  # 顶掉两个"脚本模式不可用"的命令，并数一数注册了几个用例。
  # 计数用文件而不是变量：胶水是在 `function(_node_suite_register ...)` 里调 add_test 的，
  # 而宏里的 math()/set() 只会改到**那个函数的作用域**，全局变量永远是 0（第一版就栽在这）。
  # 计数文件带口径名，两遍互不覆盖 —— 顺带验证 debug 那一遍真的注册了用例。
  set(_glue_count_file "${_work}/registered-${_label}.txt")
  file(WRITE "${_glue_count_file}" "")
  macro(add_test)
    file(APPEND "${_glue_count_file}" "x")
  endmacro()
  macro(set_tests_properties)
  endmacro()

  include("${_repo_root}/test/test_official_suite/ctest_node_suite.cmake")

  file(SIZE "${_glue_count_file}" _glue_registered)
  if(_glue_registered LESS 1)
    message(FATAL_ERROR
      "test/test_official_suite/ctest_node_suite.cmake 以 ${_label} 口径被加载了，"
      "但**一个用例都没注册** ——\n"
      "说明它在某处 early return 掉了（fixture 已经满足全部早退条件，所以这是胶水自己的问题）。\n"
      "这个闸门存在的意义就是不让早退把语法/流控错误藏起来（2026-10-13 为此废掉一整轮 CI）。")
  endif()
  message(STATUS "test glue 可完整加载（${_label} 口径）：注册了 ${_glue_registered} 个用例")
endfunction()

# ★ 两遍都要跑：debug 口径会额外加载 cmake/node-suite-skips-debug.txt 那段
#   （release 口径不走它 —— 那正是它该有的行为：debug-only 的失败不能让 release 腿跳过用例）。
_gate_load_glue("release" "Release")
_gate_load_glue("debug" "Debug")

# 额外断言：debug 清单**确实被读到了**（否则上面那遍只是走了个形式）。
# 不这样断言的话，把 if 条件写错（比如 STREQUAL 写成 MATCHES 之外的东西）
# 会让 debug 段静默不执行，而这正是 2026-10-14 run #40 的翻版：
#   代码"改了"、闸门也绿、实际一行没生效。
get_filename_component(_debug_skips "${CMAKE_SOURCE_DIR}/cmake/node-suite-skips-debug.txt" ABSOLUTE)
if(NOT EXISTS "${_debug_skips}")
  message(FATAL_ERROR
    "找不到 debug 口径跳过清单 ${_debug_skips}：\n"
    "胶水的 debug 分支会因此只发一条 WARNING 就跳过整段，闸门却仍然绿。\n"
    "这个文件是 debug 腿不误报的唯一依据，必须存在。")
endif()
message(STATUS "debug 口径跳过清单就位：${_debug_skips}")

file(REMOVE_RECURSE "${_work}")
