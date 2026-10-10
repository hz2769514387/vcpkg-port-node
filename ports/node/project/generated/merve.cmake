# 由 gyp2vcpkg 生成 —— 不要手改，改了会被判为过期。
#   生成命令：python ../gyp2vcpkg/gyp2vcpkg.py all --config ../gyp2vcpkg/config.json
#   指纹    ：../gyp2vcpkg/resolve.py 34eb26e83830e71f
#             ../gyp2vcpkg/collect.py 69a202ae8e388ee3
#             ../gyp2vcpkg/generate.py b91b0bec8bc781f3
#             ../gyp2vcpkg/_dump_generator.py d3fe1a95334e65ee
#             ../gyp2vcpkg/config.json 4304a096a04026f7
#             ../gyp2vcpkg/env/win-x64.json 2ac8390bd45101df
#             ../gyp2vcpkg/env/linux-x64.json a37e3877ca8397b2
#             ../gyp2vcpkg/env/darwin-arm64.json 50eb464ee2df40e5
#   蓝本    ：node-v24.21.0/deps/merve/merve.gyp（目标 merve，gyp 里的类型 static_library）
#   编译单元：win 1 / linux 1 / mac 1（另外 win 0、linux 0、mac 0 个是头文件）

set(NODE_PORT_V8_MERVE_IS_INTERFACE FALSE)
set(NODE_PORT_V8_MERVE_IS_EXECUTABLE FALSE)

set(NODE_PORT_V8_MERVE_SOURCES_WIN
  ${NODE_ROOT}/deps/merve/merve.cpp
)
set(NODE_PORT_V8_MERVE_SOURCES_LINUX
  ${NODE_ROOT}/deps/merve/merve.cpp
)
set(NODE_PORT_V8_MERVE_SOURCES_MAC
  ${NODE_ROOT}/deps/merve/merve.cpp
)

set(NODE_PORT_V8_MERVE_DEFINES
  "_GLIBCXX_USE_CXX11_ABI=1"
  "_FILE_OFFSET_BITS=64"
  "OPENSSL_NO_PINSHARED"
  "OPENSSL_THREADS"
)
set(NODE_PORT_V8_MERVE_DEFINES_WIN
  "WIN32"
  "_CRT_SECURE_NO_DEPRECATE"
  "_CRT_NONSTDC_NO_DEPRECATE"
  "_HAS_EXCEPTIONS=0"
  "BUILDING_V8_SHARED=1"
  "BUILDING_UV_SHARED=1"
  "NOMINMAX"
)
set(NODE_PORT_V8_MERVE_DEFINES_LINUX
  "__STDC_FORMAT_MACROS"
)
set(NODE_PORT_V8_MERVE_DEFINES_MAC
  "_DARWIN_USE_64_BIT_INODE=1"
)

set(NODE_PORT_V8_MERVE_INCLUDE_DIRS
  ${NODE_ROOT}/deps/merve
  ${NODE_PORT_V8_ROOT}/third_party/simdutf
)
set(NODE_PORT_V8_MERVE_INCLUDE_DIRS_WIN
)
set(NODE_PORT_V8_MERVE_INCLUDE_DIRS_LINUX
)
set(NODE_PORT_V8_MERVE_INCLUDE_DIRS_MAC
)

set(NODE_PORT_V8_MERVE_CFLAGS_LINUX
  "-pthread"
  "-Wall"
  "-Wextra"
  "-Wno-unused-parameter"
  "-m64"
  "-O3"
  "-fno-omit-frame-pointer"
)
set(NODE_PORT_V8_MERVE_CFLAGS_MAC
  "-O3"
)
set(NODE_PORT_V8_MERVE_CFLAGS_CC_LINUX
  "-fno-rtti"
  "-fno-exceptions"
  "-fno-strict-aliasing"
  "-std=gnu++20"
  "-std=c++20"
)
set(NODE_PORT_V8_MERVE_CFLAGS_CC_MAC
  "-std=c++20"
)
set(NODE_PORT_V8_MERVE_LDFLAGS_LINUX
  "-pthread"
  "-rdynamic"
  "-m64"
)

set(NODE_PORT_V8_MERVE_EXCEPTIONS FALSE)
# gyp 的 msvs_disabled_warnings（禁 7 个警告，不传就全刷屏）
set(NODE_PORT_V8_MERVE_MSVS_DISABLED_WARNINGS
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
set(NODE_PORT_V8_MERVE_MSVS_FLAGS
  "/Zc:__cplusplus"
  "/Zm2000"
  "/std:c++20"
  "/W3"
  "/GR-"
  "/EHs-c-"
)

