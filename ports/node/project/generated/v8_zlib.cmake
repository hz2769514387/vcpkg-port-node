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
#   蓝本    ：node-v24.21.0/tools/v8_gypfiles/v8.gyp（目标 v8_zlib，gyp 里的类型 static_library）
#   编译单元：win 17 / linux 17 / mac 17（另外 win 15、linux 15、mac 15 个是头文件）

set(NODE_PORT_V8_V8_ZLIB_IS_INTERFACE FALSE)
set(NODE_PORT_V8_V8_ZLIB_IS_EXECUTABLE FALSE)

set(NODE_PORT_V8_V8_ZLIB_SOURCES_WIN
  ${NODE_PORT_V8_ROOT}/third_party/zlib/adler32.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/compress.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/cpu_features.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/crc32.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/deflate.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/gzclose.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/gzlib.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/gzread.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/gzwrite.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/infback.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/inffast.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/inflate.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/inftrees.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/trees.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/uncompr.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/zutil.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/google/compression_utils_portable.cc
)
set(NODE_PORT_V8_V8_ZLIB_SOURCES_LINUX
  ${NODE_PORT_V8_ROOT}/third_party/zlib/adler32.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/compress.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/cpu_features.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/crc32.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/deflate.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/gzclose.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/gzlib.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/gzread.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/gzwrite.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/infback.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/inffast.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/inflate.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/inftrees.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/trees.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/uncompr.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/zutil.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/google/compression_utils_portable.cc
)
set(NODE_PORT_V8_V8_ZLIB_SOURCES_MAC
  ${NODE_PORT_V8_ROOT}/third_party/zlib/adler32.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/compress.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/cpu_features.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/crc32.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/deflate.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/gzclose.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/gzlib.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/gzread.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/gzwrite.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/infback.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/inffast.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/inflate.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/inftrees.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/trees.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/uncompr.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/zutil.c
  ${NODE_PORT_V8_ROOT}/third_party/zlib/google/compression_utils_portable.cc
)

set(NODE_PORT_V8_V8_ZLIB_DEFINES
  "_GLIBCXX_USE_CXX11_ABI=1"
  "_FILE_OFFSET_BITS=64"
  "V8_GYP_BUILD"
  "V8_TYPED_ARRAY_MAX_SIZE_IN_HEAP=64"
  "BUILDING_V8_SHARED"
  "BUILDING_V8_PLATFORM_SHARED"
  "OPENSSL_NO_PINSHARED"
  "OPENSSL_THREADS"
  "V8_HAVE_TARGET_OS"
  "V8_EMBEDDER_STRING=\"-node.53\""
  "ENABLE_DISASSEMBLER"
  "V8_PROMISE_INTERNAL_FIELD_COUNT=1"
  "OBJECT_PRINT"
  "V8_INTL_SUPPORT"
  "V8_ATOMIC_OBJECT_FIELD_WRITES"
  "V8_ENABLE_LAZY_SOURCE_POSITIONS"
  "V8_USE_SIPHASH"
  "V8_ENABLE_SEEDED_ARRAY_INDEX_HASH"
  "NDEBUG"
  "V8_WIN64_UNWINDING_INFO"
  "V8_ENABLE_REGEXP_INTERPRETER_THREADED_DISPATCH"
  "V8_USE_ZLIB"
  "V8_ENABLE_LEAPTIERING"
  "V8_ENABLE_SPARKPLUG"
  "V8_ENABLE_MAGLEV"
  "V8_ENABLE_TURBOFAN"
  "V8_ENABLE_WEBASSEMBLY"
  "V8_ENABLE_JAVASCRIPT_PROMISE_HOOKS"
  "V8_ENABLE_CONTINUATION_PRESERVED_EMBEDDER_DATA"
  "V8_ALLOCATION_FOLDING"
  "V8_ALLOCATION_SITE_TRACKING"
  "V8_ADVANCED_BIGINT_ALGORITHMS"
  "ZLIB_IMPLEMENTATION"
)
set(NODE_PORT_V8_V8_ZLIB_DEFINES_WIN
  "WIN32"
  "_CRT_SECURE_NO_DEPRECATE"
  "_CRT_NONSTDC_NO_DEPRECATE"
  "_HAS_EXCEPTIONS=0"
  "BUILDING_V8_SHARED=1"
  "BUILDING_UV_SHARED=1"
  "NOMINMAX"
  "V8_TARGET_ARCH_X64"
  "_WIN32_WINNT=0x0A00"
  "_SILENCE_ALL_CXX20_DEPRECATION_WARNINGS"
  "V8_TARGET_OS_WIN"
  "V8_SHORT_BUILTIN_CALLS"
  "V8_ENABLE_SYSTEM_INSTRUMENTATION"
  "V8_ENABLE_ETW_STACK_WALKING"
  "V8_ENABLE_WASM_SIMD256_REVEC"
  "X86_WINDOWS"
)
set(NODE_PORT_V8_V8_ZLIB_DEFINES_LINUX
  "__STDC_FORMAT_MACROS"
  "V8_TARGET_ARCH_X64"
  "V8_TARGET_OS_LINUX"
  "ENABLE_GDB_JIT_INTERFACE"
  "V8_ENABLE_PRIVATE_MAPPING_FORK_OPTIMIZATION"
  "V8_SHORT_BUILTIN_CALLS"
  "V8_ENABLE_WASM_SIMD256_REVEC"
)
set(NODE_PORT_V8_V8_ZLIB_DEFINES_MAC
  "_DARWIN_USE_64_BIT_INODE=1"
  "V8_TARGET_ARCH_ARM64"
  "V8_TARGET_OS_MACOS"
  "V8_ENABLE_SYSTEM_INSTRUMENTATION"
)

