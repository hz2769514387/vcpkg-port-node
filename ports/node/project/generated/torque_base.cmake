# 由 gyp2vcpkg 生成 —— 不要手改，改了会被判为过期。
#   生成命令：python ../gyp2vcpkg/gyp2vcpkg.py all --config ../gyp2vcpkg/config.json
#   指纹    ：../gyp2vcpkg/resolve.py 34eb26e83830e71f
#             ../gyp2vcpkg/collect.py 69a202ae8e388ee3
#             ../gyp2vcpkg/generate.py b91b0bec8bc781f3
#             ../gyp2vcpkg/_dump_generator.py d3fe1a95334e65ee
#             ../gyp2vcpkg/config.json 4304a096a04026f7
#             ../gyp2vcpkg/env/win-x64.json 2ac8390bd45101df
#             ../gyp2vcpkg/env/linux-x64.json a37e3877ca8397b2
#   蓝本    ：node-v24.21.0/tools/v8_gypfiles/v8.gyp（目标 torque_base，gyp 里的类型 static_library）
#   编译单元：win 24 / linux 24（另外 win 30、linux 30 个是头文件）

set(NODE_PORT_V8_TORQUE_BASE_IS_INTERFACE FALSE)
set(NODE_PORT_V8_TORQUE_BASE_IS_EXECUTABLE FALSE)

set(NODE_PORT_V8_TORQUE_BASE_SOURCES_WIN
  ${NODE_PORT_V8_ROOT}/src/torque/cc-generator.cc
  ${NODE_PORT_V8_ROOT}/src/torque/cfg.cc
  ${NODE_PORT_V8_ROOT}/src/torque/class-debug-reader-generator.cc
  ${NODE_PORT_V8_ROOT}/src/torque/cpp-builder.cc
  ${NODE_PORT_V8_ROOT}/src/torque/csa-generator.cc
  ${NODE_PORT_V8_ROOT}/src/torque/declarable.cc
  ${NODE_PORT_V8_ROOT}/src/torque/declaration-visitor.cc
  ${NODE_PORT_V8_ROOT}/src/torque/declarations.cc
  ${NODE_PORT_V8_ROOT}/src/torque/earley-parser.cc
  ${NODE_PORT_V8_ROOT}/src/torque/global-context.cc
  ${NODE_PORT_V8_ROOT}/src/torque/implementation-visitor.cc
  ${NODE_PORT_V8_ROOT}/src/torque/instance-type-generator.cc
  ${NODE_PORT_V8_ROOT}/src/torque/instructions.cc
  ${NODE_PORT_V8_ROOT}/src/torque/kythe-data.cc
  ${NODE_PORT_V8_ROOT}/src/torque/server-data.cc
  ${NODE_PORT_V8_ROOT}/src/torque/source-positions.cc
  ${NODE_PORT_V8_ROOT}/src/torque/torque-code-generator.cc
  ${NODE_PORT_V8_ROOT}/src/torque/torque-compiler.cc
  ${NODE_PORT_V8_ROOT}/src/torque/torque-parser.cc
  ${NODE_PORT_V8_ROOT}/src/torque/type-inference.cc
  ${NODE_PORT_V8_ROOT}/src/torque/type-oracle.cc
  ${NODE_PORT_V8_ROOT}/src/torque/type-visitor.cc
  ${NODE_PORT_V8_ROOT}/src/torque/types.cc
  ${NODE_PORT_V8_ROOT}/src/torque/utils.cc
)
set(NODE_PORT_V8_TORQUE_BASE_SOURCES_LINUX
  ${NODE_PORT_V8_ROOT}/src/torque/cc-generator.cc
  ${NODE_PORT_V8_ROOT}/src/torque/cfg.cc
  ${NODE_PORT_V8_ROOT}/src/torque/class-debug-reader-generator.cc
  ${NODE_PORT_V8_ROOT}/src/torque/cpp-builder.cc
  ${NODE_PORT_V8_ROOT}/src/torque/csa-generator.cc
  ${NODE_PORT_V8_ROOT}/src/torque/declarable.cc
  ${NODE_PORT_V8_ROOT}/src/torque/declaration-visitor.cc
  ${NODE_PORT_V8_ROOT}/src/torque/declarations.cc
  ${NODE_PORT_V8_ROOT}/src/torque/earley-parser.cc
  ${NODE_PORT_V8_ROOT}/src/torque/global-context.cc
  ${NODE_PORT_V8_ROOT}/src/torque/implementation-visitor.cc
  ${NODE_PORT_V8_ROOT}/src/torque/instance-type-generator.cc
  ${NODE_PORT_V8_ROOT}/src/torque/instructions.cc
  ${NODE_PORT_V8_ROOT}/src/torque/kythe-data.cc
  ${NODE_PORT_V8_ROOT}/src/torque/server-data.cc
  ${NODE_PORT_V8_ROOT}/src/torque/source-positions.cc
  ${NODE_PORT_V8_ROOT}/src/torque/torque-code-generator.cc
  ${NODE_PORT_V8_ROOT}/src/torque/torque-compiler.cc
  ${NODE_PORT_V8_ROOT}/src/torque/torque-parser.cc
  ${NODE_PORT_V8_ROOT}/src/torque/type-inference.cc
  ${NODE_PORT_V8_ROOT}/src/torque/type-oracle.cc
  ${NODE_PORT_V8_ROOT}/src/torque/type-visitor.cc
  ${NODE_PORT_V8_ROOT}/src/torque/types.cc
  ${NODE_PORT_V8_ROOT}/src/torque/utils.cc
)

