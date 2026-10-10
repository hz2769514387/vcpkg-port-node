# V8 的 CMake 目标（`9.0-P-4`）。
#
# 这里**不写任何清单**：源文件、宏、include 目录、编译/链接标志都在
# `cmake/gyp2vcpkg/generated/<目标>.cmake` 里，由 **deps/gyp2vcpkg**
# （`--config tools/bootstrap/config.json` + 各平台 `--env`）从 node 自带的 gyp 实测解析而来
# （每个平台各跑一次，因为 win 与 linux 求出来的集合不一样）。
# 理由：v8.gyp 的 sources 大半是 `<!@pymod_do_main(GN-scraper ...)`（从 BUILD.gn 现场抓），
# 手抄一份就等于自己发明事实 —— 而且发明错了编译期才会发现。
# gyp2vcpkg 只 `set()` 变量（不产 add_library），怎么变成目标是本文件的事。

set(NODE_PORT_V8_ROOT "${NODE_ROOT}/deps/v8" CACHE INTERNAL "V8 源码根（src/node 等兄弟目录也要用）")

# 生成物统一放这里（gyp 的 SHARED_INTERMEDIATE_DIR）。
# 注意它是 **torque-generated 的上一级**：源码里写的是 `#include "torque-generated/xxx.h"`。
# 用 CACHE INTERNAL：src/node 等**兄弟目录**也要用它（普通 set 只在定义目录
# 及其子目录可见，兄弟目录里会展开成空串 —— 实测 ninja 报 '/node_protocol.pdl'）。
set(NODE_PORT_V8_GENERATED "${CMAKE_BINARY_DIR}/generated/v8" CACHE INTERNAL "V8 与其兄弟目标的中间产物根目录")
file(MAKE_DIRECTORY "${NODE_PORT_V8_GENERATED}")

# 本文件只做两件事：**建哪些目标**、以及那些目标各自的**额外动作**（并生成源、
# 汇编语言、快照链…）。"清单 → 目标"的通用逻辑在 `cmake/gyp2vcpkg/consume.cmake`
# （`node_port_add_v8_target` / `node_port_add_v8_action` / `node_port_lang_opts`），顶层已 include。

# ---- 目标 -----------------------------------------------------------------
# 清单由 deps/gyp2vcpkg 从 gyp 实测展开（禁手抄）；
# 每个目标的取舍依据见各自行内注释与 `9.0-P-4` 的子任务文件。

# abseil 走 **node 自带的那份**（`调研-8`：它已打过 3 个补丁，vcpkg 那份不是一回事），
# 从 deps/v8/third_party/abseil-cpp 编。V8 的 src/base/platform/mutex.h 直接 include
# `absl/synchronization/mutex.h` —— 没有它 v8_libbase 连编译都过不去。
node_port_add_v8_target(abseil)

node_port_add_v8_target(v8_headers)
node_port_add_v8_target(v8_shared_internal_headers)
node_port_add_v8_target(v8_libbase)
node_port_add_v8_target(v8_libplatform)
# torque.exe：把 .tq 翻成 C++ 的构建期工具（gyp 里 `toolsets:['host']` 那一套）。
# torque_base 是**编进产物**的运行时支撑库，跟它不是一个东西 —— 两个都建。
node_port_add_v8_target(torque_base)
node_port_add_v8_target(torque)
node_port_add_v8_target(bytecode_builtins_list_generator)
# gen-regexp-special-case 也编出来：run_gen-regexp-special-case 要跑它
# （它依赖 v8_maybe_icu —— 那个目标在 gyp 里是 'none'，只有 include 目录和宏）
node_port_add_v8_target(v8_maybe_icu)
node_port_add_v8_target(gen-regexp-special-case)

