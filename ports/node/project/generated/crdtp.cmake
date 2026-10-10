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
#   蓝本    ：node-v24.21.0/deps/inspector_protocol/inspector_protocol.gyp（目标 crdtp，gyp 里的类型 static_library）
#   编译单元：win 9 / linux 9 / mac 9（另外 win 13、linux 13、mac 13 个是头文件）

set(NODE_PORT_V8_CRDTP_IS_INTERFACE FALSE)
set(NODE_PORT_V8_CRDTP_IS_EXECUTABLE FALSE)

set(NODE_PORT_V8_CRDTP_SOURCES_WIN
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/cbor.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/dispatch.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/error_support.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/json.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/json_platform.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/protocol_core.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/serializable.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/span.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/status.cc
)
set(NODE_PORT_V8_CRDTP_SOURCES_LINUX
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/cbor.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/dispatch.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/error_support.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/json.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/json_platform.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/protocol_core.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/serializable.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/span.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/status.cc
)
set(NODE_PORT_V8_CRDTP_SOURCES_MAC
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/cbor.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/dispatch.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/error_support.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/json.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/json_platform.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/protocol_core.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/serializable.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/span.cc
  ${NODE_ROOT}/deps/inspector_protocol/crdtp/status.cc
)

set(NODE_PORT_V8_CRDTP_DEFINES
  "_GLIBCXX_USE_CXX11_ABI=1"
  "_FILE_OFFSET_BITS=64"
  "OPENSSL_NO_PINSHARED"
  "OPENSSL_THREADS"
)
set(NODE_PORT_V8_CRDTP_DEFINES_WIN
  "WIN32"
  "_CRT_SECURE_NO_DEPRECATE"
  "_CRT_NONSTDC_NO_DEPRECATE"
  "_HAS_EXCEPTIONS=0"
  "BUILDING_V8_SHARED=1"
  "BUILDING_UV_SHARED=1"
  "NOMINMAX"
)
set(NODE_PORT_V8_CRDTP_DEFINES_LINUX
  "__STDC_FORMAT_MACROS"
)
set(NODE_PORT_V8_CRDTP_DEFINES_MAC
  "_DARWIN_USE_64_BIT_INODE=1"
)

set(NODE_PORT_V8_CRDTP_INCLUDE_DIRS
  ${NODE_ROOT}/deps/inspector_protocol
)
set(NODE_PORT_V8_CRDTP_INCLUDE_DIRS_WIN
)
set(NODE_PORT_V8_CRDTP_INCLUDE_DIRS_LINUX
)
set(NODE_PORT_V8_CRDTP_INCLUDE_DIRS_MAC
)

set(NODE_PORT_V8_CRDTP_CFLAGS_LINUX
  "-pthread"
  "-Wall"
  "-Wextra"
  "-Wno-unused-parameter"
  "-m64"
  "-O3"
  "-fno-omit-frame-pointer"
)
set(NODE_PORT_V8_CRDTP_CFLAGS_MAC
  "-O3"
)
set(NODE_PORT_V8_CRDTP_CFLAGS_CC_LINUX
  "-fno-rtti"
  "-fno-exceptions"
  "-fno-strict-aliasing"
  "-std=gnu++20"
)
set(NODE_PORT_V8_CRDTP_LDFLAGS_LINUX
  "-pthread"
  "-rdynamic"
  "-m64"
)

set(NODE_PORT_V8_CRDTP_EXCEPTIONS FALSE)
# gyp 的 msvs_disabled_warnings（禁 7 个警告，不传就全刷屏）
set(NODE_PORT_V8_CRDTP_MSVS_DISABLED_WARNINGS
  /wd4351
  /wd4355
  /wd4800
  /wd4251
  /wd4275
  /wd4244
  /wd4267
)
# msvs_settings.VCCLCompilerTool：AdditionalOptions + WarningLevel /
# RuntimeTypeInfo / ExceptionHandling 翻出来的开关（Windows 专用）
set(NODE_PORT_V8_CRDTP_MSVS_FLAGS
  "/Zc:__cplusplus"
  "/Zm2000"
  "/W3"
  "/GR-"
  "/EHs-c-"
)

