# 子项目：把 node 嵌进一个可执行，作为"使用者"的最小验证。
add_executable(smoke main.cpp)
target_link_libraries(smoke PRIVATE node::node)
target_compile_features(smoke PRIVATE cxx_std_17)

# Windows：目标必须嵌 node 的平台兼容性清单，否则进程一启动就退出码 216（实测）。
# node 的消费配置导出了清单路径变量 `node_NODE_SOURCE_MANIFEST`。
if(WIN32 AND DEFINED node_NODE_SOURCE_MANIFEST AND EXISTS "${node_NODE_SOURCE_MANIFEST}")
  target_link_options(smoke PRIVATE
    "/MANIFEST:EMBED"
    "/MANIFESTINPUT:${node_NODE_SOURCE_MANIFEST}")
endif()