# ---- v8_base_without_compiler 的依赖链（v8.gyp:1064-1084 逐条对上）----------
# 一大批 'none' 目标：它们自己不编（或把源并进依赖方），只下发 include / 宏 / 源文件。
node_port_add_v8_target(torque_generated_definitions)   # v8.gyp:208，3 个源并进依赖方
node_port_add_v8_target(v8_bigint)                      # v8.gyp:2015，13 个源并进依赖方
node_port_add_v8_target(v8_heap_base)                   # v8.gyp:2032
node_port_add_v8_target(v8_inspector_headers)           # v8.gyp:1009，inspector 生成物的 include
node_port_add_v8_target(v8_version)                     # v8.gyp:558
node_port_add_v8_target(cppgc_base)                     # v8.gyp:2005，46 个源并进依赖方
node_port_add_v8_target(v8_internal_headers)            # v8.gyp:632
node_port_add_v8_target(v8_pch)                         # v8.gyp:79
node_port_add_v8_target(fp16)                           # v8.gyp:2360，只有 include
# 这两个是真静态库（V8 自带的 chromium 版 zlib / highway，**不是 vcpkg 那份**）
node_port_add_v8_target(v8_zlib)                        # v8.gyp:2298
node_port_add_v8_target(highway)                        # v8.gyp:2373

target_link_libraries(v8_libbase PUBLIC v8_headers abseil)
target_link_libraries(v8_libplatform PUBLIC v8_libbase)
target_link_libraries(torque_base PUBLIC v8_libbase v8_shared_internal_headers abseil)
target_link_libraries(torque PRIVATE torque_base abseil)
target_link_libraries(bytecode_builtins_list_generator PRIVATE v8_libbase abseil)
target_link_libraries(gen-regexp-special-case PRIVATE v8_libbase v8_maybe_icu abseil)

# ICU 走 **vcpkg 的**（`调研-1`：官方包是 full ICU 78.3，vcpkg port 78.3 一致）。
# gyp 里 v8_maybe_icu 依赖 icui18n/icuuc（并 export_dependent_settings 给依赖方），
# 对应 CMake 就是这三个组件 —— INTERFACE 库把 include 和库一起传给依赖方。
# 之前漏了它：gen-regexp-special-case 编译报 `unicode/uchar.h not found`。
find_package(ICU REQUIRED COMPONENTS data i18n uc)
target_link_libraries(v8_maybe_icu INTERFACE ICU::data ICU::i18n ICU::uc)

# simdutf **不走 vcpkg**（`调研-1` 标 ⚠⚠：node/V8 用 6.4.0，port 8.2.0 大版本
# 超前）。实测 V8 的 6.4.0 头（`deps/v8/third_party/simdutf/simdutf.h`）声明了
# `base64_to_binary_safe(..., last_chunk_handling_options)`，vcpkg 8.2.0 的库
# 里没有对应 mangled 符号 —— mksnapshot 链接 undefined。gyp 里 simdutf 就是
# V8 自带的单文件 static_library（v8.gyp:2423，simdutf.cpp），照抄。
# 工程约定第 7 条的例外：port 版本 API 不兼容是刚性阻碍，记录在案。
node_port_add_v8_target(simdutf)

# 汇编：v8_heap_base 的 push_registers_masm.asm（Windows x64 照 gyp 用 MASM，
# v8.gyp:2050 注释 —— V8 v12.8 起 clang-cl 也要走 masm）。没有对应语言的
# 生成器会**静默跳过** .asm 文件（无警告、无规则），链接期才炸 undefined
# PushAllRegistersAndIterateStack。Linux 侧 embedded.S 用普通 ASM。
if(WIN32)
  enable_language(ASM_MASM)
else()
  enable_language(ASM)
endif()

# ---- 代码生成动作 ---------------------------------------------------------
#
# 三个动作都是同一套做法，所以做成函数：读 generated/<动作>_action.cmake 里那批变量
# （工具、命令行、输入、输出、要建的目录），挂成 add_custom_command。
#
# 两件 CMake 侧必须自己补的事：
#   1. **先建目录**：工具写文件走的是 utils.cc:327 的 ReplaceFileContentsIfDifferent，
#      直接 ofstream.open —— 目录不存在就**静默不写**（torque 那次实测只出 20 个聚合文件）。
#      官方靠 ninja 给声明过的 outputs 建目录，这里显式建一遍，不依赖生成器行为。
#   2. **声明全部输出**：不声明的话增量构建不知道该重跑。
#      曾经把路径拼错一层（声明在 torque-generated/torque-generated/ 下），
#      ninja 老老实实建了个空目录、文件却在上一层 —— **声明的路径必须和真写出的对得上**。
#
# python：run.py 那两个动作要它 —— 按 `调研-4` 的口径，python 是**已承认的构建前置**。
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# 245 个 .tq → 1245 个生成物（torque 已编好）
node_port_add_v8_action(run_torque)
# 目标名沿用 gyp 的：这两个动作的产物分别是 bytecodes-builtins-list.h 与 special-case.cc
node_port_add_v8_action(generate_bytecode_builtins_list)
node_port_add_v8_action(run_gen-regexp-special-case)
# inspector 协议链（v8_inspector_headers 里两个动作；产物是 17 个协议源 + 1 个 stamp）。
# 注意动作名带宿主目标前缀 —— 同一目标里有两个动作，靠 `目标:动作` 区分。
node_port_add_v8_action(protocol_compatibility)
node_port_add_v8_action(protocol_generated_sources)