set(NODE_PORT_V8_V8_ZLIB_INCLUDE_DIRS
  ${NODE_PORT_V8_ROOT}
  ${NODE_PORT_V8_ROOT}/include
  ${NODE_PORT_V8_ROOT}/third_party/zlib
  ${NODE_PORT_V8_ROOT}/third_party/zlib/google
)
set(NODE_PORT_V8_V8_ZLIB_INCLUDE_DIRS_WIN
)
set(NODE_PORT_V8_V8_ZLIB_INCLUDE_DIRS_LINUX
)
set(NODE_PORT_V8_V8_ZLIB_INCLUDE_DIRS_MAC
)

set(NODE_PORT_V8_V8_ZLIB_CFLAGS_LINUX
  "-fvisibility=hidden"
  "-fvisibility-inlines-hidden"
  "-pthread"
  "-Wno-unused-parameter"
  "-Wno-strict-overflow"
  "-Wno-return-type"
  "-Wno-int-in-bool-context"
  "-Wno-deprecated"
  "-Wno-stringop-overflow"
  "-Wno-stringop-overread"
  "-Wno-restrict"
  "-Wno-array-bounds"
  "-Wno-nonnull"
  "-Wno-dangling-pointer"
  "-flax-vector-conversions"
  "-m64"
  "-O3"
  "-fno-omit-frame-pointer"
  "-fdata-sections"
  "-ffunction-sections"
  "-O3"
)
set(NODE_PORT_V8_V8_ZLIB_CFLAGS_MAC
  "-O3"
)
set(NODE_PORT_V8_V8_ZLIB_CFLAGS_CC_LINUX
  "-fno-rtti"
  "-fno-exceptions"
  "-fno-strict-aliasing"
  "-std=gnu++20"
  "-Wno-invalid-offsetof"
)
set(NODE_PORT_V8_V8_ZLIB_CFLAGS_CC_MAC
  "-Wno-invalid-offsetof"
  "-Wno-nullability-completeness"
)
set(NODE_PORT_V8_V8_ZLIB_LDFLAGS_LINUX
  "-pthread"
  "-rdynamic"
  "-m64"
)

set(NODE_PORT_V8_V8_ZLIB_EXCEPTIONS FALSE)
# gyp 的 msvs_disabled_warnings（禁 21 个警告，不传就全刷屏）
set(NODE_PORT_V8_V8_ZLIB_MSVS_DISABLED_WARNINGS
  /wd4351
  /wd4355
  /wd4800
  /wd4251
  /wd4275
  /wd4244
  /wd4267
  /wd4129
  /wd4245
  /wd4324
  /wd4506
  /wd4661
  /wd4701
  /wd4702
  /wd4703
  /wd4709
  /wd4714
  /wd4715
  /wd4718
  /wd4723
  /wd4724
)
# msvs_settings.VCCLCompilerTool：AdditionalOptions + WarningLevel /
# RuntimeTypeInfo / ExceptionHandling 翻出来的开关（Windows 专用）
set(NODE_PORT_V8_V8_ZLIB_MSVS_FLAGS
  "/utf-8"
  "-Wno-invalid-offsetof"
  "-Wno-nullability-completeness"
  "/bigobj"
  "/Zc:__cplusplus"
  "/Zm2000"
  "/W3"
  "/GR-"
  "/EHs-c-"
)

