# 由 gyp2vcpkg 生成 —— 不要手改，改了会被判为过期。
#   生成命令：python ../gyp2vcpkg/gyp2vcpkg.py all --config ../gyp2vcpkg/config.json
#   指纹    ：../gyp2vcpkg/resolve.py 34eb26e83830e71f
#             ../gyp2vcpkg/collect.py 69a202ae8e388ee3
#             ../gyp2vcpkg/generate.py e471cc445dfec174
#             ../gyp2vcpkg/_dump_generator.py d3fe1a95334e65ee
#             ../gyp2vcpkg/config.json 4304a096a04026f7
#             ../gyp2vcpkg/env/win-x64.json 2ac8390bd45101df
#             ../gyp2vcpkg/env/linux-x64.json a37e3877ca8397b2
#             ../gyp2vcpkg/env/darwin-arm64.json 50eb464ee2df40e5
#   蓝本    ：node-v24.21.0/node.gyp 里 node_base 的 action「node_protocol_generated_sources」
#   输入 24 个；输出 19 个（1 个目录）

# gyp 的 SHARED_INTERMEDIATE_DIR
set(NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN ${NODE_PORT_V8_GENERATED})
# 工具往这里写（-o 那个参数；没有 -o 时就是第一个输出所在的目录）
set(NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_OUTDIR ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol)
set(NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_INPUTS
  ${NODE_ROOT}/src/inspector/node_protocol_config.json
  ${NODE_ROOT}/src/inspector/node_protocol.pdl
  ${NODE_ROOT}/src/inspector/domain_io.pdl
  ${NODE_ROOT}/src/inspector/domain_network.pdl
  ${NODE_ROOT}/src/inspector/domain_node_runtime.pdl
  ${NODE_ROOT}/src/inspector/domain_node_tracing.pdl
  ${NODE_ROOT}/src/inspector/domain_node_worker.pdl
  ${NODE_ROOT}/src/inspector/domain_target.pdl
  ${NODE_ROOT}/src/inspector/domain_dom_storage.pdl
  ${NODE_ROOT}/src/inspector/domain_storage.pdl
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node_protocol.json
  ${NODE_ROOT}/deps/inspector_protocol/lib/Forward_h.template
  ${NODE_ROOT}/deps/inspector_protocol/lib/Object_cpp.template
  ${NODE_ROOT}/deps/inspector_protocol/lib/Object_h.template
  ${NODE_ROOT}/deps/inspector_protocol/lib/Protocol_cpp.template
  ${NODE_ROOT}/deps/inspector_protocol/lib/ValueConversions_cpp.template
  ${NODE_ROOT}/deps/inspector_protocol/lib/ValueConversions_h.template
  ${NODE_ROOT}/deps/inspector_protocol/lib/Values_cpp.template
  ${NODE_ROOT}/deps/inspector_protocol/lib/Values_h.template
  ${NODE_ROOT}/deps/inspector_protocol/templates/Exported_h.template
  ${NODE_ROOT}/deps/inspector_protocol/templates/Imported_h.template
  ${NODE_ROOT}/deps/inspector_protocol/templates/TypeBuilder_cpp.template
  ${NODE_ROOT}/deps/inspector_protocol/templates/TypeBuilder_h.template
  ${NODE_ROOT}/deps/inspector_protocol/code_generator.py
)
set(NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_OUTPUTS
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/Forward.h
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/Protocol.cpp
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/Protocol.h
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/NodeWorker.cpp
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/NodeWorker.h
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/NodeTracing.cpp
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/NodeTracing.h
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/NodeRuntime.cpp
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/NodeRuntime.h
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/Network.cpp
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/Network.h
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/Target.cpp
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/Target.h
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/IO.h
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/IO.cpp
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/DOMStorage.h
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/DOMStorage.cpp
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/Storage.cpp
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol/Storage.h
)
set(NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_OUTPUT_DIRS
  ${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node/inspector/protocol
)
set(NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_INTERMEDIATE ${NODE_PORT_V8_GENERATED}/intermediate/node_base)
# gyp 的 _inputs（命令行里引用的那批，含工具）
set(NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_IN_ALL
  "${NODE_ROOT}/src/inspector/node_protocol_config.json"
  "${NODE_ROOT}/src/inspector/node_protocol.pdl"
  "${NODE_ROOT}/src/inspector/domain_io.pdl"
  "${NODE_ROOT}/src/inspector/domain_network.pdl"
  "${NODE_ROOT}/src/inspector/domain_node_runtime.pdl"
  "${NODE_ROOT}/src/inspector/domain_node_tracing.pdl"
  "${NODE_ROOT}/src/inspector/domain_node_worker.pdl"
  "${NODE_ROOT}/src/inspector/domain_target.pdl"
  "${NODE_ROOT}/src/inspector/domain_dom_storage.pdl"
  "${NODE_ROOT}/src/inspector/domain_storage.pdl"
  "${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/node_protocol.json"
  "${NODE_ROOT}/deps/inspector_protocol/lib/Forward_h.template"
  "${NODE_ROOT}/deps/inspector_protocol/lib/Object_cpp.template"
  "${NODE_ROOT}/deps/inspector_protocol/lib/Object_h.template"
  "${NODE_ROOT}/deps/inspector_protocol/lib/Protocol_cpp.template"
  "${NODE_ROOT}/deps/inspector_protocol/lib/ValueConversions_cpp.template"
  "${NODE_ROOT}/deps/inspector_protocol/lib/ValueConversions_h.template"
  "${NODE_ROOT}/deps/inspector_protocol/lib/Values_cpp.template"
  "${NODE_ROOT}/deps/inspector_protocol/lib/Values_h.template"
  "${NODE_ROOT}/deps/inspector_protocol/templates/Exported_h.template"
  "${NODE_ROOT}/deps/inspector_protocol/templates/Imported_h.template"
  "${NODE_ROOT}/deps/inspector_protocol/templates/TypeBuilder_cpp.template"
  "${NODE_ROOT}/deps/inspector_protocol/templates/TypeBuilder_h.template"
  "${NODE_ROOT}/deps/inspector_protocol/code_generator.py"
)
set(NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_CMD
  "${Python3_EXECUTABLE}"
  "${NODE_ROOT}/deps/inspector_protocol/code_generator.py"
  "--inspector_protocol_dir"
  "${NODE_ROOT}/deps/inspector_protocol"
  "--jinja_dir"
  "${NODE_ROOT}/tools/inspector_protocol"
  "--output_base"
  "${NODE_PORT_NODE_PROTOCOL_GENERATED_SOURCES_GEN}/src/"
  "--config"
  "${NODE_ROOT}/src/inspector/node_protocol_config.json"
)

