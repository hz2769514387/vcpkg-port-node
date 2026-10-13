# 本仓库的内部测试 · 符号审计（Windows）
#
# 这是一个**ctest 目标**：注册 `symbols-no-duplicate-strong`。
# 它用本工程自己编出来的 node 执行本目录的 symbol_check.js，
# 检查"node 的静态库与 vcpkg 库之间有没有重复强符号"。
#
# 之所以要有这个 CMakeLists.txt（而不是把 .js 单独丢在一个目录里）：
# 光看一个 .js 谁也不知道它由谁执行、是不是测试；写在这里就能明确"它是 ctest 目标"。
include(${CMAKE_CURRENT_LIST_DIR}/ctest_symbols.cmake)