# ---- v8_base_without_compiler（v8.gyp:1061，V8 的大头）----------------------
# 依赖见 v8.gyp:1064-1084：一批 'none' 目标（源文件经 direct_dependent_settings
# 并进这里编）+ v8_zlib / highway / abseil 三个静态库 + 上面四个代码生成动作
# （sources 里有 bytecodes-builtins-list.h、torque 生成的头、inspector 协议源 ——
# 必须先跑动作，文件才存在）。
node_port_add_v8_target(v8_base_without_compiler)
target_link_libraries(v8_base_without_compiler PRIVATE
  torque_generated_definitions
  v8_bigint
  v8_headers
  v8_heap_base
  v8_inspector_headers
  v8_libbase
  v8_shared_internal_headers
  v8_version
  cppgc_base
  v8_internal_headers
  v8_maybe_icu
  v8_zlib
  v8_pch
  fp16
  highway
  abseil)
add_dependencies(v8_base_without_compiler
  run_torque
  generate_bytecode_builtins_list
  protocol_compatibility
  protocol_generated_sources)
target_link_libraries(v8_base_without_compiler PUBLIC simdutf)

# ---- mksnapshot 编译侧（v8.gyp:276-534 的链）--------------------------------
# torque_runtime_support：runtime-support.h 经 direct_dependent_settings 并进依赖方
node_port_add_v8_target(torque_runtime_support)
# torque_generated_initializers：csa-types.h / enum-verifiers.cc 等生成物并进依赖方
node_port_add_v8_target(torque_generated_initializers)
# wasm→js 桥的 4 个 torque 生成文件单独 -O1 编（GCC 慢的 workaround，v8.gyp:296 注释）
node_port_add_v8_target(v8_initializers_slow)
# builtins-x64.cc 等 49 个初始化源
node_port_add_v8_target(v8_initializers)
# setup-isolate-full.cc：mksnapshot 侧要"完整"初始化
node_port_add_v8_target(v8_init)
# v8_compiler_for_mksnapshot：0 源的中转 —— 按 v8_enable_turbofan==1（官方包实测）
# 走 else 分支，最终由 v8_compiler 那 181 个 compiler 源承担编译
# （gyp 里这些源是 v8_compiler_sources 的 direct_dependent_settings，真 gyp 解析
#  之后它们**并进了 v8_compiler 自己** —— 所以现在取 v8_compiler 的源，不再取
#  v8_compiler_sources 那份：它已经是空的了）。
# **不能**把 INTERFACE 中转目标放进 mksnapshot 的 PRIVATE 链接：PRIVATE 链接
# INTERFACE 库会以 $<LINK_ONLY> 把名字透传给链接器（lld-link: could not open
# 'v8_compiler_sources.lib'，实测）。源的并进改用 target_sources 直取清单变量
# —— 顶层 include 让清单变量进目录作用域（node_port_add_v8_target 里的 include 只在
# 函数作用域可见）。
node_port_add_v8_target(v8_compiler_for_mksnapshot)
# mksnapshot.exe 本体（11 个源）—— 先有目标，才能往里并 compiler 源
node_port_add_v8_target(mksnapshot)
include("${NODE_PORT_GYP2VCPKG_DIR}/generated/v8_compiler.cmake")
# 平台分支写全三个：`if(WIN32) … else` 会把 macOS 静默归进 Linux 分支。
if(WIN32)
  target_sources(mksnapshot PRIVATE ${NODE_PORT_V8_V8_COMPILER_SOURCES_WIN})
