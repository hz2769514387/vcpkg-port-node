# 消费方示例 · 场景六：嵌入运行时里，node 的并发模型还完整吗
#
# 消费方最常见的一问："我把 node 嵌进我的程序了，worker_threads 还能用吗？"
# 本示例给可运行的答案：能，而且 worker 里 vcpkg 提供的库同样是好的。
#
# 与相关示例的分工（都不耦合，删掉任何一个其它照跑）：
#   * example_embed        —— 嵌入的基本形态（主线程直调 node::Start）；
#   * example_thread_loop  —— **宿主**多线程：node 在宿主的 worker 线程里跑，
#                            主线程跑宿主自己的循环（C++ 侧的线程分离）；
#   * 本示例               —— **node 自己**的并发模型：worker_threads 在
#                            嵌入运行时里真跑（JS 侧的多线程）。
#   一个是"node 与宿主的线程关系"，一个是"node 内部的并发能力"，两回事。
#
# 本示例自带一个最小嵌入器（main.cpp，与 example_embed 同一副样子，
# 故意的：消费方拷走这一个目录就能跑）和一条测试。

add_executable(worker_threads main.cpp)
set_target_properties(worker_threads PROPERTIES OUTPUT_NAME worker_threads)
target_link_libraries(worker_threads PRIVATE unofficial::node::node)
target_compile_features(worker_threads PRIVATE cxx_std_20)

# Windows：与 example_embed 同样的两条必要处置 ——
#   1) 嵌 node 的平台兼容性清单，否则进程一启动就退出码 216（实测）；
#   2) MSVC 前端显式声明源码是 UTF-8（本文件注释是中文）。
# /INCREMENTAL:NO 的原因见 example_embed/CMakeLists.txt：Debug 下 vs_link_exe 的
# 增量路径会往链接命令尾部追加裸 /MANIFEST，顶掉 /MANIFESTINPUT 的嵌入模式。
if(WIN32 AND DEFINED node_NODE_SOURCE_MANIFEST AND EXISTS "${node_NODE_SOURCE_MANIFEST}")
  target_link_options(worker_threads PRIVATE
    "/MANIFEST:EMBED"
    "/MANIFESTINPUT:${node_NODE_SOURCE_MANIFEST}"
    "/INCREMENTAL:NO")
endif()
if(MSVC)
  target_compile_options(worker_threads PRIVATE /utf-8)
endif()

# ---- 示例自带的测试 ----------------------------------------------------------
# 3 个 worker 各自用 vcpkg 提供的 zlib 做一次压/解往返，主线程收齐后打印
# `WORKERS-OK w0:zlib-ok w1:zlib-ok w2:zlib-ok`；任何一条不对脚本自己就
# 以非零退出，嵌入运行时原样透传。
add_test(NAME example-worker-threads
         COMMAND worker_threads "${CMAKE_CURRENT_SOURCE_DIR}/workers.js")
set_tests_properties(example-worker-threads PROPERTIES
  LABELS "example;example_worker_threads"
  TIMEOUT 300
  PASS_REGULAR_EXPRESSION "WORKERS-OK")
