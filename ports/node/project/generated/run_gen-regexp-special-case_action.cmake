# 由 gyp2vcpkg 生成 —— 不要手改，改了会被判为过期。
#   生成命令：python ../gyp2vcpkg/gyp2vcpkg.py all --config ../gyp2vcpkg/config.json
#   指纹    ：../gyp2vcpkg/resolve.py 34eb26e83830e71f
#             ../gyp2vcpkg/collect.py 69a202ae8e388ee3
#             ../gyp2vcpkg/generate.py b91b0bec8bc781f3
#             ../gyp2vcpkg/_dump_generator.py d3fe1a95334e65ee
#             ../gyp2vcpkg/config.json 4304a096a04026f7
#             ../gyp2vcpkg/env/win-x64.json 2ac8390bd45101df
#             ../gyp2vcpkg/env/linux-x64.json a37e3877ca8397b2
#   蓝本    ：node-v24.21.0/tools/v8_gypfiles/v8.gyp 里 run_gen-regexp-special-case 的 action「run_gen-regexp-special-case_action」
#   输入 0 个；输出 1 个（1 个目录）

set(NODE_PORT_RUN_GEN-REGEXP-SPECIAL-CASE_TOOL gen-regexp-special-case)
# gyp 的 SHARED_INTERMEDIATE_DIR
set(NODE_PORT_RUN_GEN-REGEXP-SPECIAL-CASE_GEN ${NODE_PORT_V8_GENERATED})
# 工具往这里写（-o 那个参数；没有 -o 时就是第一个输出所在的目录）
set(NODE_PORT_RUN_GEN-REGEXP-SPECIAL-CASE_OUTDIR ${NODE_PORT_RUN_GEN-REGEXP-SPECIAL-CASE_GEN}/src/regexp)
set(NODE_PORT_RUN_GEN-REGEXP-SPECIAL-CASE_INPUTS
)
set(NODE_PORT_RUN_GEN-REGEXP-SPECIAL-CASE_OUTPUTS
  ${NODE_PORT_RUN_GEN-REGEXP-SPECIAL-CASE_GEN}/src/regexp/special-case.cc
)
set(NODE_PORT_RUN_GEN-REGEXP-SPECIAL-CASE_OUTPUT_DIRS
  ${NODE_PORT_RUN_GEN-REGEXP-SPECIAL-CASE_GEN}/src/regexp
)
set(NODE_PORT_RUN_GEN-REGEXP-SPECIAL-CASE_INTERMEDIATE ${NODE_PORT_V8_GENERATED}/intermediate/run_gen-regexp-special-case)
# gyp 的 _inputs（命令行里引用的那批，含工具）
set(NODE_PORT_RUN_GEN-REGEXP-SPECIAL-CASE_IN_ALL
  "$<TARGET_FILE:gen-regexp-special-case>"
)
set(NODE_PORT_RUN_GEN-REGEXP-SPECIAL-CASE_CMD
  "${Python3_EXECUTABLE}"
  "${NODE_PORT_V8_ROOT}/tools/run.py"
  "$<TARGET_FILE:gen-regexp-special-case>"
  "${NODE_PORT_RUN_GEN-REGEXP-SPECIAL-CASE_GEN}/src/regexp/special-case.cc"
)

