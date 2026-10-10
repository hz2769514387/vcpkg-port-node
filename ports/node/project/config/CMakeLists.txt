# 生成 config.gypi（`9.0-P-3`）。
#
# node_js2c 强制要一个 config.gypi，而且它是**被原样嵌进产物**的（process.config 的来源，
# 要与官方包对照，`9.0-V-1`）。所以我们不猜 configure.py 的选项名，而是**拿官方二进制
# 导出的那份 process.config 当种子**（`gyp2vcpkg/env/<平台>.json`），只覆盖确实随平台变
# 的少数几项。生成用 python（`seed_gypi.py`）—— node 构建搬进 port 后没有 node 可跑脚本。

set(NODE_PORT_GENERATED "${CMAKE_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${NODE_PORT_GENERATED}")

if(WIN32)
  set(NODE_PORT_ENV_SEED "${NODE_PORT_GYP2VCPKG_TOOL}/env/win-x64.json")
elseif(APPLE)
  set(NODE_PORT_ENV_SEED "${NODE_PORT_GYP2VCPKG_TOOL}/env/darwin-arm64.json")
else()
  set(NODE_PORT_ENV_SEED "${NODE_PORT_GYP2VCPKG_TOOL}/env/linux-x64.json")
endif()
if(NOT EXISTS "${NODE_PORT_ENV_SEED}")
  message(FATAL_ERROR "缺本平台的变量环境：${NODE_PORT_ENV_SEED}")
endif()

# ---- 随平台/决策变的少数几项 --------------------------------------------
# 目标架构：直接从 triplet 名取前缀（x64-linux-gcc → x64），不另发明一套。
string(REGEX MATCH "^[a-z0-9_]+" NODE_PORT_TARGET_ARCH "${VCPKG_TARGET_TRIPLET}")
set(NODE_PORT_HOST_ARCH "${NODE_PORT_TARGET_ARCH}")   # 本工程不做交叉编译
set(NODE_PORT_BYTEORDER "little")

# 编译器：照 node 的做法各平台不同（工程约定第 2 条 / 调研-6）。
if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
  set(NODE_PORT_CLANG 1)
  set(NODE_PORT_LLVM_VERSION "${CMAKE_CXX_COMPILER_VERSION}")
  set(NODE_PORT_GCC_VERSION "")
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  set(NODE_PORT_CLANG 0)
  set(NODE_PORT_LLVM_VERSION "0.0")
  set(NODE_PORT_GCC_VERSION "${CMAKE_C_COMPILER_VERSION}")
else()
  set(NODE_PORT_CLANG 0)
  set(NODE_PORT_LLVM_VERSION "0.0")
  set(NODE_PORT_GCC_VERSION "")
endif()

# node_prefix：照官方包实测的值（Windows "\\usr\\local"，Linux/macOS "/"）。
if(WIN32)
  set(NODE_PORT_PREFIX "\\\\usr\\\\local")
else()
  set(NODE_PORT_PREFIX "/")
endif()

# 覆盖项的值一律是 JSON（字符串要带引号）。
set(NODE_PORT_ARGS
  "host_arch=\"${NODE_PORT_HOST_ARCH}\""
  "target_arch=\"${NODE_PORT_TARGET_ARCH}\""
  "node_byteorder=\"${NODE_PORT_BYTEORDER}\""
  "node_prefix=\"${NODE_PORT_PREFIX}\""
  "clang=${NODE_PORT_CLANG}"
  "llvm_version=\"${NODE_PORT_LLVM_VERSION}\"")
if(NOT NODE_PORT_GCC_VERSION STREQUAL "")
  list(APPEND NODE_PORT_ARGS "gcc_version=\"${NODE_PORT_GCC_VERSION}\"")
endif()

add_custom_command(
  OUTPUT "${NODE_PORT_GENERATED}/config.gypi"
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_LIST_DIR}/seed_gypi.py"
          "${NODE_PORT_ENV_SEED}"
          "${NODE_PORT_GENERATED}/config.gypi"
          ${NODE_PORT_ARGS}
  DEPENDS "${CMAKE_CURRENT_LIST_DIR}/seed_gypi.py"
          "${NODE_PORT_ENV_SEED}"
  COMMENT "生成 config.gypi（会被嵌入产物，是 process.config 的来源）"
  VERBATIM)

add_custom_target(node_port_config_gypi DEPENDS "${NODE_PORT_GENERATED}/config.gypi")
set(NODE_PORT_CONFIG_GYPI "${NODE_PORT_GENERATED}/config.gypi" PARENT_SCOPE)