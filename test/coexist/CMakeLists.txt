# 行为级共存测试：同一个可执行里，node 的各类能力全部由链接进来的第三方库提供。
#
# 判据用 PASS_REGULAR_EXPRESSION 锚在脚本最后打印的 COEXIST-OK 上：
#   * 脚本内部任何一步 assert 失败都会非零退出；
#   * 只有真跑到最后一行才会打印 COEXIST-OK —— 避免"中途崩了但退出码侥幸为 0"。
add_test(NAME coexist-node-runtime
         COMMAND node_embed --experimental-sqlite "${CMAKE_CURRENT_SOURCE_DIR}/coexist.js")
set_tests_properties(coexist-node-runtime PROPERTIES
  LABELS "coexist"
  TIMEOUT 900
  PASS_REGULAR_EXPRESSION "COEXIST-OK")
