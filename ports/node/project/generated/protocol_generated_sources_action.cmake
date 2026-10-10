# 由 gyp2vcpkg 生成 —— 不要手改，改了会被判为过期。
#   生成命令：python ../gyp2vcpkg/gyp2vcpkg.py all --config ../gyp2vcpkg/config.json
#   指纹    ：../gyp2vcpkg/resolve.py 34eb26e83830e71f
#             ../gyp2vcpkg/collect.py 69a202ae8e388ee3
#             ../gyp2vcpkg/generate.py 99aeddd76277b094
#             ../gyp2vcpkg/_dump_generator.py d3fe1a95334e65ee
#             ../gyp2vcpkg/config.json 4304a096a04026f7
#             ../gyp2vcpkg/env/win-x64.json 2ac8390bd45101df
#             ../gyp2vcpkg/env/linux-x64.json a37e3877ca8397b2
#             ../gyp2vcpkg/env/darwin-arm64.json 50eb464ee2df40e5
#   蓝本    ：node-v24.21.0/tools/v8_gypfiles/v8.gyp 里 v8_inspector_headers 的 action「protocol_generated_sources」
#   输入 14 个；输出 18 个（2 个目录）

# gyp 的 SHARED_INTERMEDIATE_DIR
set(NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN ${NODE_PORT_V8_GENERATED})
# 工具往这里写（-o 那个参数；没有 -o 时就是第一个输出所在的目录）
set(NODE_PORT_PROTOCOL_GENERATED_SOURCES_OUTDIR ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol)
set(NODE_PORT_PROTOCOL_GENERATED_SOURCES_INPUTS
  ${NODE_PORT_V8_ROOT}/include/js_protocol.pdl
  ${NODE_PORT_V8_ROOT}/src/inspector/inspector_protocol_config.json
  ${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/lib/Forward_h.template
  ${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/lib/Object_cpp.template
  ${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/lib/Object_h.template
  ${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/lib/Protocol_cpp.template
  ${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/lib/ValueConversions_h.template
  ${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/lib/Values_cpp.template
  ${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/lib/Values_h.template
  ${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/templates/Exported_h.template
  ${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/templates/Imported_h.template
  ${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/templates/TypeBuilder_cpp.template
  ${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/templates/TypeBuilder_h.template
  ${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/code_generator.py
)
set(NODE_PORT_PROTOCOL_GENERATED_SOURCES_OUTPUTS
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol/Forward.h
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol/Protocol.cpp
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol/Protocol.h
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol/Console.cpp
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol/Console.h
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol/Debugger.cpp
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol/Debugger.h
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol/HeapProfiler.cpp
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol/HeapProfiler.h
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol/Profiler.cpp
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol/Profiler.h
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol/Runtime.cpp
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol/Runtime.h
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol/Schema.cpp
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol/Schema.h
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/include/inspector/Debugger.h
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/include/inspector/Runtime.h
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/include/inspector/Schema.h
)
set(NODE_PORT_PROTOCOL_GENERATED_SOURCES_OUTPUT_DIRS
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/include/inspector
  ${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector/protocol
)
set(NODE_PORT_PROTOCOL_GENERATED_SOURCES_INTERMEDIATE ${NODE_PORT_V8_GENERATED}/intermediate/v8_inspector_headers)
# gyp 的 _inputs（命令行里引用的那批，含工具）
set(NODE_PORT_PROTOCOL_GENERATED_SOURCES_IN_ALL
  "${NODE_PORT_V8_ROOT}/include/js_protocol.pdl"
  "${NODE_PORT_V8_ROOT}/src/inspector/inspector_protocol_config.json"
  "${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/lib/Forward_h.template"
  "${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/lib/Object_cpp.template"
  "${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/lib/Object_h.template"
  "${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/lib/Protocol_cpp.template"
  "${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/lib/ValueConversions_h.template"
  "${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/lib/Values_cpp.template"
  "${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/lib/Values_h.template"
  "${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/templates/Exported_h.template"
  "${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/templates/Imported_h.template"
  "${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/templates/TypeBuilder_cpp.template"
  "${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/templates/TypeBuilder_h.template"
  "${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/code_generator.py"
)
set(NODE_PORT_PROTOCOL_GENERATED_SOURCES_CMD
  "${Python3_EXECUTABLE}"
  "${NODE_PORT_V8_ROOT}/third_party/inspector_protocol/code_generator.py"
  "--jinja_dir"
  "${NODE_PORT_V8_ROOT}/third_party"
  "--output_base"
  "${NODE_PORT_PROTOCOL_GENERATED_SOURCES_GEN}/inspector-generated-output-root/src/inspector"
  "--config"
  "${NODE_PORT_V8_ROOT}/src/inspector/inspector_protocol_config.json"
  "--config_value"
  "protocol.path=${NODE_PORT_V8_ROOT}/include/js_protocol.pdl"
  "--inspector_protocol_dir"
  "third_party/inspector_protocol"
)

