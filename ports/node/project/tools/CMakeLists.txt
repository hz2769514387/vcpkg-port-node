# 构建期工具（`9.0-P-3`：代码生成链的第一步）。
#
# node 的构建里有一批**先编个工具、再用它生成代码**的步骤（gyp 里的 `toolsets: ['host']`）。
# 在 CMake 里对应做法就是：这些工具是**普通的可执行文件目标**，生成物用
# `add_custom_command(OUTPUT ... COMMAND ...)` 接到依赖链上。
#
# 目标名沿用 node gyp 里的名字。**源文件一个字不动。**

set(NODE_PORT_SRC "${NODE_ROOT}/src")

# tools/executable_wrapper.h 里 `#include <uv.h>` —— 所以这个工具要链 libuv。
# （gyp 里没明写，因为 node 的构建全局都能看见 uv.h；我们不给全局 include，所以显式链。）
find_package(libuv CONFIG REQUIRED)

# simdutf：gyp 的 node_js2c 在 `node_shared_simdutf=="false"` 时依赖
# `tools/v8_gypfiles/v8.gyp:simdutf#host` —— 即 **V8 自带的那份 6.4.0**
# （`deps/v8/third_party/simdutf/simdutf.cpp` 单文件 amalgamation）。
#
# **不用 vcpkg 的 8.2.0**（`调研-11`/`踩坑-19`）：6.4 头的重载在 8.2 库里没有对应
# mangled 符号，而且两份同命名空间会撞。vcpkg.json 里已删掉 simdutf 声明
# （`dep-conflict-audit.js` 会把这种撞名报 FAIL）。
# 我们这边就是 `src/v8` 建的 `simdutf` 目标（同一份源），下面链它即可。

# node_js2c —— 构建期工具。**源/宏/include 全部从 gyp2vcpkg 的清单来**
# （`cmake/gyp2vcpkg/generated/node_js2c.cmake`），不再手抄：
#
#   * 源：tools/js2c.cc、src/embedded_data.cc、src/builtin_info.cc；
#   * include：'tools'、'src'、V8 自带的 simdutf、deps/uv/include；
#   * 依赖（清单里的 `_DEPS`）：simdutf（V8 那份）+ libuv（vcpkg 的 `libuv::uv_a`，
#     见下面那行 —— 那是**我们的**决定，gyp 说了不算）。
#
node_port_add_v8_target(node_js2c)
# 两个 vcpkg / 自有目标的链接（清单里的 `_DEPS` 已经点了名，这里照它接）：
#   simdutf —— V8 自带那份的 CMake 目标（src/v8 建的，所以 src/v8 要**先** add_subdirectory）
#   libuv   —— vcpkg 的（`调研-1`）
node_port_pick_target(_node_uv libuv::uv_a libuv::uv)
target_link_libraries(node_js2c PRIVATE simdutf ${_node_uv})

