# 由 gyp2vcpkg 生成 —— 不要手改，改了会被判为过期。
#   生成命令：python ../gyp2vcpkg/gyp2vcpkg.py all --config ../gyp2vcpkg/config.json
#   指纹    ：../gyp2vcpkg/resolve.py 34eb26e83830e71f
#             ../gyp2vcpkg/collect.py 69a202ae8e388ee3
#             ../gyp2vcpkg/generate.py b91b0bec8bc781f3
#             ../gyp2vcpkg/_dump_generator.py d3fe1a95334e65ee
#             ../gyp2vcpkg/config.json 4304a096a04026f7
#             ../gyp2vcpkg/env/win-x64.json 2ac8390bd45101df
#             ../gyp2vcpkg/env/linux-x64.json a37e3877ca8397b2
#   蓝本    ：node-v24.21.0/node.gyp（目标 node，gyp 里的类型 executable）
#   编译单元：win 2 / linux 1（另外 win 3、linux 0 个是头文件）

set(NODE_PORT_V8_NODE_IS_INTERFACE FALSE)
set(NODE_PORT_V8_NODE_IS_EXECUTABLE TRUE)

set(NODE_PORT_V8_NODE_SOURCES_WIN
  ${NODE_ROOT}/src/node_main.cc
  ${NODE_ROOT}/tools/msvs/pch/node_pch.cc
)
set(NODE_PORT_V8_NODE_SOURCES_LINUX
  ${NODE_ROOT}/src/node_main.cc
)

set(NODE_PORT_V8_NODE_DEFINES
  "_GLIBCXX_USE_CXX11_ABI=1"
  "_FILE_OFFSET_BITS=64"
  "OPENSSL_NO_PINSHARED"
  "OPENSSL_THREADS"
  "NODE_ARCH=\"x64\""
  "NODE_WANT_INTERNALS=1"
  "NODE_USE_V8_PLATFORM=1"
  "NODE_HAVE_I18N_SUPPORT=1"
  "NODE_BUNDLED_ZLIB"
  "NODE_BUNDLED_ZSTD"
  "HAVE_OPENSSL=1"
  "OPENSSL_API_COMPAT=0x10100000L"
  "HAVE_AMARO=1"
  "HAVE_SQLITE=1"
  "HAVE_QUIC=0"
  "XXH_NAMESPACE=ZSTD_"
  "ZSTD_MULTITHREAD"
  "ZSTD_DISABLE_ASM"
  "NGHTTP2_STATICLIB"
  "NDEBUG"
  "OPENSSL_BUILDING_OPENSSL"
  "AES_ASM"
  "BSAES_ASM"
  "CMLL_ASM"
  "ECP_NISTZ256_ASM"
  "GHASH_ASM"
  "KECCAK1600_ASM"
  "MD5_ASM"
  "OPENSSL_BN_ASM_GF2m"
  "OPENSSL_BN_ASM_MONT"
  "OPENSSL_BN_ASM_MONT5"
  "OPENSSL_CPUID_OBJ"
  "OPENSSL_IA32_SSE2"
  "PADLOCK_ASM"
  "POLY1305_ASM"
  "RC4_ASM"
  "SHA1_ASM"
  "SHA256_ASM"
  "SHA512_ASM"
  "VPAES_ASM"
  "WHIRLPOOL_ASM"
  "X25519_ASM"
  "OPENSSL_PIC"
)
set(NODE_PORT_V8_NODE_DEFINES_WIN
  "WIN32"
  "_CRT_SECURE_NO_DEPRECATE"
  "_CRT_NONSTDC_NO_DEPRECATE"
  "_HAS_EXCEPTIONS=0"
  "BUILDING_V8_SHARED=1"
  "BUILDING_UV_SHARED=1"
  "NOMINMAX"
  "FD_SETSIZE=1024"
  "NODE_PLATFORM=\"win32\""
  "_UNICODE=1"
  "OPENSSL_SYS_WIN32"
  "WIN32_LEAN_AND_MEAN"
  "UNICODE"
  "_UNICODE"
  "_WINSOCK_DEPRECATED_NO_WARNINGS"
)
set(NODE_PORT_V8_NODE_DEFINES_LINUX
  "__STDC_FORMAT_MACROS"
  "NODE_PLATFORM=\"linux\""
  "__POSIX__"
  "_LARGEFILE_SOURCE"
  "_POSIX_C_SOURCE=200112"
  "OPENSSL_USE_NODELETE"
  "L_ENDIAN"
)

