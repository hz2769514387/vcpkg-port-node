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
#   蓝本    ：node-v24.21.0/node.gyp（目标 node_js2c，gyp 里的类型 executable）
#   编译单元：win 3 / linux 3 / mac 3（另外 win 3、linux 3、mac 3 个是头文件）

set(NODE_PORT_V8_NODE_JS2C_IS_INTERFACE FALSE)
set(NODE_PORT_V8_NODE_JS2C_IS_EXECUTABLE TRUE)

set(NODE_PORT_V8_NODE_JS2C_SOURCES_WIN
  ${NODE_ROOT}/tools/js2c.cc
  ${NODE_ROOT}/src/embedded_data.cc
  ${NODE_ROOT}/src/builtin_info.cc
)
set(NODE_PORT_V8_NODE_JS2C_SOURCES_LINUX
  ${NODE_ROOT}/tools/js2c.cc
  ${NODE_ROOT}/src/embedded_data.cc
  ${NODE_ROOT}/src/builtin_info.cc
)
set(NODE_PORT_V8_NODE_JS2C_SOURCES_MAC
  ${NODE_ROOT}/tools/js2c.cc
  ${NODE_ROOT}/src/embedded_data.cc
  ${NODE_ROOT}/src/builtin_info.cc
)

set(NODE_PORT_V8_NODE_JS2C_DEFINES
  "_GLIBCXX_USE_CXX11_ABI=1"
  "_FILE_OFFSET_BITS=64"
  "OPENSSL_NO_PINSHARED"
  "OPENSSL_THREADS"
)
set(NODE_PORT_V8_NODE_JS2C_DEFINES_WIN
  "WIN32"
  "_CRT_SECURE_NO_DEPRECATE"
  "_CRT_NONSTDC_NO_DEPRECATE"
  "_HAS_EXCEPTIONS=0"
  "BUILDING_V8_SHARED=1"
  "BUILDING_UV_SHARED=1"
  "NOMINMAX"
)
set(NODE_PORT_V8_NODE_JS2C_DEFINES_LINUX
  "__STDC_FORMAT_MACROS"
  "NODE_JS2C_USE_STRING_LITERALS"
  "_LARGEFILE_SOURCE"
  "_POSIX_C_SOURCE=200112"
)
set(NODE_PORT_V8_NODE_JS2C_DEFINES_MAC
  "_DARWIN_USE_64_BIT_INODE=1"
  "NODE_JS2C_USE_STRING_LITERALS"
  "_LARGEFILE_SOURCE"
)

set(NODE_PORT_V8_NODE_JS2C_INCLUDE_DIRS
  ${NODE_ROOT}/tools
  ${NODE_ROOT}/src
  ${NODE_PORT_V8_ROOT}/third_party/simdutf
  ${NODE_ROOT}/deps/uv/include
)
set(NODE_PORT_V8_NODE_JS2C_INCLUDE_DIRS_WIN
)
set(NODE_PORT_V8_NODE_JS2C_INCLUDE_DIRS_LINUX
)
set(NODE_PORT_V8_NODE_JS2C_INCLUDE_DIRS_MAC
)

# gyp 的 `dependencies`（跨平台取并集；按名字去重，调用方自己映射）
set(NODE_PORT_V8_NODE_JS2C_DEPS
  libuv
  simdutf
)

set(NODE_PORT_V8_NODE_JS2C_CFLAGS_LINUX
  "-Wall"
  "-Wextra"
  "-Wno-unused-parameter"
  "-Wno-restrict"
  "-pthread"
  "-Wall"
  "-Wextra"
  "-Wno-unused-parameter"
  "-m64"
  "-O3"
  "-fno-omit-frame-pointer"
)
set(NODE_PORT_V8_NODE_JS2C_CFLAGS_MAC
  "-Wall"
  "-Wextra"
  "-Wno-unused-parameter"
  "-mbranch-protection=standard"
  "-O3"
)
set(NODE_PORT_V8_NODE_JS2C_CFLAGS_CC_LINUX
  "-fno-rtti"
  "-fno-exceptions"
  "-fno-strict-aliasing"
  "-std=gnu++20"
)
set(NODE_PORT_V8_NODE_JS2C_LDFLAGS_LINUX
  "-pthread"
  "-rdynamic"
  "-pthread"
  "-m64"
)
set(NODE_PORT_V8_NODE_JS2C_LDFLAGS_MAC
  "-pthread"
  "-Wl,-search_paths_first"
)

set(NODE_PORT_V8_NODE_JS2C_EXCEPTIONS FALSE)
# gyp 的 msvs_disabled_warnings（禁 7 个警告，不传就全刷屏）
set(NODE_PORT_V8_NODE_JS2C_MSVS_DISABLED_WARNINGS
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
set(NODE_PORT_V8_NODE_JS2C_MSVS_FLAGS
  "/Zc:__cplusplus"
  "/Zm2000"
  "/W3"
  "/GR-"
  "/EHs-c-"
)

