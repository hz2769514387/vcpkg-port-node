# 消费方示例 · 场景一：把 node 嵌进自己的可执行
#
# 这是**示例**，不是本仓库的内部测试：它只演示"一个普通项目怎么用 node port"——
# 把 unofficial::node::node 链进自己的可执行，让它变成 node 运行时。
#
# 但它**自带测试**（见文件末尾），因为：
#   1) 示例必须真能跑通，否则它就只是一段"看起来对"的代码；
#   2) 一个正经的消费方项目本来就该有测试 —— 这里顺手做个样子。
# 测试用的是本目录编出来的 node_embed 自己，不依赖任何其它目录
# （所以单独删掉这个示例也不会牵连别的示例或内部测试）。
#
# 目标名是 node_embed，产物名故意叫 `node`：
#   * node 官方用例里有不少地方按 `process.execPath` 去 spawn 子进程、并按 node 的
#     命令行语义传参，产物叫 node 最贴近官方环境；
#   * CMake 里仍用 node_embed 这个名字，避免和 unofficial::node::node 之类混在一起。
add_executable(node_embed main.cpp)
set_target_properties(node_embed PROPERTIES OUTPUT_NAME node)
target_link_libraries(node_embed PRIVATE unofficial::node::node)
target_compile_features(node_embed PRIVATE cxx_std_20)

# Windows：目标必须嵌 node 的平台兼容性清单，否则进程一启动就退出码 216（实测）。
# node 的消费配置导出了清单路径变量 `node_NODE_SOURCE_MANIFEST`。
# ★ /INCREMENTAL:NO 不能省：Debug 构建默认带 /INCREMENTAL，cmake 的 vs_link_exe
#   会改走"增量"两遍链接，并在链接命令尾部追加裸 /MANIFEST /MANIFESTFILE: ——
#   它把我们这条 /MANIFESTINPUT: 的嵌入模式顶掉，lld-link 直接报
#   `/manifestinput: requires /manifest:embed`（2026-10-14 ci debug 首跑实测；
#   Release 不复现，因为非增量路径没有这段追加）。关掉增量 = 回到 Release
#   同一条已经验证过的链接路径。
if(WIN32 AND DEFINED node_NODE_SOURCE_MANIFEST AND EXISTS "${node_NODE_SOURCE_MANIFEST}")
  target_link_options(node_embed PRIVATE
    "/MANIFEST:EMBED"
    "/MANIFESTINPUT:${node_NODE_SOURCE_MANIFEST}"
    "/INCREMENTAL:NO")
endif()

# MSVC 前端请显式声明源码是 UTF-8（本文件注释是中文）。
if(MSVC)
  target_compile_options(node_embed PRIVATE /utf-8)
endif()

# ---- 示例自带的测试 ----------------------------------------------------------
# 1) 版本断言：一次就把"库真的链接成功 + 运行时真的跑起来 + 版本对得上"三件事一起验了。
add_test(NAME example-embed-node-version
         COMMAND node_embed -e "process.stdout.write(process.versions.node)")
set_tests_properties(example-embed-node-version PROPERTIES
  LABELS "example;example_embed"
  # 不加 `^...$` 锚：ctest 的正则不是多行模式，Windows 上输出以 CRLF 结尾，
  # `$` 卡在 `\r` 前面（实测 `^24\.21\.0[[:space:]]*$` 也红，输出确实是 24.21.0）。
  # 我们要断言的是"版本号等于 24.21.0"，直接匹配它本身。
  PASS_REGULAR_EXPRESSION "24\\.21\\.0")

# 2) 跑一段 JS 并断言输出：演示"消费方怎么给自己嵌进去的运行时写测试"
#    （脚本就在本目录 demo.js，用法和平时的 `node xxx.js` 一样）。
add_test(NAME example-embed-run-js
         COMMAND node_embed "${CMAKE_CURRENT_SOURCE_DIR}/demo.js")
set_tests_properties(example-embed-run-js PROPERTIES
  LABELS "example;example_embed"
  TIMEOUT 300
  PASS_REGULAR_EXPRESSION "EMBED-DEMO-OK")
