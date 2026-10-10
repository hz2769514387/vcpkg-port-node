# gyp2vcpkg 的**消费层**（`9.0-P-26`）：把 `generated/<目标>.cmake` 里的变量变成
# 真正的 CMake 目标 / 自定义命令。
#
# 为什么放在 `cmake/gyp2vcpkg/` 而不是某个 `src/<组件>/CMakeLists.txt` 里：
#
#   * 它是**产品产物的消费侧**（用户原话 2026-10-08 10点11分 第 2 条："把和 gyp2vcpkg
#     相关的都放在 gyp2vcpkg 目录"）—— 配置（config.json / icu-vcpkg.gyp）、产物
#     （generated/）、补丁（NodePortTargetPatch.cmake）、消费层（本文件）四件一套；
#   * 它是**多个工程共用的函数库**：`src/v8`、`src/node`、`src/tools`、`src/vendored`
#     都要调 `node_port_add_v8_target`。写在某一个工程里，别的工程就受 `add_subdirectory`
#     顺序的约束（谁先定义谁后调）—— 抽到这里之后，顶层 include 一次，谁都能调。
#
# 本文件**不建任何目标**（那是各 `src/<组件>/CMakeLists.txt` 的事），只提供：
#
#   node_port_lang_opts(<out> <语言> <选项…>)      给一批选项套 COMPILE_LANGUAGE 限定
#   node_port_add_v8_target(<名字>)                按清单建目标（静态库 / INTERFACE / 可执行）
#   node_port_add_v8_action(<动作> [TARGET <名>])   按清单挂自定义命令（代码生成动作）
#   node_port_drop_bundled_include(<目标> <相对路径…>) 摘掉"node 自带副本"的 include 目录
#   （依赖图的消费还没接：见下面那段说明与 `9.0-P-26`）

# gyp2vcpkg 在本工程侧的落点：消费层 + 产物**都放一起**（本文件所在目录）。
# 用 CACHE INTERNAL：v8 / tools / vendored / node 各目录都要用。
set(NODE_PORT_GYP2VCPKG_DIR "${CMAKE_CURRENT_LIST_DIR}" CACHE INTERNAL "gyp2vcpkg 在本工程侧的落点（消费层 + 产物）")

# 清单目录登记成**全局属性**：function 里的 CMAKE_CURRENT_LIST_DIR 是**调用方**目录，
# 而 node_port_add_v8_target 可能被 src/vendored / src/tools / src/v8 / src/node 任一处调用 ——
# 所以登记在**定义处**（本文件），不是某个工程目录。
set_property(GLOBAL PROPERTY NODE_PORT_V8_GEN_DIR "${NODE_PORT_GYP2VCPKG_DIR}/generated")

# 把一批编译选项逐个包上 `$<$<COMPILE_LANGUAGE:...>:…>` —— 汇编（MASM / GAS）不认
# `-Wno-invalid-offsetof` / `/wdXXXX` 这类参数（A1013 / A4018），不限语言会被静默
# 喂给它，然后报"不认识的指令"。
function(node_port_lang_opts out langs)
  set(_acc "")
  foreach(_o IN LISTS ARGN)
    list(APPEND _acc "$<$<COMPILE_LANGUAGE:${langs}>:${_o}>")
  endforeach()
  set(${out} "${_acc}" PARENT_SCOPE)
endfunction()

