# 由 gyp2vcpkg 生成 —— 不要手改，改了会被判为过期。
#   生成命令：python ../gyp2vcpkg/gyp2vcpkg.py all --config ../gyp2vcpkg/config.json
#   指纹    ：../gyp2vcpkg/resolve.py dd1094c2b980abfe
#             ../gyp2vcpkg/collect.py bad964667d786dc9
#             ../gyp2vcpkg/generate.py faa73f3b43a0a9ef
#             ../gyp2vcpkg/_dump_generator.py 1c32cb74b4bccbe1
#             ../gyp2vcpkg/config.json 4304a096a04026f7
#             ../gyp2vcpkg/env/win-x64.json 2ac8390bd45101df
#             ../gyp2vcpkg/env/linux-x64.json a37e3877ca8397b2
#             ../gyp2vcpkg/env/darwin-arm64.json 50eb464ee2df40e5
#   蓝本    ：node-v24.21.0/tools/v8_gypfiles/v8.gyp 里 v8_snapshot 的 action「run_mksnapshot」
#   输入 0 个；输出 2 个（1 个目录）

set(NODE_PORT_RUN_MKSNAPSHOT_TOOL mksnapshot)
# gyp 的 SHARED_INTERMEDIATE_DIR
set(NODE_PORT_RUN_MKSNAPSHOT_GEN ${NODE_PORT_V8_GENERATED})
# 工具往这里写（-o 那个参数；没有 -o 时就是第一个输出所在的目录）
set(NODE_PORT_RUN_MKSNAPSHOT_OUTDIR ${NODE_PORT_RUN_MKSNAPSHOT_GEN}/intermediate/v8_snapshot)
set(NODE_PORT_RUN_MKSNAPSHOT_INPUTS
)
set(NODE_PORT_RUN_MKSNAPSHOT_OUTPUTS
  ${NODE_PORT_RUN_MKSNAPSHOT_GEN}/intermediate/v8_snapshot/snapshot.cc
  ${NODE_PORT_RUN_MKSNAPSHOT_GEN}/intermediate/v8_snapshot/embedded.S
)
set(NODE_PORT_RUN_MKSNAPSHOT_OUTPUT_DIRS
  ${NODE_PORT_RUN_MKSNAPSHOT_GEN}/intermediate/v8_snapshot
)
set(NODE_PORT_RUN_MKSNAPSHOT_INTERMEDIATE ${NODE_PORT_V8_GENERATED}/intermediate/v8_snapshot)
# gyp 的 _inputs（命令行里引用的那批，含工具）
set(NODE_PORT_RUN_MKSNAPSHOT_IN_ALL
  "$<TARGET_FILE:mksnapshot>"
)
set(NODE_PORT_RUN_MKSNAPSHOT_CMD
  "$<TARGET_FILE:mksnapshot>"
  "--turbo_instruction_scheduling"
  "--stress-turbo-late-spilling"
  "--target_os=${NODE_PORT_TARGET_OS}"
  "--target_arch=x64"
  "--startup_src"
  "${NODE_PORT_V8_GENERATED}/intermediate/v8_snapshot/snapshot.cc"
  "--embedded_variant"
  "Default"
  "--embedded_src"
  "${NODE_PORT_V8_GENERATED}/intermediate/v8_snapshot/embedded.S"
  "--concurrent-builtin-generation"
  "--concurrent-turbofan-max-threads=0"
  "--no-native-code-counters"
)