set(NODE_PORT_V8_NODE_INCLUDE_DIRS
  ${NODE_ROOT}/src
  ${NODE_PORT_V8_ROOT}/include
  ${NODE_ROOT}/deps/postject
  ${NODE_ROOT}/deps/histogram/src
  ${NODE_ROOT}/deps/histogram/include
  ${NODE_ROOT}/deps/zlib
  ${NODE_ROOT}/deps/llhttp/include
  ${NODE_ROOT}/deps/cares/include
  ${NODE_ROOT}/deps/uv/include
  ${NODE_ROOT}/deps/uvwasi/include
  ${NODE_ROOT}/deps/nghttp2/lib/includes
  ${NODE_ROOT}/deps/ada
  ${NODE_ROOT}/deps/merve
  ${NODE_ROOT}/deps/simdjson
  ${NODE_PORT_V8_ROOT}/third_party/simdutf
  ${NODE_ROOT}/deps/brotli/c/include
  ${NODE_ROOT}/deps/sqlite
  ${NODE_ROOT}/deps/zstd/lib
  ${NODE_ROOT}/deps/openssl/openssl/include
  ${NODE_ROOT}/deps/openssl/openssl/crypto/include
)
set(NODE_PORT_V8_NODE_INCLUDE_DIRS_WIN
  ${NODE_ROOT}/deps/openssl/config/archs/VC-WIN64A/asm/include
  ${NODE_ROOT}/deps/openssl/config/archs/VC-WIN64A/asm
)
set(NODE_PORT_V8_NODE_INCLUDE_DIRS_LINUX
  ${NODE_ROOT}/deps/openssl/config/archs/linux-x86_64/asm/include
  ${NODE_ROOT}/deps/openssl/config/archs/linux-x86_64/asm
)

# gyp 的 `dependencies`（跨平台取并集；按名字去重，调用方自己映射）
set(NODE_PORT_V8_NODE_DEPS
  ada
  brotli
  cares
  histogram
  icui18n
  icuuc
  libnode
  libuv
  llhttp
  merve
  nghttp2
  node_text_start
  openssl
  openssl-cli
  simdjson
  simdutf
  sqlite
  uvwasi
  v8_libplatform
  v8_snapshot
  zlib
  zstd
)

set(NODE_PORT_V8_NODE_CFLAGS_LINUX
  "-Wall"
  "-Wextra"
  "-Wno-unused-parameter"
  "-Wno-restrict"
  "-pthread"
  "-Wall"
  "-Wextra"
  "-Wno-unused-parameter"
  "-Wno-error=deprecated-declarations"
  "-m64"
  "-O3"
  "-fno-omit-frame-pointer"
)
set(NODE_PORT_V8_NODE_CFLAGS_CC_LINUX
  "-fno-rtti"
  "-fno-exceptions"
  "-fno-strict-aliasing"
  "-std=gnu++20"
)
#   gyp 的 ldflags 里有 16 项是把构建产物整份塞进链接的写法（__GYP_PRODUCT_DIR__/obj.target/node_text_start/src/large_pages/node_text_start.o…），翻不成 CMake，调用方要自己写 $<LINK_LIBRARY:WHOLE_ARCHIVE,…>
set(NODE_PORT_V8_NODE_LDFLAGS_LINUX
  "-pthread"
  "-rdynamic"
  "-Wl,-z,noexecstack"
  "-Wl,-z,relro"
  "-Wl,-z,now"
  "-pthread"
  "-m64"
)

set(NODE_PORT_V8_NODE_EXCEPTIONS FALSE)
# gyp 的 msvs_disabled_warnings（禁 6 个警告，不传就全刷屏）
set(NODE_PORT_V8_NODE_MSVS_DISABLED_WARNINGS
  /wd4351
  /wd4355
  /wd4800
  /wd4251
  /wd4275
  /wd4267
)
# msvs_settings.VCCLCompilerTool：AdditionalOptions + WarningLevel /
# RuntimeTypeInfo / ExceptionHandling 翻出来的开关（Windows 专用）
set(NODE_PORT_V8_NODE_MSVS_FLAGS
  "/Zc:__cplusplus"
  "/Zm2000"
  "-flto=thin"
  "/W3"
  "/GR-"
  "/EHs-c-"
)