# 按生成的变量建一个 V8 目标。
# gyp 的 'none'（头文件集，作用是把设置下发给依赖方）→ CMake 的 INTERFACE 库；
# 'static_library' → 静态库（工程约定第 1 条：静态单 exe，V8 也不编成 DLL）。
#
# 只做"清单 → 目标"，**不接依赖图**：依赖要等所有目标都建出来才接得上
# （清单里的 dep 有前向引用，而且有两处我们自己的偏离要先处理）。
# 这里只把名字记进 `NODE_PORT_V8_PENDING_DEPS` 备查，接法见本文件下面那段与 `9.0-P-26`。
function(node_port_add_v8_target name)
  string(TOUPPER "${name}" U)
  get_property(_gen GLOBAL PROPERTY NODE_PORT_V8_GEN_DIR)
  set(_f "${_gen}/${name}.cmake")
  if(NOT EXISTS "${_f}")
    message(FATAL_ERROR
      "缺 ${name} 的生成清单：${_f}\n"
      "用这条命令生成（输入在同级 ../gyp2vcpkg/，产物出到 ${_gen}）：\n"
      "  python ../gyp2vcpkg/gyp2vcpkg.py all --config ../gyp2vcpkg/config.json"
      " --node-root \${NODE_ROOT} --env win=../gyp2vcpkg/env/win-x64.json"
      " --env linux=../gyp2vcpkg/env/linux-x64.json")
  endif()
  include("${_f}")

  # 当前平台 → 片段里的变量后缀。macOS 走 `MAC`（整理见 generate.py 的平台后缀口径）。
  if(WIN32)
    set(_plat WIN)
  elseif(APPLE)
    set(_plat MAC)
  elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(_plat LINUX)
  else()
    # 其它平台不是"不支持"，是**还没有那台机器的变量环境** —— 没有环境就不生成清单，
    # 也不拿别的平台那份改个 OS 凑数（那是在发明事实）。
    message(FATAL_ERROR
      "${name}：${CMAKE_SYSTEM_NAME} 还没有对应的 gyp 变量环境，所以没有生成清单。\n"
      "要补的是：在 ${CMAKE_SYSTEM_NAME} 上跑官方二进制导出 process.config，\n"
      "存进 gyp2vcpkg/env/<平台>.json，再把平台加进 gyp2vcpkg/config.json 的 platforms。")
  endif()

  set(_src "${NODE_PORT_V8_${U}_SOURCES_${_plat}}")
  set(_extra_defs "${NODE_PORT_V8_${U}_DEFINES_${_plat}}")
  set(_extra_incs "${NODE_PORT_V8_${U}_INCLUDE_DIRS_${_plat}}")

  if(NODE_PORT_V8_${U}_IS_INTERFACE)
    add_library(${name} INTERFACE)
    set(_kw INTERFACE)
    # gyp 的 'none' + sources：源文件**并进依赖方去编**（`direct_dependent_settings`）。
    # CMake 里对应的就是 INTERFACE_SOURCES —— 谁链它，谁就把这些源文件编进自己。
    target_sources(${name} INTERFACE ${_src})
  elseif(NODE_PORT_V8_${U}_IS_EXECUTABLE)
    # 构建期工具（gyp 里的 `toolsets: ['host']`）。不交叉编译，所以就是普通可执行文件。
    add_executable(${name} ${_src})
    set(_kw PRIVATE)
  else()
    add_library(${name} STATIC ${_src})
    set(_kw PUBLIC)
  endif()

  target_compile_definitions(${name} ${_kw} ${NODE_PORT_V8_${U}_DEFINES} ${_extra_defs})
  # 平台专属的 include 目录（openssl 的 arch 目录就是：win 与 linux 各一份，
  # 交集里没有它）—— 旧清单只给了交集，于是 openssl 的头文件是靠"碰巧"找到的。
  target_include_directories(${name} ${_kw} ${NODE_PORT_V8_${U}_INCLUDE_DIRS} ${_extra_incs})

  # ---- 编译选项（**只给自己的编译单元**）---------------------------------
  # INTERFACE 目标（gyp 的 'none'）没有自己的编译单元：它的选项只在"并进依赖方"
  # 时才有意义，而依赖方（v8_base_without_compiler / v8_initializers 那一类）
  # 自己都有完整一份。**所以不给它们设选项** —— 设了会以 INTERFACE 身份排在
  # 依赖方自己选项的**后面**、把它们显式开的开关盖回去：torque 那一摊在 gyp 里是
  # `ExceptionHandling: 1`（我们照抄成 /EHsc），却被 v8_shared_internal_headers
  # 传下来的 /EHs-c- 盖掉，编译报 10 处 "cannot use 'try' with exceptions disabled"（实测）。
  if(NOT NODE_PORT_V8_${U}_IS_INTERFACE)
    # gyp 的 POSIX 标志（cflags / cflags_cc / ldflags / libraries）。
    # 旧清单漏了这四样，于是 V8 的 `-Wno-unused-parameter` 那一批**全都没生效** ——
    # "V8 未使用变量警告刷屏"就是这么来的（`9.0-T-9` 要治的就是它）。
    if(NOT WIN32)
      if(NODE_PORT_V8_${U}_CFLAGS_${_plat})
        node_port_lang_opts(_cflags "C,CXX" ${NODE_PORT_V8_${U}_CFLAGS_${_plat}})
        target_compile_options(${name} PRIVATE ${_cflags})
      endif()
      if(NODE_PORT_V8_${U}_CFLAGS_CC_${_plat})
        node_port_lang_opts(_cflags_cc "CXX" ${NODE_PORT_V8_${U}_CFLAGS_CC_${_plat}})
        target_compile_options(${name} PRIVATE ${_cflags_cc})
      endif()
    endif()
    if(WIN32 AND NODE_PORT_V8_${U}_MSVS_FLAGS)
      # MSVC/clang 的附加选项逐个包 COMPILE_LANGUAGE 限定 —— MASM 不认
      # -Wno-invalid-offsetof 这类 clang 参数（A1013），不限语言会被静默喂给它。
      node_port_lang_opts(_msvs_genex "C,CXX" ${NODE_PORT_V8_${U}_MSVS_FLAGS})
      target_compile_options(${name} PRIVATE ${_msvs_genex})
    endif()

    # gyp2vcpkg 提取的禁用警告（gyp 的 msvs_disabled_warnings）。
    # V8 禁了 21 个警告（4351/4355/4800/…），不传就全刷屏（`9.0-T-9`）。
    # 用 COMPILE_LANGUAGE 限定 —— MASM 不认 /wdXXXX（A4018）。
    if(WIN32 AND NODE_PORT_V8_${U}_MSVS_DISABLED_WARNINGS)
      node_port_lang_opts(_wd_genex "C,CXX" ${NODE_PORT_V8_${U}_MSVS_DISABLED_WARNINGS})
      target_compile_options(${name} PRIVATE ${_wd_genex})
    endif()

    # clang-cl 适配（**对齐 node 的口径**，不是新发明）：
    # node 的 `cflags`（common.gypi）里写着 `-Wno-unused-parameter` —— 但官方 Windows
    # 构建用 MSVC，那边不认 `-W...`（等于没生效），而 C4100 又只在 /W4 才开。
    # 用 **clang-cl** 时：`-Wunused-parameter` 在 /W3 就开，于是 V8 满屏"未使用的变量"。
    # 把 node 那条口径显式喂进来即可 —— **只喂给 clang 前端**：真正的 cl.exe 不认
    # `-W...`（会报 D9002 未知选项），不该无谓地丢给它。
    #
    # 为什么不干脆把 win 侧的 `cflags` 整份吐出来：那一份里有 `-Werror=unused-result`
    # 之类**clang 专有**的开关，node 自己的 Windows 构建根本没让它们生效过 ——
    # 全量喂进去等于单方面把它们变成错误（构建会红），那不是"对齐 node"。
    if(WIN32 AND CMAKE_CXX_COMPILER_ID MATCHES "Clang")
      target_compile_options(${name} PRIVATE
        "$<$<COMPILE_LANGUAGE:C,CXX>:-Wno-unused-parameter>")
    endif()

    # 少数 V8 目标（torque 那一摊）在 gyp 里**把异常/RTTI 又打开了**：
    # v8.gyp 三处都是三种写法一起给的（cflags_cc:-fexceptions / xcode / msvs ExceptionHandling:1）。
    # 上面 MSVS_FLAGS 里已经按 gyp 翻出了 `/EHsc`（或 `/EHs-c-`）与 `/GR-`，但**同一条
    # gyp 事实在 msvs 与 POSIX 两侧的写法不同**（POSIX 是 cflags_cc 的 -fexceptions），
    # 而且 RTTI 得连着 `/GR` 一起开 —— 所以这里再按 EXCEPTIONS 补一次。
    # **必须排在 MSVS_FLAGS 之后**（后面的开关赢）：反过来写会被 `/GR-` 盖回去。
    if(NODE_PORT_V8_${U}_EXCEPTIONS)
      if(CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
        target_compile_options(${name} PRIVATE /EHsc /GR)
      else()
        target_compile_options(${name} PRIVATE -fexceptions -frtti)
      endif()
    endif()
  endif()

  # ---- 链接选项（**与上面那个 if 无关**：INTERFACE 目标也要把链接需求下发给依赖方）----
  if(NOT WIN32)
    if(NODE_PORT_V8_${U}_LDFLAGS_${_plat})
      target_link_options(${name} ${_kw} ${NODE_PORT_V8_${U}_LDFLAGS_${_plat}})
    endif()
    if(NODE_PORT_V8_${U}_LIBRARIES_${_plat})
      target_link_libraries(${name} ${_kw} ${NODE_PORT_V8_${U}_LIBRARIES_${_plat}})
    endif()
  endif()

  # 只写在 msvs_settings 里的那两样：额外科系统库、编译器附加选项。
  # gyp 的 `libraries` / `cflags` 里都没有它们 —— 不收就会链接期报 undefined symbol。
  if(WIN32 AND NODE_PORT_V8_${U}_LINK_LIBS_WIN)
    target_link_libraries(${name} ${_kw} ${NODE_PORT_V8_${U}_LINK_LIBS_WIN})
  endif()

  # 依赖图留到最后统一接（清单里的 dep 有前向引用）。
  set_property(GLOBAL APPEND PROPERTY NODE_PORT_V8_PENDING_DEPS "${name}")
endfunction()

# ---- gyp 依赖图 → CMake（**设计已定、消费待接：见 `9.0-P-26`**）-----------------
#
# 清单里**已经**带着 gyp 的 `dependencies`（`NODE_PORT_V8_<目标>_DEPS`：名字去重、去掉了
# `.gyp` 路径与 `#host`/`#target`）。接成 CMake 的链接 / 构建顺序得先绕开两个
# **我们自己造成的偏离**，所以单独排一个任务做，不在这轮硬接：
#
#   1. **`mksnapshot` 的编译源是我们自己并进去的**（`target_sources` 直取清单变量），
#      而 gyp 图里那是 `mksnapshot → v8_compiler_for_mksnapshot → v8_compiler` 的**链接**关系。
#      照图接 = 同一批源既编又链 → 重复符号。
#   2. **INTERFACE 库不能随手 PRIVATE 链**：CMake 会把它当"库名"透传给链接器
#      （`lld-link: could not open 'v8_compiler_sources.lib'`，实测）。
#
# 接的时候按三条规则分类（vcpkg 顶替 / 只要构建顺序 / 普通目标），
# 并且"没被任何一条接住的名字"必须**当场报错**（否则 gyp 那边加了依赖我们这边静默少链）。
# 分类名单与逐条依据见 `9.0-P-26`。


# 把 node 树里"自带副本"的 include 目录从目标上摘掉。
#
# 背景（`踩坑-31`）：本工程对第三方库的口径是"**用 vcpkg 的**"（`调研-1`），而 gyp 的
# `direct_dependent_settings` 会把 node 自带的同名副本也下发下来 —— 头用自带的、库用
# vcpkg 的，版本对不上：轻则链接期 undefined（llhttp），重则**运行期堆损坏**
# （`fe -e` 直接 STATUS_HEAP_CORRUPTION）。
#
# 为什么不用 `BEFORE` 把 vcpkg 的提前：CMake 对同一个目录去重、且 imported target 那份是
# SYSTEM（`-imsvc`），`BEFORE PRIVATE` 加了也不进命令行（实测）。所以只能做减法。
function(node_port_drop_bundled_include tgt)
  foreach(_d IN LISTS ARGN)
    foreach(_prop IN ITEMS INCLUDE_DIRECTORIES INTERFACE_INCLUDE_DIRECTORIES)
      get_target_property(_incs ${tgt} ${_prop})
      if(_incs)
        list(REMOVE_ITEM _incs "${NODE_ROOT}/${_d}")
        set_target_properties(${tgt} PROPERTIES ${_prop} "${_incs}")
      endif()
    endforeach()
  endforeach()
endfunction()

# 标准名单：`node_port_node_third_party` 链接的那批包在 node 树里的自带副本。
# **不在名单里的不许摘**：uvwasi / ncrypto / nbytes / merve / inspector_protocol /
# googletest（gtest_prod.h）是我们自己编的，V8 那棵树同理。
set(NODE_PORT_BUNDLED_INCLUDE_DROP
  deps/llhttp/include
  deps/uv/include
  deps/cares/include
  deps/brotli/c/include
  deps/zlib
  deps/ada
  deps/simdjson
  deps/nghttp2/lib/includes
  deps/zstd/lib
  deps/sqlite
  deps/histogram/include
  deps/histogram/src
  deps/openssl/openssl/include
  deps/openssl/openssl/crypto/include
  CACHE INTERNAL "node 树里自带、但我们用 vcpkg 那份的 include 目录（踩坑-31）")

# 读 generated/<动作>_action.cmake 里那批变量（工具、命令行、输入、输出、要建的目录），
# 挂成 add_custom_command。
#
# 两件 CMake 侧必须自己补的事：
#   1. **先建目录**：工具写文件走的是 utils.cc:327 的 ReplaceFileContentsIfDifferent，
#      直接 ofstream.open —— 目录不存在就**静默不写**（torque 那次实测只出 20 个聚合文件）。
#      官方靠 ninja 给声明过的 outputs 建目录，这里显式建一遍，不依赖生成器行为。
#   2. **声明全部输出**：不声明的话增量构建不知道该重跑。
#      曾经把路径拼错一层（声明在 torque-generated/torque-generated/ 下），
#      ninja 老老实实建了个空目录、文件却在上一层 —— **声明的路径必须和真写出的对得上**。
#
# 可选 `TARGET <名>`：动作的 CMake 目标名默认取动作名，但**动作名有时会撞上同名目标**
# （node.gyp 里 libnode 的动作叫 node_mksnapshot，而 node_mksnapshot 本身又是一个
# 可执行目标 —— add_custom_target 会直接报 "another target with the same name
# already exists"）。撞名时用 TARGET 指定另一个名字，清单文件与变量前缀仍按动作名。
function(node_port_add_v8_action name)
  cmake_parse_arguments(NODE_PORT "" "TARGET" "" ${ARGN})
  if(NOT NODE_PORT_TARGET)
    set(NODE_PORT_TARGET "${name}")
  endif()
  string(TOUPPER "${name}" U)
  get_property(_gen GLOBAL PROPERTY NODE_PORT_V8_GEN_DIR)
  set(_f "${_gen}/${name}_action.cmake")
  if(NOT EXISTS "${_f}")
    message(FATAL_ERROR
      "缺 ${name} 的生成清单：${_f}\n"
      "用这条命令生成（输入在同级 ../gyp2vcpkg/，产物出到 ${_gen}）：\n"
      "  python ../gyp2vcpkg/gyp2vcpkg.py all --config ../gyp2vcpkg/config.json"
      " --node-root \${NODE_ROOT} --env win=../gyp2vcpkg/env/win-x64.json"
      " --env linux=../gyp2vcpkg/env/linux-x64.json")
  endif()
  include("${_f}")

  set(_prep "")
  if(NODE_PORT_${U}_OUTPUT_DIRS)
    list(APPEND _prep COMMAND ${CMAKE_COMMAND} -E make_directory ${NODE_PORT_${U}_OUTPUT_DIRS})
  endif()
  add_custom_command(
    OUTPUT ${NODE_PORT_${U}_OUTPUTS}
    ${_prep}
    COMMAND ${NODE_PORT_${U}_CMD}
    DEPENDS ${NODE_PORT_${U}_TOOL} ${NODE_PORT_${U}_INPUTS}
    # cwd = 仓库根：gyp 的动作就是以 .gyp 所在目录为 cwd 跑的，node 的
    # inspector 协议链依赖这一点（config 里的相对路径按 cwd 解析；不设的话
    # ninja 用构建目录 cwd，命令"成功"但**什么都不产出**，实测）。
    WORKING_DIRECTORY "${NODE_ROOT}"
    COMMENT "${name}：${NODE_PORT_${U}_TOOL} → ${NODE_PORT_${U}_OUTDIR}"
    VERBATIM)
  add_custom_target(${NODE_PORT_TARGET} DEPENDS ${NODE_PORT_${U}_OUTPUTS})
endfunction()
