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
#   蓝本    ：node-v24.21.0/deps/ncrypto/ncrypto.gyp（目标 ncrypto，gyp 里的类型 static_library）
#   编译单元：win 1 / linux 1 / mac 1（另外 win 1、linux 1、mac 1 个是头文件）

set(NODE_PORT_V8_NCRYPTO_IS_INTERFACE FALSE)
set(NODE_PORT_V8_NCRYPTO_IS_EXECUTABLE FALSE)

set(NODE_PORT_V8_NCRYPTO_SOURCES_WIN
  ${NODE_ROOT}/deps/ncrypto/ncrypto.cc
)
set(NODE_PORT_V8_NCRYPTO_SOURCES_LINUX
  ${NODE_ROOT}/deps/ncrypto/ncrypto.cc
)
set(NODE_PORT_V8_NCRYPTO_SOURCES_MAC
  ${NODE_ROOT}/deps/ncrypto/ncrypto.cc
)

set(NODE_PORT_V8_NCRYPTO_DEFINES
  "_GLIBCXX_USE_CXX11_ABI=1"
  "_FILE_OFFSET_BITS=64"
  "OPENSSL_NO_PINSHARED"
  "OPENSSL_THREADS"
  "NCRYPTO_BSSL_LIBDECREPIT_MISSING=1"
  "OPENSSL_API_COMPAT=30000"
  "OPENSSL_NO_DEPRECATED"
  "XXH_NAMESPACE=ZSTD_"
  "ZSTD_MULTITHREAD"
  "ZSTD_DISABLE_ASM"
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
set(NODE_PORT_V8_NCRYPTO_DEFINES_WIN
  "WIN32"
  "_CRT_SECURE_NO_DEPRECATE"
  "_CRT_NONSTDC_NO_DEPRECATE"
  "_HAS_EXCEPTIONS=0"
  "BUILDING_V8_SHARED=1"
  "BUILDING_UV_SHARED=1"
  "NOMINMAX"
  "OPENSSL_SYS_WIN32"
  "WIN32_LEAN_AND_MEAN"
  "UNICODE"
  "_UNICODE"
  "_WINSOCK_DEPRECATED_NO_WARNINGS"
  "AES_ASM"
  "CMLL_ASM"
  "GHASH_ASM"
  "OPENSSL_BN_ASM_GF2m"
  "OPENSSL_BN_ASM_MONT5"
  "OPENSSL_IA32_SSE2"
  "PADLOCK_ASM"
  "RC4_ASM"
  "WHIRLPOOL_ASM"
  "X25519_ASM"
)
set(NODE_PORT_V8_NCRYPTO_DEFINES_LINUX
  "__STDC_FORMAT_MACROS"
  "OPENSSL_USE_NODELETE"
  "L_ENDIAN"
  "AES_ASM"
  "CMLL_ASM"
  "GHASH_ASM"
  "OPENSSL_BN_ASM_GF2m"
  "OPENSSL_BN_ASM_MONT5"
  "OPENSSL_IA32_SSE2"
  "PADLOCK_ASM"
  "RC4_ASM"
  "WHIRLPOOL_ASM"
  "X25519_ASM"
)
set(NODE_PORT_V8_NCRYPTO_DEFINES_MAC
  "_DARWIN_USE_64_BIT_INODE=1"
  "L_ENDIAN"
  "ECP_SM2P256_ASM"
  "OPENSSL_SM3_ASM"
  "SM4_ASM"
  "VPSM4_ASM"
)

set(NODE_PORT_V8_NCRYPTO_INCLUDE_DIRS
  ${NODE_ROOT}/deps/ncrypto
  ${NODE_ROOT}/deps/openssl/openssl/include
  ${NODE_ROOT}/deps/openssl/openssl/crypto/include
)
set(NODE_PORT_V8_NCRYPTO_INCLUDE_DIRS_WIN
  ${NODE_ROOT}/deps/openssl/config/archs/VC-WIN64A/asm/include
  ${NODE_ROOT}/deps/openssl/config/archs/VC-WIN64A/asm
)
set(NODE_PORT_V8_NCRYPTO_INCLUDE_DIRS_LINUX
  ${NODE_ROOT}/deps/openssl/config/archs/linux-x86_64/asm/include
  ${NODE_ROOT}/deps/openssl/config/archs/linux-x86_64/asm
)
set(NODE_PORT_V8_NCRYPTO_INCLUDE_DIRS_MAC
  ${NODE_ROOT}/deps/openssl/config/archs/darwin64-arm64-cc/asm/include
  ${NODE_ROOT}/deps/openssl/config/archs/darwin64-arm64-cc/asm
)

# gyp 的 `dependencies`（跨平台取并集；按名字去重，调用方自己映射）
set(NODE_PORT_V8_NCRYPTO_DEPS
  ncrypto_engine
  openssl
)

set(NODE_PORT_V8_NCRYPTO_CFLAGS_LINUX
  "-pthread"
  "-Wall"
  "-Wextra"
  "-Wno-unused-parameter"
  "-m64"
  "-O3"
  "-fno-omit-frame-pointer"
)
set(NODE_PORT_V8_NCRYPTO_CFLAGS_MAC
  "-O3"
)
set(NODE_PORT_V8_NCRYPTO_CFLAGS_CC_LINUX
  "-fno-rtti"
  "-fno-exceptions"
  "-fno-strict-aliasing"
  "-std=gnu++20"
)
set(NODE_PORT_V8_NCRYPTO_LDFLAGS_LINUX
  "-pthread"
  "-rdynamic"
  "-m64"
)

set(NODE_PORT_V8_NCRYPTO_EXCEPTIONS FALSE)
# gyp 的 msvs_disabled_warnings（禁 7 个警告，不传就全刷屏）
set(NODE_PORT_V8_NCRYPTO_MSVS_DISABLED_WARNINGS
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
set(NODE_PORT_V8_NCRYPTO_MSVS_FLAGS
  "/Zc:__cplusplus"
  "/Zm2000"
  "/W3"
  "/GR-"
  "/EHs-c-"
)

