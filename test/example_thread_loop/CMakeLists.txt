# 消费方示例 · 场景四：消息循环**耦合还是分离**
#
# 消费方把 node 嵌进自己程序时的第一个问题："node 会不会霸占我的主线程？
# 我自己的消息循环还跑不跑？"本示例给的是**分离**形态的完整答案：
#   * node::Start 在 worker 线程里跑（main.cpp 里那一小段）；
#   * 主线程继续跑宿主自己的循环（自己的 tick 节奏、自己的活）；
#   * 双方经共享目录里的消息文件双向通信（先写临时名再 rename，原子可见）；
#   * 退出码从 node::Start 的返回值原样透传。
#
# 形态对比（不耦合，只是给你选型参考）：
#   * 想要"我的程序就是个 node 运行时" → 看 example_embed（主线程直调
#     node::Start，你的循环就是 node 的循环，最简单）；
#   * 想要"我的程序是主、node 是工" → 就是本示例。
#
# 它自带一条测试（见文件末尾）。这条示例**不依赖任何其它 example_/test_ 目录**：
# 自己编嵌入器、自己带 JS、断言全在自己进程里完成 —— 单独删掉本目录，
# 其它示例与内部测试照跑。
add_executable(thread_loop main.cpp)
target_link_libraries(thread_loop PRIVATE unofficial::node::node)
# C++20 由 unofficial::node::node 的 INTERFACE 声明（port 侧 cxx_std_20），这里不写。

# Windows：与 example_embed 同样的两条必要处置 ——
#   1) 嵌 node 的平台兼容性清单，否则进程一启动就退出码 216（实测）；
#   2) MSVC 前端显式声明源码是 UTF-8（本文件注释是中文）。
# /INCREMENTAL:NO 的原因见 example_embed/CMakeLists.txt：Debug 下 vs_link_exe 的
# 增量路径会往链接命令尾部追加裸 /MANIFEST，顶掉 /MANIFESTINPUT 的嵌入模式。
# Windows 的清单/栈/compiler-rt 由 unofficial::node::node 的 INTERFACE 自动带上
# （2026-10-14 重构后不再需要手抄 /MANIFEST 片段，见 example_embed 里的说明）。
if(MSVC)
  target_compile_options(thread_loop PRIVATE /utf-8)
endif()

# ---- 示例自带的测试 ----------------------------------------------------------
# 一条用例同时验四件事（断言写在 main.cpp 里，这里只负责把产物指过去）：
#   1) node 运行期间宿主循环持续 tick（HOST-TICK 与 JS-GOT 在日志里交错）；
#   2) 双向数据都到达（5 条消息 5 条回复，条数不对就红）；
#   3) 退出码 0 原样透传；
#   4) 挂死保护（宿主等 node 有 120s 硬上限）。
# 邮箱目录放在构建目录下：ctest 可重复运行，宿主启动时会先清空。
add_test(NAME example-thread-loop-separated
         COMMAND thread_loop
                 "${CMAKE_CURRENT_SOURCE_DIR}/loop_worker.js"
                 "${CMAKE_CURRENT_BINARY_DIR}/mailbox")
set_tests_properties(example-thread-loop-separated PROPERTIES
  LABELS "example;example_thread_loop"
  TIMEOUT 300
  PASS_REGULAR_EXPRESSION "THREAD-LOOP-OK")
