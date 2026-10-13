# 把"node 的退出码 == 期望值"变成 ctest 能判定的结果。
#
# 为什么需要它：ctest 只能表达"期望失败"（WILL_FAIL），说不出"退出码应当
# 正好是 7"。这个十行小脚本补上这一课：跑一次 node，比对退出码，不相等就
# FATAL_ERROR（-P 脚本里 FATAL_ERROR 会让 cmake 以非零退出 ⇒ ctest 判红）。
#
# 用法（由同目录 CMakeLists.txt 的 add_test 调用）：
#   cmake -DNODE=<node 可执行> -DSCRIPT=<js 文件> -DEXPECT=<期望退出码> -P check_exit.cmake
#
# 顺带把脚本自己的输出回显出来 —— 未捕获异常那条会打一整页栈，
# 判读时不用再手工跑一遍。

if(NOT DEFINED NODE OR NOT DEFINED SCRIPT OR NOT DEFINED EXPECT)
  message(FATAL_ERROR "check_exit.cmake 需要 -DNODE / -DSCRIPT / -DEXPECT 三个变量")
endif()

execute_process(
  COMMAND "${NODE}" "${SCRIPT}"
  RESULT_VARIABLE _actual
  OUTPUT_VARIABLE _stdout
  ERROR_VARIABLE _stderr
)

message(STATUS "脚本: ${SCRIPT}")
message(STATUS "stdout: ${_stdout}")
if(_stderr)
  message(STATUS "stderr: ${_stderr}")
endif()
message(STATUS "退出码: 期望 ${EXPECT} / 实际 ${_actual}")

if(NOT _actual EQUAL ${EXPECT})
  message(FATAL_ERROR
    "node 退出码不对：期望 ${EXPECT}，实际 ${_actual}。\n"
    "宿主必须原样透传 node 的退出码 —— 吞掉或改写它，调用方就无法靠退出码判定成败。")
endif()

message(STATUS "退出码符合预期（${_actual}）")
