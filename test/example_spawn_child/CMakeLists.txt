# 消费方示例 · 场景五：**不链接** node，把 node 当子进程用
#
# 对应一大类真实消费方："我不想链上百兆的静态库，我只想在需要的时候跑一段
# JS / 用一下 npm/npx"。port 的 `tools` feature 装出 node 可执行
# （`node_EXECUTABLE`），本示例演示宿主这一侧的完整姿势：
#   * node 路径从命令行传入（真实项目里可来自配置/环境变量）；
#   * spawn 并**捕获输出**（不是甩给继承的 stdout，否则没法对输出做判断）；
#   * 子进程退出码如实打印（`CHILD-EXIT: <码>`）；宿主自己的退出码有两种口径：
#     默认镜像子进程，`--expect-exit=N` 则核对后自行判定（见 spawn_host.cpp 顶部）；
#   * "起不来"与"跑完但失败"两种失败分开报。
#
# 与 example_embed 的分工：那边是"链进我的程序"，这边是"当外部工具用"——
# 两条都是正当路线，按你的程序形态选。本示例**不链接 node**，也不需要
# 任何其它 example_/test_ 目录 ⇒ 单独删掉不影响任何东西。

add_executable(spawn_host spawn_host.cpp)
target_compile_features(spawn_host PRIVATE cxx_std_20)
if(MSVC)
  target_compile_options(spawn_host PRIVATE /utf-8)  # 本文件注释是中文
endif()

# node 可执行来自 port 的 tools feature；没开这个 feature 就跳过本示例
# （示例要能在任何 feature 组合下配置成功，这才是给消费方的样子）。
if(NOT DEFINED node_EXECUTABLE OR NOT EXISTS "${node_EXECUTABLE}")
  message(WARNING
    "没有 node_EXECUTABLE（node port 的 tools feature 没开）⇒ 跳过 example_spawn_child。")
  return()
endif()

# ---- 示例自带的测试 ----------------------------------------------------------
# 1) 跑一段真干活的脚本：zlib 往返（顺带证明子进程里的 zlib 也是 vcpkg 那份）。
add_test(NAME example-spawn-child-script
         COMMAND spawn_host "${node_EXECUTABLE}"
                 "${CMAKE_CURRENT_SOURCE_DIR}/child_script.js")
set_tests_properties(example-spawn-child-script PROPERTIES
  LABELS "example;example_spawn_child"
  TIMEOUT 300
  PASS_REGULAR_EXPRESSION "SPAWN-CHILD-OK")

# 2) 参数透传：-e 这种 node 自己的参数原样到达子进程。
#    （也演示了"参数怎么转发"——宿主不做任何解释，一字不改传给 node。）
add_test(NAME example-spawn-child-version
         COMMAND spawn_host "${node_EXECUTABLE}"
                 -e "process.stdout.write(process.versions.node)")
set_tests_properties(example-spawn-child-version PROPERTIES
  LABELS "example;example_spawn_child"
  TIMEOUT 300
  PASS_REGULAR_EXPRESSION "24\\.21\\.0")

# 3) 退出码链：子进程 process.exit(3) ⇒ 宿主必须如实打印 `CHILD-EXIT: 3`。
#    这里用 `--expect-exit=3`（断言口径）：宿主核对"子进程确实以 3 退出"，
#    核对成功自己才 exit 0 —— 于是 ctest 不需要 WILL_FAIL 也能钉住这个 3。
#    （WILL_FAIL + PASS_REGULAR_EXPRESSION 在 ctest 里会把判定反转：
#     实测匹配即失败，所以断言型场景一律用"宿主自己 exit 0 + 正则断言"。）
#    两种口径的区别见 spawn_host.cpp 顶部注释。
add_test(NAME example-spawn-child-exit-code
         COMMAND spawn_host --expect-exit=3
                 "${node_EXECUTABLE}"
                 -e "process.exit(3)")
set_tests_properties(example-spawn-child-exit-code PROPERTIES
  LABELS "example;example_spawn_child"
  TIMEOUT 300
  PASS_REGULAR_EXPRESSION "CHILD-EXIT: 3")