# ---------------------------------------------------------------------------
# node_js2c —— 把 lib/*.js 与 deps 里的 JS 打成 C++ 源文件（`node_javascript.cc`）。
#
# 蓝本：node.gyp 的 `node_js2c` target（type executable / toolsets host）：
#   include_dirs: ['tools', 'src']
#   sources:      tools/js2c.cc, tools/executable_wrapper.h,
#                 src/embedded_data.h/.cc, src/builtin_info.h/.cc
#
# 调用方式（node.gyp 里那个 action 的原文）：
#   node_js2c <输出的 .cc>  lib  config.gypi  <deps_files…>  <linked_module_files…>
# —— 它**要读 config.gypi** 来决定编进哪些模块，所以下一步是把 config.gypi 也生成出来。
#
# 好消息：这三个源文件只 include 自己的头 + 标准头，**不依赖 config.h**，所以现在就能编。
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 用 node_js2c 生成 `node_javascript.cc`（把 lib/*.js 与 deps 里的 JS 打成 C++ 源文件）。
#
# 命令行照 node.gyp 里那个 action 的原文：
#   node_js2c <输出的 .cc>  lib  config.gypi  <deps_files…>  <linked_module_files…>
#   （`linked_module_files` 默认是空的，所以这里没有）
# 并且要 `--root <项目根>`：js2c 会 chdir 过去（tools/js2c.cc 里的 uv_chdir），
# 所以 `lib` 与下面这些相对路径都是相对项目根的 —— 和 node 自己的构建一致。
#
# deps_files 照 node.gyp:56-71 抄（**逐个列、不用通配符** —— 原注释说得很明白：
#   "We list the deps/ files out instead of globbing them in js2c.cc since we
#    only include a subset of all the files under these directories."）
# 最后两条是 `node_builtin_shareable_builtins` 的值（官方 config.gypi 里就是这两个）。
# ---------------------------------------------------------------------------
set(NODE_PORT_GENERATED "${CMAKE_BINARY_DIR}/generated")

set(NODE_PORT_JS2C_DEPS_REL
  deps/v8/tools/splaytree.mjs
  deps/v8/tools/codemap.mjs
  deps/v8/tools/consarray.mjs
  deps/v8/tools/csvparser.mjs
  deps/v8/tools/profile.mjs
  deps/v8/tools/profile_view.mjs
  deps/v8/tools/logreader.mjs
  deps/v8/tools/arguments.mjs
  deps/v8/tools/tickprocessor.mjs
  deps/v8/tools/sourcemap.mjs
  deps/v8/tools/tickprocessor-driver.mjs
  deps/acorn/acorn/dist/acorn.js
  deps/acorn/acorn-walk/dist/walk.js
  deps/minimatch/index.js
  deps/undici/undici.js
  deps/amaro/dist/index.js)

set(NODE_PORT_JS2C_DEPS_ABS "")
foreach(f IN LISTS NODE_PORT_JS2C_DEPS_REL)
  list(APPEND NODE_PORT_JS2C_DEPS_ABS "${NODE_ROOT}/${f}")
endforeach()

# **`lib/**` 必须列进来**（`9.0-P-15` 查实的洞）：蓝本 node.gyp:996-1010 的 `inputs` 里
# 有 `<@(library_files)`（= configure.py:1650 的 `SearchFiles('lib', 'js')`，我们
# `tools/bootstrap/env/*.json` 里那张 372 项的清单就是它），而 `lib` 只是**命令行参数**
# （node_js2c 运行时自己去读目录）—— 不列进 DEPENDS 的话，**改 `lib/` 下任何 JS
# 都不会触发这一次生成**，症状是"改了源码、产物里还是旧的"，而且一句提示都没有
# （实测：`9.0-P-13` 改的欢迎词就没进 `fe.exe`）。
#
# **这里**绝对不能**写 `CONFIGURE_DEPENDS`**（`9.0-P-19` 查实的坑，见 踩坑-26）：
# 它会让 CMake 生成一个 `VerifyGlobs.cmake_force` 伪目标（**永远 dirty**），于是
# `cmake.verify_globs` → `RERUN_CMAKE` → **每次 ninja 构建都重新跑一遍 cmake**，
# `build.ninja` 被重写、整个图被判脏 —— 症状是"改一行代码也要全量重编 4 小时"，
# 而且**看不出来是谁干的**（ninja 只说 "Re-running CMake..."）。
# 代价：`lib/` 下**新增/删除** JS 文件时要手动重跑一次 cmake（改内容不用），
# 由 `tools/check/check.js` 第 14 项对照 `tools/bootstrap/env/*.json` 的清单来抓（增删了就报红，
# 提示"重新 configure"）。
file(GLOB_RECURSE NODE_PORT_JS2C_LIB_ABS
  "${NODE_ROOT}/lib/*.js" "${NODE_ROOT}/lib/*.mjs")

add_custom_command(
  OUTPUT "${NODE_PORT_GENERATED}/node_javascript.cc"
  COMMAND node_js2c
          --root "${NODE_ROOT}"
          "${NODE_PORT_GENERATED}/node_javascript.cc"
          lib
          "${NODE_PORT_CONFIG_GYPI}"
          ${NODE_PORT_JS2C_DEPS_REL}
  # `${NODE_PORT_CONFIG_GYPI}` **必须按文件列进 DEPENDS**（不只是那个 `node_port_config_gypi` 目标）：
  # 目标级依赖只保证"先建"，**不会**在 config.gypi 内容变了之后重跑这条命令 ——
  # 于是新的 config.gypi 永远嵌不进产物（`9.0-T-10` 查实：改成按平台取种子后，
  # linux 的 config.gypi 变了、node_javascript.cc 却没重生成，fe 里还是旧的 process.config）。
  DEPENDS node_js2c node_port_config_gypi ${NODE_PORT_CONFIG_GYPI} ${NODE_PORT_JS2C_DEPS_ABS} ${NODE_PORT_JS2C_LIB_ABS}
  COMMENT "node_js2c：lib/*.js + deps 的 JS → node_javascript.cc"
  VERBATIM)

add_custom_target(node_javascript DEPENDS "${NODE_PORT_GENERATED}/node_javascript.cc")

# ---------------------------------------------------------------------------
# mkssldef：生成 openssl.def（Windows + 静态链 OpenSSL 时才需要）。
#
# 蓝本：node.gyp 的 `mkssldef` action。启用条件是
#   OS=="win" and node_use_openssl=="true" and node_shared_openssl=="false"
# —— 三条我们全中（工程约定第 1 条：静态单 exe）。
#
# **这一步是必需的，不是可选**：实测官方 `node.exe` 的导出表有 **9656 个符号**
# （两种独立方法都量到同一个数：`llvm-readobj --coff-exports` 与自写的 PE 导出目录解析，
#   `NumberOfNames = 9656`；含 `EVP_*` 842 个与 `ERR_load_EVP_strings`）
# —— 原生插件就靠这些符号。没有 openssl.def，编出来的 node.exe 不导出它们。
#
# **正确性判据（已实测）**：生成的 openssl.def 有 5531 个符号，
# 与官方导出表求差集 —— **"只在 def 里、官方没导出" = 0 个**。
# 也就是说 def 是官方导出表的子集，一个都没多余；剩下 4125 个是 V8/ICU/node 自己的
# C++ 修饰名等，由别的途径导出，与这一步无关。
#
# 脚本要 python（`tools/mkssldef.py`）—— 按 `调研-4` 的口径：**python 是已承认的构建前置**，
# 不在这一步上搞"去 python"。
#
# 三个输入**都在 node 自己的树里**（deps/openssl/openssl/util/*.num 与 deps/zlib/win32/zlib.def），
# 所以不用去找 OpenSSL 的源码包。
# ---------------------------------------------------------------------------
if(WIN32)
  find_package(Python3 REQUIRED COMPONENTS Interpreter)

  # 注意 `-C` 必须是**一个**参数。node.gyp 里它写成五段相邻的字符串字面量
  # （`'…' '…' '…'`），在 gyp 的 Python 字面量语法里那是**拼接成一个字符串**，
  # 一个列表项。我第一版按 CMake 的写法拆成了五个列表项，CMake 就当成五个 argv 传进去，
  # mkssldef.py 把后面四段当成了输入文件：
  #   FileNotFoundError: 'MD4,MD5,PSK,RC2,RC4,RSA,SHA,…'
  # 所以这里合成一行。（`-DOPENSSL_FIPS` 是 openssl_is_fips=="true" 时才加的，我们不加。）
  set(NODE_PORT_MKSSLDEF_FLAGS
    "-CAES,ARGON2,BF,BIO,DES,DH,DSA,EC,ECDH,ECDSA,ENGINE,EVP,HMAC,MD4,MD5,PSK,RC2,RC4,RSA,SHA,SHA0,SHA1,SHA256,SHA512,SOCK,STDIO,TLSEXT,UI,FP_API,TLS1_METHOD,TLS1_1_METHOD,TLS1_2_METHOD,SCRYPT,OCSP,NEXTPROTONEG,RMD160,CAST,DEPRECATEDIN_1_1_0,DEPRECATEDIN_1_2_0,DEPRECATEDIN_3_0"
    "-DWIN32"
    "-X^DSO"
    "-X^_"
    "-X^private_"
    "-B${NODE_ROOT}/deps/zlib/win32/zlib.def")

  add_custom_command(
    OUTPUT "${NODE_PORT_GENERATED}/openssl.def"
    COMMAND Python3::Interpreter "${NODE_ROOT}/tools/mkssldef.py"
            ${NODE_PORT_MKSSLDEF_FLAGS}
            -o "${NODE_PORT_GENERATED}/openssl.def"
            "${NODE_ROOT}/deps/openssl/openssl/util/libcrypto.num"
            "${NODE_ROOT}/deps/openssl/openssl/util/libssl.num"
    DEPENDS "${NODE_ROOT}/tools/mkssldef.py"
            "${NODE_ROOT}/deps/openssl/openssl/util/libcrypto.num"
            "${NODE_ROOT}/deps/openssl/openssl/util/libssl.num"
            "${NODE_ROOT}/deps/zlib/win32/zlib.def"
    COMMENT "mkssldef：生成 openssl.def（node.exe 要把 OpenSSL 的符号导出给原生插件）"
    VERBATIM)

  add_custom_target(node_port_openssl_def DEPENDS "${NODE_PORT_GENERATED}/openssl.def")
endif()