elseif(APPLE)
  target_sources(mksnapshot PRIVATE ${NODE_PORT_V8_V8_COMPILER_SOURCES_MAC})
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  target_sources(mksnapshot PRIVATE ${NODE_PORT_V8_V8_COMPILER_SOURCES_LINUX})
else()
  # 走到这里说明 node_port_add_v8_target 那道 FATAL_ERROR 被绕过了 —— 不许静默拿别平台的源。
  message(FATAL_ERROR
    "mksnapshot：${CMAKE_SYSTEM_NAME} 还没有 compiler 源清单（见本文件 node_port_add_v8_target 的说明）")
endif()

target_link_libraries(v8_initializers_slow PRIVATE v8_base_without_compiler v8_shared_internal_headers v8_maybe_icu fp16 abseil)
target_link_libraries(v8_initializers PRIVATE v8_base_without_compiler v8_shared_internal_headers v8_pch fp16 v8_maybe_icu abseil torque_generated_initializers
  # v8.gyp:344 —— `v8_initializers` 在 wasm 打开时**依赖 `v8_initializers_slow`**。
  # 旧清单里那 4 个 slow 源同时也在 `torque_generated_initializers`（INTERFACE，源并进
  # 依赖方），所以"并进 v8_initializers"就够了；换成真 gyp 解析之后它们**只**在
  # `v8_initializers_slow` 里 —— 不显式链进来，mksnapshot 链接期就报 7 个 undefined
  # （`Builtins::Generate_JSToWasmWrapper`、`WasmToJSWrapper_0`… 都是 wasm 那几个文件
  # 里的，实测）。
  v8_initializers_slow)
target_link_libraries(v8_init PRIVATE v8_base_without_compiler v8_initializers v8_maybe_icu fp16 abseil)
target_link_libraries(mksnapshot PRIVATE
  v8_base_without_compiler
  v8_init
  v8_libbase
  v8_libplatform
  v8_maybe_icu
  v8_pch
  fp16
  abseil)
add_dependencies(mksnapshot run_torque generate_bytecode_builtins_list)

# mksnapshot 的 --target_os 决定 embedded.S 的汇编格式（Win writer 写 COFF、
# linux 走 Generic/ELF）—— 它必须跟随**生成快照的平台**，不能拿 win 展开值
# 写死到 linux 命令行（实测：linux 拿到 --target_os=win 生成 COFF 格式 .S，
# GAS 报 bad .section directive）。
#
# 注意：必须**定义在下面 node_port_add_v8_action(run_mksnapshot) 之前** —— 片段里的
# ${NODE_PORT_TARGET_OS} 是在创建自定义命令时展开的；后定义就等于空串，mksnapshot 会
# 落回 Generic writer，Windows 上产出 ELF 风格 embedded.cc（`.hidden` 指令），
# clang-cl 直接报 unknown directive（实测踩到）。
if(WIN32)
  set(NODE_PORT_TARGET_OS win)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  set(NODE_PORT_TARGET_OS linux)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  set(NODE_PORT_TARGET_OS mac)
endif()

node_port_add_v8_action(run_mksnapshot)

# v8_compiler：compiler 的 181 个源做成**真静态库** ——
# node 主体要用编译器的实现（v8::ScriptCompiler 等），只链头 INTERFACE 会
# 大面积未定义符号（实测：undefined symbol v8::StackFrame::GetLocation 起头）。
# mksnapshot 那边保持把源直接并进自己（已经跑通，不动）。
#
# 源不再取自 `v8_compiler_sources`：那个 gyp 目标是 `none` + direct_dependent_settings，
# 真 gyp 解析之后它的源**并进了 v8_compiler**（清单里 v8_compiler_sources 已经 0 源）。
#
# **走通用路径 `node_port_add_v8_target`，不再手写 `add_library`**：手写那版只补了源/宏/include，
# **没补 gyp 的编译选项**，Linux 上就炸了 —— `pipeline.cc` 少了 `-fno-rtti`
# （同族的 v8_base_without_compiler 有），于是它引用
# `typeinfo for v8::internal::AssemblerBase`，而那个 typeinfo 在 `-fno-rtti` 下压根不生成：
#     ld: libv8_compiler.a(pipeline.cc.o): undefined reference to `typeinfo for v8::internal::AssemblerBase'
# Windows 上看不出来（MSVC 不靠 typeinfo 做这件事），所以是 Linux 侧编译才暴露的。
node_port_add_v8_target(v8_compiler)
target_link_libraries(v8_compiler PUBLIC v8_base_without_compiler v8_shared_internal_headers
  v8_maybe_icu fp16 abseil v8_libbase)

