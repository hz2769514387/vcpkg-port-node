# 消费方示例 · 场景③：宿主进程怎么"收场"——node 的退出码语义
#
# 消费方最担心的第二件事（第一件是"会不会跟我已有的库打架"）：
#   **我把 node 嵌进自己的程序之后，它崩了/抛异常了，我的进程能不能拿到一个说得清的退出码？**
#   这直接决定"我的程序该不该继续、要不要重启某个子任务、CI 里能不能只靠退出码判定成败"。
#
# 本示例演示三种最常见的收场方式，并且**逐条断言退出码**：
#   exit 0        —— 正常跑完
#   exit 1(非 0)  —— 未捕获异常
#   exit N        —— 脚本里显式 process.exit(N)，原样传出来
#
# 断言精确值（不是"非 0 就行"）由同目录 check_exit.cmake 完成：
# ctest 自己只能表达"期望失败"（WILL_FAIL），说不出"应当是 7"，所以这里用一个
# 十行的小脚本把"实际退出码 == 期望值"变成 ctest 能懂的结果。
#
# 用的是端口 `tools` feature 装出来的 node（node_EXECUTABLE），不链库、也不依赖
# 其它示例目录 ⇒ 单独删掉本目录不影响任何东西。
if(NOT DEFINED node_EXECUTABLE OR NOT EXISTS "${node_EXECUTABLE}")
  message(WARNING
    "没有 node_EXECUTABLE（node port 的 tools feature 没开）⇒ 跳过 example_host_exit。")
  return()
endif()

# 正常结束：退出码必须是 0。
add_test(NAME example-host-exit-ok
         COMMAND ${CMAKE_COMMAND}
                 -DNODE=${node_EXECUTABLE}
                 -DSCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/exit_ok.js
                 -DEXPECT=0
                 -P ${CMAKE_CURRENT_SOURCE_DIR}/check_exit.cmake)
set_tests_properties(example-host-exit-ok PROPERTIES LABELS "example;example_host_exit" TIMEOUT 300)

# 未捕获异常：node 的约定是退出码 1。
add_test(NAME example-host-exit-uncaught
         COMMAND ${CMAKE_COMMAND}
                 -DNODE=${node_EXECUTABLE}
                 -DSCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/exit_uncaught.js
                 -DEXPECT=1
                 -P ${CMAKE_CURRENT_SOURCE_DIR}/check_exit.cmake)
set_tests_properties(example-host-exit-uncaught PROPERTIES
  LABELS "example;example_host_exit" TIMEOUT 300)

# process.exit(7)：宿主应当原样拿到 7（不要把 node 的退出码吞掉或改写成 1）。
add_test(NAME example-host-exit-code7
         COMMAND ${CMAKE_COMMAND}
                 -DNODE=${node_EXECUTABLE}
                 -DSCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/exit_code7.js
                 -DEXPECT=7
                 -P ${CMAKE_CURRENT_SOURCE_DIR}/check_exit.cmake)
set_tests_properties(example-host-exit-code7 PROPERTIES
  LABELS "example;example_host_exit" TIMEOUT 300)