set(NODE_PORT_V8_TORQUE_BASE_DEFINES
  "_GLIBCXX_USE_CXX11_ABI=1"
  "_FILE_OFFSET_BITS=64"
  "V8_GYP_BUILD"
  "V8_TYPED_ARRAY_MAX_SIZE_IN_HEAP=64"
  "BUILDING_V8_SHARED"
  "BUILDING_V8_PLATFORM_SHARED"
  "OPENSSL_NO_PINSHARED"
  "OPENSSL_THREADS"
  "V8_TARGET_ARCH_X64"
  "V8_HAVE_TARGET_OS"
  "V8_EMBEDDER_STRING=\"-node.53\""
  "ENABLE_DISASSEMBLER"
  "V8_PROMISE_INTERNAL_FIELD_COUNT=1"
  "V8_SHORT_BUILTIN_CALLS"
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
  "V8_ENABLE_WASM_SIMD256_REVEC"
)
set(NODE_PORT_V8_TORQUE_BASE_DEFINES_WIN
  "WIN32"
  "_CRT_SECURE_NO_DEPRECATE"
  "_CRT_NONSTDC_NO_DEPRECATE"
  "BUILDING_UV_SHARED=1"
  "NOMINMAX"
  "_WIN32_WINNT=0x0A00"
  "_SILENCE_ALL_CXX20_DEPRECATION_WARNINGS"
  "V8_TARGET_OS_WIN"
  "V8_ENABLE_SYSTEM_INSTRUMENTATION"
  "V8_ENABLE_ETW_STACK_WALKING"
)
set(NODE_PORT_V8_TORQUE_BASE_DEFINES_LINUX
  "__STDC_FORMAT_MACROS"
  "V8_TARGET_OS_LINUX"
  "ENABLE_GDB_JIT_INTERFACE"
  "V8_ENABLE_PRIVATE_MAPPING_FORK_OPTIMIZATION"
)

set(NODE_PORT_V8_TORQUE_BASE_INCLUDE_DIRS
  ${NODE_PORT_V8_ROOT}
  ${NODE_PORT_V8_ROOT}/include
  ${NODE_PORT_V8_ROOT}/third_party/abseil-cpp
)
set(NODE_PORT_V8_TORQUE_BASE_INCLUDE_DIRS_WIN
)
set(NODE_PORT_V8_TORQUE_BASE_INCLUDE_DIRS_LINUX
)

# gyp 的 `dependencies`（跨平台取并集；按名字去重，调用方自己映射）
set(NODE_PORT_V8_TORQUE_BASE_DEPS
  abseil
  v8_libbase
  v8_shared_internal_headers
)

set(NODE_PORT_V8_TORQUE_BASE_CFLAGS_LINUX
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
set(NODE_PORT_V8_TORQUE_BASE_CFLAGS_CC_LINUX
  "-fno-rtti"
  "-fno-strict-aliasing"
  "-std=gnu++20"
  "-Wno-invalid-offsetof"
  "-fexceptions"
)
set(NODE_PORT_V8_TORQUE_BASE_LDFLAGS_LINUX
  "-pthread"
  "-rdynamic"
  "-m64"
)

# gyp 把这个目标的异常/RTTI 又打开了（msvs ExceptionHandling:1 / cflags_cc -fexceptions /
# xcode GCC_ENABLE_CPP_EXCEPTIONS）—— 全工程默认是关的，要显式开回去
set(NODE_PORT_V8_TORQUE_BASE_EXCEPTIONS TRUE)
# gyp 的 msvs_disabled_warnings（禁 21 个警告，不传就全刷屏）
set(NODE_PORT_V8_TORQUE_BASE_MSVS_DISABLED_WARNINGS
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
set(NODE_PORT_V8_TORQUE_BASE_MSVS_FLAGS
  "/utf-8"
  "-Wno-invalid-offsetof"
  "-Wno-nullability-completeness"
  "/bigobj"
  "/Zc:__cplusplus"
  "/Zm2000"
  "/W3"
  "/GR-"
  "/EHsc"
)
# 只写在 msvs_settings.VCLinkerTool.AdditionalDependencies 里的系统库
set(NODE_PORT_V8_TORQUE_BASE_LINK_LIBS_WIN
  dbghelp.lib
  winmm.lib
  ws2_32.lib
  advapi32.lib
)