# postmortem-metadata 的动作（v8.gyp:2276）：python 脚本吃 82 个头文件、
# 产出 debug-support.cc（经 direct_dependent_settings 并进 node 主体，P-5 接）。
# 注意：输出在 GEN 根下、无子目录 —— OUTPUT_DIRS 为空，make_directory 跳过。
node_port_add_v8_action(postmortem-metadata)


# ---- v8_snapshot（v8.gyp:415，snapshot 的载体）------------------------------
# 三个动作串成链：mksnapshot.exe → run_mksnapshot（snapshot.cc + embedded.S）
# → [仅 win+clang] asm_to_inline_asm（embedded.S → embedded.cc，inline asm 的 C++，
#    v8.gyp:532-552 —— Windows 侧因此**不需要汇编器**）。
# v8_snapshot 的源 = setup-isolate-deserialize.cc + snapshot.cc + 平台各自的
# embedded 产物（win: embedded.cc / linux: embedded.S），其中生成源是
# `process_outputs_as_sources` 注入的，生成清单里没有 —— 这里手动加。
node_port_add_v8_target(v8_snapshot)
node_port_add_v8_action(asm_to_inline_asm)
add_dependencies(asm_to_inline_asm run_mksnapshot)
add_dependencies(v8_snapshot run_mksnapshot)

# embedded 产物分平台取：Windows 用 asm_to_inline_asm 转出来的 embedded.cc（因此不需要汇编器），
# 另一个 POSIX 平台直接汇编 embedded.S。写全三个分支 —— 没有清单的平台上宁可明确拒绝，
# 也不静默拿别平台的那份顶上（`9.0-V-2`）。
if(WIN32)
  target_sources(v8_snapshot PRIVATE
    "${NODE_PORT_V8_GENERATED}/intermediate/v8_snapshot/snapshot.cc"
    "${NODE_PORT_V8_GENERATED}/intermediate/v8_snapshot/embedded.cc")
  add_dependencies(v8_snapshot asm_to_inline_asm)
elseif(APPLE)
  # macOS 与 Linux 同构：embedded 产物是**汇编**（mksnapshot 按 --target_os=mac 写
  # Mach-O 风格），直接交给汇编器 —— 也不需要 asm_to_inline_asm（那只服务 win+clang）。
  enable_language(ASM)
  target_sources(v8_snapshot PRIVATE
    "${NODE_PORT_V8_GENERATED}/intermediate/v8_snapshot/snapshot.cc"
    "${NODE_PORT_V8_GENERATED}/intermediate/v8_snapshot/embedded.S")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  enable_language(ASM)
  target_sources(v8_snapshot PRIVATE
    "${NODE_PORT_V8_GENERATED}/intermediate/v8_snapshot/snapshot.cc"
    "${NODE_PORT_V8_GENERATED}/intermediate/v8_snapshot/embedded.S")
else()
  message(FATAL_ERROR
    "v8_snapshot：${CMAKE_SYSTEM_NAME} 还没有 embedded 产物（见本文件 node_port_add_v8_target 的说明）")
endif()
# gyp 里这两个 include 来自代码生成动作的 direct_dependent_settings ——
# run_torque 给 SHARED_INTERMEDIATE_DIR（v8.gyp:107-111）、
# generate_bytecode_builtins_list 给 generate_bytecode_output_root（v8.gyp:247-253）。
# custom_target 传不了 usage requirements，这里手动补：
# 源里 `#include "torque-generated/instance-types.h"` 与
# `#include "builtins-generated/bytecodes-builtins-list.h"`。
target_include_directories(v8_snapshot PRIVATE
  ${NODE_PORT_V8_GENERATED}
  ${NODE_PORT_V8_GENERATED}/generate-bytecode-output-root)
target_link_libraries(v8_snapshot PRIVATE v8_libbase v8_maybe_icu abseil)
add_dependencies(v8_snapshot run_torque generate_bytecode_builtins_list)
