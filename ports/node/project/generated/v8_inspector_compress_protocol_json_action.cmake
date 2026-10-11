# 由 gyp2vcpkg 生成 —— 不要手改，改了会被判为过期。
#   生成命令：python ../gyp2vcpkg/gyp2vcpkg.py all --config ../gyp2vcpkg/config.json
#   指纹    ：../gyp2vcpkg/resolve.py dd1094c2b980abfe
#             ../gyp2vcpkg/collect.py bad964667d786dc9
#             ../gyp2vcpkg/generate.py 073d946e6a47a475
#             ../gyp2vcpkg/_dump_generator.py 1c32cb74b4bccbe1
#             ../gyp2vcpkg/config.json 4304a096a04026f7
#             ../gyp2vcpkg/env/win-x64.json 2ac8390bd45101df
#             ../gyp2vcpkg/env/linux-x64.json a37e3877ca8397b2
#             ../gyp2vcpkg/env/darwin-arm64.json 50eb464ee2df40e5
#   蓝本    ：C:\work\git\fe\deps\node\node-v24.21.0\node.gyp 里 node_base 的 action「v8_inspector_compress_protocol_json」
#   输入 1 个；输出 1 个（0 个目录）

# gyp 的 SHARED_INTERMEDIATE_DIR
set(NODE_PORT_V8_INSPECTOR_COMPRESS_PROTOCOL_JSON_GEN ${NODE_PORT_V8_GENERATED})
# 工具往这里写（-o 那个参数；没有 -o 时就是第一个输出所在的目录）
set(NODE_PORT_V8_INSPECTOR_COMPRESS_PROTOCOL_JSON_OUTDIR ${NODE_PORT_V8_INSPECTOR_COMPRESS_PROTOCOL_JSON_GEN})
set(NODE_PORT_V8_INSPECTOR_COMPRESS_PROTOCOL_JSON_INPUTS
  ${NODE_PORT_V8_INSPECTOR_COMPRESS_PROTOCOL_JSON_GEN}/concatenated_protocol.json
)
set(NODE_PORT_V8_INSPECTOR_COMPRESS_PROTOCOL_JSON_OUTPUTS
  ${NODE_PORT_V8_INSPECTOR_COMPRESS_PROTOCOL_JSON_GEN}/v8_inspector_protocol_json.h
)
set(NODE_PORT_V8_INSPECTOR_COMPRESS_PROTOCOL_JSON_OUTPUT_DIRS
)
set(NODE_PORT_V8_INSPECTOR_COMPRESS_PROTOCOL_JSON_INTERMEDIATE ${NODE_PORT_V8_GENERATED}/intermediate/node_base)
# gyp 的 _inputs（命令行里引用的那批，含工具）
set(NODE_PORT_V8_INSPECTOR_COMPRESS_PROTOCOL_JSON_IN_ALL
  "${NODE_PORT_V8_INSPECTOR_COMPRESS_PROTOCOL_JSON_GEN}/concatenated_protocol.json"
)
set(NODE_PORT_V8_INSPECTOR_COMPRESS_PROTOCOL_JSON_CMD
  "${Python3_EXECUTABLE}"
  "tools/compress_json.py"
  "${NODE_PORT_V8_INSPECTOR_COMPRESS_PROTOCOL_JSON_GEN}/concatenated_protocol.json"
  "${NODE_PORT_V8_INSPECTOR_COMPRESS_PROTOCOL_JSON_GEN}/v8_inspector_protocol_json.h"
)

