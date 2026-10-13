# 本仓库的内部测试 · node port 的 tools feature 冒烟
#
# 这是一个**ctest 目标组**：注册 tools-node-runs / tools-npm-version /
# tools-npx-version / tools-corepack-version —— 验证端口装出来的
# node / npm / npx / corepack 这一套能跑、版本对得上。
# 注册逻辑在 ctest_tools.cmake（本目录），这个文件只是让"它是 ctest 目标"一眼可见。
#
# 用的是端口 `tools` feature 装到 tools/node/ 下的那些文件（node_EXECUTABLE 等），
# 与示例目录无关 ⇒ 删掉任何示例都不影响本组。
include(${CMAKE_CURRENT_LIST_DIR}/ctest_tools.cmake)
