# 子项目：把 node 嵌进一个可执行 —— 它同时是"使用者最小验证"和 node 官方套件的 shell。
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
if(WIN32 AND DEFINED node_NODE_SOURCE_MANIFEST AND EXISTS "${node_NODE_SOURCE_MANIFEST}")
  target_link_options(node_embed PRIVATE
    "/MANIFEST:EMBED"
    "/MANIFESTINPUT:${node_NODE_SOURCE_MANIFEST}")
endif()

# MSVC 前端请显式声明源码是 UTF-8（本文件注释是中文）。
if(MSVC)
  target_compile_options(node_embed PRIVATE /utf-8)
endif()

# ---- 冒烟：版本断言（T2）------------------------------------------------------
# 一次断言就把"库真的链接成功 + 运行时真的跑起来 + 版本对得上"三件事一起验了。
add_test(NAME smoke-node-version
         COMMAND node_embed -e "process.stdout.write(process.versions.node)")
set_tests_properties(smoke-node-version PROPERTIES
  LABELS "smoke"
  # 不加 `^...$` 锚：ctest 的正则不是多行模式，Windows 上输出以 CRLF 结尾，
  # `$` 卡在 `\r` 前面（实测 `^24\.21\.0[[:space:]]*$` 也红，输出确实是 24.21.0）。
  # 我们要断言的是"版本号等于 24.21.0"，直接匹配它本身。
  PASS_REGULAR_EXPRESSION "24\\.21\\.0")
