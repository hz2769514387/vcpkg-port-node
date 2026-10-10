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
#   蓝本    ：node-v24.21.0/node.gyp 里 node_base 的 action「concatenate_protocols」
#   输入 2 个；输出 1 个（0 个目录）

# gyp 的 SHARED_INTERMEDIATE_DIR
set(NODE_PORT_CONCATENATE_PROTOCOLS_GEN ${NODE_PORT_V8_GENERATED})
# 工具往这里写（-o 那个参数；没有 -o 时就是第一个输出所在的目录）
set(NODE_PORT_CONCATENATE_PROTOCOLS_OUTDIR ${NODE_PORT_CONCATENATE_PROTOCOLS_GEN})
set(NODE_PORT_CONCATENATE_PROTOCOLS_INPUTS
  ${NODE_PORT_V8_ROOT}/include/js_protocol.pdl
  ${NODE_PORT_CONCATENATE_PROTOCOLS_GEN}/src/node_protocol.json
)
set(NODE_PORT_CONCATENATE_PROTOCOLS_OUTPUTS
  ${NODE_PORT_CONCATENATE_PROTOCOLS_GEN}/concatenated_protocol.json
)
set(NODE_PORT_CONCATENATE_PROTOCOLS_OUTPUT_DIRS
)
set(NODE_PORT_CONCATENATE_PROTOCOLS_INTERMEDIATE ${NODE_PORT_V8_GENERATED}/intermediate/node_base)
# gyp 的 _inputs（命令行里引用的那批，含工具）
set(NODE_PORT_CONCATENATE_PROTOCOLS_IN_ALL
  "${NODE_PORT_V8_ROOT}/include/js_protocol.pdl"
  "${NODE_PORT_CONCATENATE_PROTOCOLS_GEN}/src/node_protocol.json"
)
set(NODE_PORT_CONCATENATE_PROTOCOLS_CMD
  "${Python3_EXECUTABLE}"
  "${NODE_ROOT}/deps/inspector_protocol/concatenate_protocols.py"
  "${NODE_PORT_V8_ROOT}/include/js_protocol.pdl"
  "${NODE_PORT_CONCATENATE_PROTOCOLS_GEN}/src/node_protocol.json"
  "${NODE_PORT_CONCATENATE_PROTOCOLS_GEN}/concatenated_protocol.json"
)

