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
#   蓝本    ：node-v24.21.0/node.gyp（目标 libnode，gyp 里的类型 static_library）
#   编译单元：win 1 / linux 0 / mac 0（另外 win 389、linux 388、mac 388 个是头文件）

set(NODE_PORT_V8_LIBNODE_IS_INTERFACE FALSE)
set(NODE_PORT_V8_LIBNODE_IS_EXECUTABLE FALSE)

set(NODE_PORT_V8_LIBNODE_SOURCES_WIN
  ${NODE_ROOT}/tools/msvs/pch/node_pch.cc
)
set(NODE_PORT_V8_LIBNODE_SOURCES_LINUX
)
set(NODE_PORT_V8_LIBNODE_SOURCES_MAC
)

set(NODE_PORT_V8_LIBNODE_DEFINES
  "_GLIBCXX_USE_CXX11_ABI=1"
  "_FILE_OFFSET_BITS=64"
  "OPENSSL_NO_PINSHARED"
  "OPENSSL_THREADS"
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
  "BSAES_ASM"
  "ECP_NISTZ256_ASM"
  "KECCAK1600_ASM"
  "MD5_ASM"
  "OPENSSL_BN_ASM_MONT"
  "OPENSSL_CPUID_OBJ"
  "POLY1305_ASM"
  "SHA1_ASM"
  "SHA256_ASM"
  "SHA512_ASM"
  "VPAES_ASM"
  "OPENSSL_PIC"
)
set(NODE_PORT_V8_LIBNODE_DEFINES_WIN
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
set(NODE_PORT_V8_LIBNODE_DEFINES_LINUX
  "__STDC_FORMAT_MACROS"
  "NODE_PLATFORM=\"linux\""
  "_POSIX_C_SOURCE=200112"
  "OPENSSL_USE_NODELETE"
)
set(NODE_PORT_V8_LIBNODE_DEFINES_MAC
  "_DARWIN_USE_64_BIT_INODE=1"
  "NODE_ARCH=\"arm64\""
  "NODE_RELEASE_URLBASE=\"https://nodejs.org/download/release/\""
  "NODE_PLATFORM=\"darwin\""
  "ECP_SM2P256_ASM"
  "OPENSSL_SM3_ASM"
  "SM4_ASM"
  "VPSM4_ASM"
)

set(NODE_PORT_V8_LIBNODE_INCLUDE_DIRS
  ${NODE_ROOT}/src
  ${NODE_PORT_V8_ROOT}/include
  ${NODE_ROOT}/deps/uv/include
  ${NODE_ROOT}/deps/zlib
  ${NODE_ROOT}/deps/llhttp/include
  ${NODE_ROOT}/deps/cares/include
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
set(NODE_PORT_V8_LIBNODE_INCLUDE_DIRS_WIN
  ${NODE_ROOT}/deps/openssl/config/archs/VC-WIN64A/asm/include
  ${NODE_ROOT}/deps/openssl/config/archs/VC-WIN64A/asm
)
set(NODE_PORT_V8_LIBNODE_INCLUDE_DIRS_LINUX
  ${NODE_ROOT}/deps/openssl/config/archs/linux-x86_64/asm/include
  ${NODE_ROOT}/deps/openssl/config/archs/linux-x86_64/asm
)
set(NODE_PORT_V8_LIBNODE_INCLUDE_DIRS_MAC
  ${NODE_ROOT}/deps/openssl/config/archs/darwin64-arm64-cc/asm/include
  ${NODE_ROOT}/deps/openssl/config/archs/darwin64-arm64-cc/asm
)

# gyp 的 `dependencies`（跨平台取并集；按名字去重，调用方自己映射）
set(NODE_PORT_V8_LIBNODE_DEPS
  ada
  brotli
  cares
  icui18n
  icuuc
  libuv
  llhttp
  merve
  nghttp2
  node_base
  node_mksnapshot
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

set(NODE_PORT_V8_LIBNODE_CFLAGS_LINUX
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
set(NODE_PORT_V8_LIBNODE_CFLAGS_MAC
  "-Wall"
  "-Wextra"
  "-Wno-unused-parameter"
  "-Werror=undefined-inline"
  "-Werror=extra-semi"
  "-Werror=ctad-maybe-unsupported"
  "-Wno-error=deprecated-declarations"
  "-mbranch-protection=standard"
  "-O3"
)
set(NODE_PORT_V8_LIBNODE_CFLAGS_CC_LINUX
  "-fno-rtti"
  "-fno-exceptions"
  "-fno-strict-aliasing"
  "-std=gnu++20"
)
set(NODE_PORT_V8_LIBNODE_LDFLAGS_LINUX
  "-pthread"
  "-rdynamic"
  "-Wl,-z,relro"
  "-Wl,-z,now"
  "-m64"
)

set(NODE_PORT_V8_LIBNODE_EXCEPTIONS FALSE)
# gyp 的 msvs_disabled_warnings（禁 7 个警告，不传就全刷屏）
set(NODE_PORT_V8_LIBNODE_MSVS_DISABLED_WARNINGS
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
set(NODE_PORT_V8_LIBNODE_MSVS_FLAGS
  "/Zc:__cplusplus"
  "/Zm2000"
  "/W3"
  "/GR-"
  "/EHs-c-"
)

