# 本仓库的内部测试 · node 官方测试套件
#
# 这里是一个**ctest 目标组**：把 node 官方套件（tools/test.py --shell=<某个 node>）
# 注册成 ctest 用例。真正的注册逻辑在 ctest_node_suite.cmake（本目录），
# 这个文件存在的目的就是让人一眼看到"这是一个 ctest 目标"，而不是一段没人调用的胶水。
#
# 这套用例用的是 node 官方的 driver，因此**依赖**：
#   * node 的 test-suite feature（装出 test/ 与 tools/）；
#   * 一个能当 shell 的 node 可执行文件 —— 优先用示例 example_embed 编出来的 node_embed
#     （顺带验证"消费方链出来的运行时"能跑官方套件），没有则用端口自带的 node_EXECUTABLE。
#     两条路都不通才警告并跳过，所以删掉那个示例也不会让本测试组消失。
include(${CMAKE_CURRENT_LIST_DIR}/ctest_node_suite.cmake)
