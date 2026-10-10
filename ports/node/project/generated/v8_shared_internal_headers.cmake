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
#   蓝本    ：node-v24.21.0/tools/v8_gypfiles/v8.gyp（目标 v8_shared_internal_headers，gyp 里的类型 none）
#   编译单元：win 0 / linux 0 / mac 0（另外 win 55、linux 55、mac 55 个是头文件）

set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_IS_INTERFACE TRUE)
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_IS_EXECUTABLE FALSE)

set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_SOURCES_WIN
)
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_SOURCES_LINUX
)
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_SOURCES_MAC
)

set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_DEFINES
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
)
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_DEFINES_WIN
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
)
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_DEFINES_LINUX
  "__STDC_FORMAT_MACROS"
  "V8_TARGET_ARCH_X64"
  "V8_TARGET_OS_LINUX"
  "ENABLE_GDB_JIT_INTERFACE"
  "V8_ENABLE_PRIVATE_MAPPING_FORK_OPTIMIZATION"
  "V8_SHORT_BUILTIN_CALLS"
  "V8_ENABLE_WASM_SIMD256_REVEC"
)
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_DEFINES_MAC
  "_DARWIN_USE_64_BIT_INODE=1"
  "V8_TARGET_ARCH_ARM64"
  "V8_TARGET_OS_MACOS"
  "V8_ENABLE_SYSTEM_INSTRUMENTATION"
)

set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_INCLUDE_DIRS
  ${NODE_PORT_V8_ROOT}
  ${NODE_PORT_V8_ROOT}/include
)
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_INCLUDE_DIRS_WIN
)
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_INCLUDE_DIRS_LINUX
)
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_INCLUDE_DIRS_MAC
)

# gyp 的 `dependencies`（跨平台取并集；按名字去重，调用方自己映射）
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_DEPS
  v8_headers
  v8_libbase
)

set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_CFLAGS_LINUX
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
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_CFLAGS_MAC
  "-O3"
)
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_CFLAGS_CC_LINUX
  "-fno-rtti"
  "-fno-exceptions"
  "-fno-strict-aliasing"
  "-std=gnu++20"
  "-Wno-invalid-offsetof"
)
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_CFLAGS_CC_MAC
  "-Wno-invalid-offsetof"
  "-Wno-nullability-completeness"
)
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_LDFLAGS_LINUX
  "-pthread"
  "-rdynamic"
  "-m64"
)
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_LDFLAGS_MAC
  "-Wl,-search_paths_first"
)

set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_EXCEPTIONS FALSE)
# gyp 的 msvs_disabled_warnings（禁 21 个警告，不传就全刷屏）
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_MSVS_DISABLED_WARNINGS
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
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_MSVS_FLAGS
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
# 只写在 msvs_settings.VCLinkerTool.AdditionalDependencies 里的系统库
set(NODE_PORT_V8_V8_SHARED_INTERNAL_HEADERS_LINK_LIBS_WIN
  dbghelp.lib
  winmm.lib
  ws2_32.lib
  advapi32.lib
)

