# port 的 tools feature 输出（node 可执行 + npm/npx/corepack）也要被真跑一遍。
#
# 这一组存在的意义：确认"使用者从 port 的安装产物里拿到可执行"这条路是通的 ——
# test 不自己去猜路径，只用 node-config.cmake 导出的变量（vcpkg 惯例）。
if(NOT node_EXECUTABLE)
  message(STATUS "tools 用例：未启用 node 的 tools feature（没有 node_EXECUTABLE），跳过")
  return()
endif()

message(STATUS "tools 用例：node_EXECUTABLE=${node_EXECUTABLE}")

add_test(NAME tools-node-runs COMMAND "${node_EXECUTABLE}" -p "process.versions.node")
set_tests_properties(tools-node-runs PROPERTIES
  LABELS "tools"
  PASS_REGULAR_EXPRESSION "24\\.21\\.0")

# Windows 上 npm 是 .cmd。★ 直接把 .cmd 交给 ctest（CreateProcess 会自动经 cmd.exe 起），
#   **不要**写 `COMMAND cmd /c ...`：
#   * ctest 会把每个参数都加引号，`"/c"` 带引号 cmd 不认 → "命令语法不正确"（实测踩到过）；
#   * cmd 也不认正斜杠的程序名。
#   路径用 node-config 导出的可移植正斜杠形式即可，CreateProcess 会归一化。
if(WIN32)
  add_test(NAME tools-npm-version COMMAND "${node_NPM}" --version)
  add_test(NAME tools-npx-version COMMAND "${node_NPX}" --version)
else()
  add_test(NAME tools-npm-version COMMAND "${node_NPM}" --version)
  add_test(NAME tools-npx-version COMMAND "${node_NPX}" --version)
endif()
set_tests_properties(tools-npm-version tools-npx-version PROPERTIES
  LABELS "tools"
  TIMEOUT 300)

# corepack --version 在有些环境会去读 HOME/缓存；读到就把版本打出来，读不到也不该挂。
add_test(NAME tools-corepack-version COMMAND "${node_COREPACK}" --version)
set_tests_properties(tools-corepack-version PROPERTIES LABELS "tools" TIMEOUT 300)
