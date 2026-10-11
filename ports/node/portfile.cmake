# node port —— 把 Node.js v24.21.0 整棵树编成可链接的 node 静态库（**路线 B：gyp → ninja**）。
#
# 为什么是 gyp → ninja（而不是"把 gyp 翻译成 CMake"）：
#   * node 官方唯一的构建入口就是 gyp —— 上游 Windows 走 MSBuild、Unix 走 Makefile，
#     两者背后都是 `tools/gyp_node.py`。直接驱动 gyp 生成的 ninja，最贴近官方路径，
#     也避免手写/翻译一整棵 CMake 工程带来的长期维护成本。
#   * gyp 自带 cmake generator 被上游自述为 experimental 且仅限 Linux，不可依赖。
#
# 三平台统一：`gyp -f ninja` → `ninja -C out/Release libnode`。
#
# ★ 本 port 是**自包含**的：目录里只有 portfile / vcpkg.json / patches / usage，
#   不引用 port 目录外的任何文件，也不自带 triplet / toolchain（那是消费端的构建配置）。
#   Windows 需要 clang-cl 时，走 vcpkg 标准变量 VCPKG_CHAINLOAD_TOOLCHAIN_FILE 从 triplet
#   交接过来 —— 于是换成使用者自己的 clang-cl triplet 也能工作。
#
# 口径要点：
#   * Windows **必须用 clang-cl**（node 24+ 的官方口径，vcbuild.bat 强制 ClangCL），
#     这也是 ninja 生成器能编过 node 的 DevTools 协议模板的前提。
#   * 依赖全部走 vcpkg（`--shared-*`），不编 node 内嵌副本；ICU 走 system-icu。
#   * 交付物是**静态库**：请求动态库时报错（结构性不可能，而非"没测过"）。

vcpkg_check_linkage(ONLY_STATIC_LIBRARY)

vcpkg_download_distfile(NODE_ARCHIVE
    URLS "https://nodejs.org/dist/v24.21.0/node-v24.21.0.tar.gz"
    SHA512 8bb098aa786298ceaf25797adb5551ff4edcafcdc19a669e530a42c60ca71c1b12da2f93253ded2dd7e9ac5a5d0a922e81789542912905e1c16b1754dcf628b8
    FILENAME nodejs-node-v24.21.0.tar.gz
)

vcpkg_extract_source_archive(SOURCE_PATH
    ARCHIVE "${NODE_ARCHIVE}"
    SOURCE_BASE node-v24.21.0
    PATCHES
        "${CMAKE_CURRENT_LIST_DIR}/patches/0001-icu-system-add-icudata.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0002-gyp-ninja-clang-cl-libpath-asm.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0003-gyp-msvs-emulation-rsp-pch-std.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0004-gyp-msvs-settings-language-standard.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0005-gyp-win-tool-utf8-decode.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0006-gyp-ninja-syntax-iterable-guard.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0007-gyp-common-predefines-clang-cl.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0008-configure-shared-syslibs-and-clang-cl.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0009-js2c-normalize-windows-paths.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0010-torque-normalize-windows-paths.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0011-v8-use-vcpkg-simdutf-target.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0012-v8-simdutf-system-include.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0013-v8-compiler-add-descriptor-array-inl.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0014-v8-use-vcpkg-zlib-target.patch"
)

# 构建期工具（都用 vcpkg 自带的，不要求系统装）。
vcpkg_find_acquire_program(PYTHON3)
vcpkg_find_acquire_program(NINJA)

# ---------------------------------------------------------------------------
# 编译环境：三平台一律 clang（工程约定）。
#   * Windows：clang-cl。**编译器路径由 triplet 经 VCPKG_CHAINLOAD_TOOLCHAIN_FILE 交接**，
#     port 里因此不需要也不携带任何 toolchain 文件。同时，triplet 已经在 portfile 之前
#     被 vcpkg include 过（scripts/ports.cmake:176），INCLUDE/LIB/PATH 也已就位。
#   * Linux / macOS：用系统 cc / c++。
# configure.py 通过 CC/CXX 环境变量决定 make_global_settings，进而决定 gyp 的 cl 规则。
# ---------------------------------------------------------------------------
set(_node_cc "")
set(_node_cxx "")
set(_node_clang_cl_arg "")

if(VCPKG_TARGET_IS_WINDOWS)
    # chainload toolchain 是 vcpkg 的标准交接机制：triplet 声明它，vcpkg 把它交给 port。
    # 我们的 triplet 交来的那一份会发布 NODE_PORT_LLVM_BIN / NODE_PORT_VS_INSTALL_ROOT，
    # 并把 MSVC 命令行环境配好。
    if(DEFINED VCPKG_CHAINLOAD_TOOLCHAIN_FILE AND NOT VCPKG_CHAINLOAD_TOOLCHAIN_FILE STREQUAL "")
        include("${VCPKG_CHAINLOAD_TOOLCHAIN_FILE}")
    endif()

    if(DEFINED NODE_PORT_LLVM_BIN AND NOT NODE_PORT_LLVM_BIN STREQUAL "")
        set(_node_clang_cl "${NODE_PORT_LLVM_BIN}/clang-cl.exe")
    elseif(DEFINED ENV{CC} AND "$ENV{CC}" MATCHES "clang-cl")
        set(_node_clang_cl "$ENV{CC}")
    else()
        find_program(_node_clang_cl NAMES clang-cl)
    endif()
    if(NOT _node_clang_cl)
        message(FATAL_ERROR
            "Windows 上构建本 port 需要 clang-cl（node 24+ 官方口径）。\n"
            "请用一个把 clang-cl 交接给 port 的 triplet：本仓库的消费端示例工程里，\n"
            "`cmake/triplets/` 下的 x64-windows-static-clang.cmake 就是这么做的\n"
            "（它设置 VCPKG_CHAINLOAD_TOOLCHAIN_FILE 指向 clang-cl.cmake）。")
    endif()

    set(_node_cc "${_node_clang_cl}")
    set(_node_cxx "${_node_clang_cl}")

    # gyp 在中文 locale 下的两个已知坑：VS 定位失败 / reg.exe 解码失败。
    set(ENV{GYP_MSVS_VERSION} 2022)
    if(NODE_PORT_VS_INSTALL_ROOT)
        set(ENV{GYP_MSVS_OVERRIDE_PATH} "${NODE_PORT_VS_INSTALL_ROOT}")
    endif()
    set(ENV{DXSDK_DIR} "C:/nonexistent")

    # system-icu 需要 pkg-config：用 vcpkg_find_acquire_program(PKGCONFIG) 拿 MinGW 原生版
    # （MSYS2 运行时版的 pkg-config 无法读 Windows 风格的 PKG_CONFIG_PATH）。
    vcpkg_find_acquire_program(PKGCONFIG)
    set(ENV{PKG_CONFIG} "${PKGCONFIG}")

    # vcpkg 依赖的头文件和库文件加入 INCLUDE/LIB：gyp 的非 v8 目标（如 js2c）
    # 也需要 simdutf.h，链接器需要 simdutf.lib —— 不加这里，每个目标都要单独配路径。
    set(ENV{INCLUDE} "${CURRENT_INSTALLED_DIR}/include;$ENV{INCLUDE}")
    set(ENV{LIB} "${CURRENT_INSTALLED_DIR}/lib;$ENV{LIB}")

    # --clang-cl=<ver> 让 configure.py 设 clang=1，这使 v8.gyp 的 asm_to_inline_asm
    # action 把 embedded.S 转成 embedded.cc（否则 embedded blob 符号丢失，链接失败）。
    execute_process(
        COMMAND "${_node_cc}" --version
        OUTPUT_VARIABLE _clang_version_output
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE)
    # 用 [.] 而不是 \. —— CMake 的引号字符串里 \. 是非法转义序列（会报 dev 级警告）。
    string(REGEX REPLACE "^clang version ([0-9]+[.][0-9]+[.][0-9]+).*" "\\1"
           _llvm_version "${_clang_version_output}")
    set(_node_clang_cl_arg "--clang-cl=${_llvm_version}")

    # patches/0007 与 0008 要用 clang.exe（clang-cl 的兄弟）做宏/OpenSSL 版本探测，并把
    # compiler-rt 内建库挂到链接行上 —— 这些开关**必须是目标架构的**，不能写死 x86_64。
    # 目标三元组与内建库名从这里交给补丁（补丁只读环境变量，内部不含架构常量）。
    if(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
        set(_node_llvm_arch "aarch64")
        set(_node_rt_arch "aarch64")
    elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "x86")
        set(_node_llvm_arch "i686")
        set(_node_rt_arch "i386")
    else()
        set(_node_llvm_arch "x86_64")
        set(_node_rt_arch "x86_64")
    endif()
    set(ENV{NODE_PORT_CLANG_TARGET} "${_node_llvm_arch}-pc-windows-msvc")
    set(ENV{NODE_PORT_CLANG_RT_BUILTINS_NAME} "clang_rt.builtins-${_node_rt_arch}")
else()
    find_program(_node_c_prog NAMES cc gcc)
    find_program(_node_cxx_prog NAMES c++ g++ clang++)
    set(_node_cc "${_node_c_prog}")
    set(_node_cxx "${_node_cxx_prog}")
    set(ENV{PKG_CONFIG} "pkg-config")
endif()

# shlex 会吃反斜杠：CC/CXX 与 PKG_CONFIG 一律用正斜杠（Windows 上尤其重要）。
set(ENV{CC} "${_node_cc}")
set(ENV{CXX} "${_node_cxx}")
set(ENV{PKG_CONFIG_PATH} "${CURRENT_INSTALLED_DIR}/lib/pkgconfig")

# ---------------------------------------------------------------------------
# prepare_shared：把 vcpkg 依赖以 --shared-<lib> 的形式喂给 configure.py。
# 库名必须写 vcpkg 包里真实的库文件名（不含扩展名），Windows 静态口径有若干差异
# （zlib → zs；brotli 去 lib 前缀；openssl 保留 lib 前缀）。
# ---------------------------------------------------------------------------
set(_inc "${CURRENT_INSTALLED_DIR}/include")
set(_lib "${CURRENT_INSTALLED_DIR}/lib")

macro(_node_shared _opt _pkg _libnames)
    list(APPEND _node_shared_args
        "--shared-${_opt}"
        "--shared-${_opt}-includes=${_inc}"
        "--shared-${_opt}-libpath=${_lib}"
        "--shared-${_opt}-libname=${_libnames}")
endmacro()

set(_node_shared_args "")

# Windows static-clang 和 Linux/macOS 的静态库名不同：
#   * Windows：zlib→zs, openssl→libcrypto,libssl, libuv→libuv
#   * Linux/macOS：zlib→z, openssl→crypto,ssl, libuv→uv
# hdr_histogram 在所有平台都装 hdr_histogram_static。
# 其余依赖库名两平台一致。
if(VCPKG_TARGET_IS_WINDOWS)
    set(_zlib_lib      "zs")
    set(_openssl_lib   "libcrypto,libssl")
    set(_libuv_lib     "libuv")
else()
    set(_zlib_lib      "z")
    set(_openssl_lib   "crypto,ssl")
    set(_libuv_lib     "uv")
endif()
set(_hdrhist_lib   "hdr_histogram_static")

_node_shared(openssl       openssl     "${_openssl_lib}")
_node_shared(zlib          zlib        "${_zlib_lib}")
_node_shared(libuv         libuv       "${_libuv_lib}")
_node_shared(cares         c-ares      "cares")
_node_shared(brotli        brotli      "brotlidec,brotlienc,brotlicommon")
_node_shared(nghttp2       nghttp2     "nghttp2")
_node_shared(ngtcp2        ngtcp2      "ngtcp2")
_node_shared(http-parser   llhttp      "llhttp")
_node_shared(zstd          zstd        "zstd")
_node_shared(simdjson      simdjson    "simdjson")
_node_shared(simdutf       simdutf     "simdutf")
_node_shared(sqlite        sqlite3     "sqlite3")
_node_shared(ada           ada-url     "ada")
_node_shared(hdr-histogram hdr-histogram "${_hdrhist_lib}")

# ---------------------------------------------------------------------------
# 1) configure.py：生成 config.gypi + 内部调 gyp 生成 ninja 构建文件。
#    --ninja → configure.py 传 `-f ninja-<flavor>`（Windows 上是 ninja-win）。这是合法
#    写法：gyp 的 Load() 里有 `if "-" in format: format, flavor = format.split("-", 1)`，
#    会把它拆成 format=ninja + flavor=win（见 tools/gyp/pylib/gyp/__init__.py）。
#    -DVCPKG_SIMDUTF_INCLUDE 供 patches/0011 的 v8 simdutf 目标使用。
# ---------------------------------------------------------------------------
vcpkg_execute_required_process(
    COMMAND "${PYTHON3}" configure.py
        --ninja
        ${_node_clang_cl_arg}
        --with-intl=system-icu
        ${_node_shared_args}
        "-DVCPKG_SIMDUTF_INCLUDE=${_inc}"
    WORKING_DIRECTORY "${SOURCE_PATH}"
    LOGNAME configure
)

# ---------------------------------------------------------------------------
# 2) ninja 构建可链接库 `libnode`（gyp 目标名，见 node.gyp 的 node_lib_target_name）。
#    并发度跟随 vcpkg（VCPKG_CONCURRENCY，来自 VCPKG_MAX_CONCURRENCY）：ninja 默认是
#    "核数+2"，在 3 核 / 7 GB 的 macOS arm64 runner 上会同时跑 5 个重型 V8 编译单元，
#    容易 OOM。vcpkg 自带的 vcpkg_build_ninja 反而不传 -j，所以这里显式传。
# ---------------------------------------------------------------------------
set(_node_ninja_jobs "")
if(DEFINED VCPKG_CONCURRENCY AND NOT VCPKG_CONCURRENCY STREQUAL "")
    set(_node_ninja_jobs "-j${VCPKG_CONCURRENCY}")
endif()

vcpkg_execute_required_process(
    COMMAND "${NINJA}" -C "${SOURCE_PATH}/out/Release" ${_node_ninja_jobs} libnode
    WORKING_DIRECTORY "${SOURCE_PATH}"
    LOGNAME build
)

# ---------------------------------------------------------------------------
# 3) 安装：头文件 + 全部 gyp 静态库 + 手写 CMake 消费配置。
# ---------------------------------------------------------------------------
file(INSTALL "${SOURCE_PATH}/src/" DESTINATION "${CURRENT_PACKAGES_DIR}/include/node"
    FILES_MATCHING PATTERN "*.h" PATTERN "*.hpp")
file(INSTALL "${SOURCE_PATH}/deps/v8/include/" DESTINATION "${CURRENT_PACKAGES_DIR}/include")

# src/api 和 src/res 只有 .cc 没有 .h，file(INSTALL) 会留空目录，vcpkg 校验会警告。
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/include/node/api" "${CURRENT_PACKAGES_DIR}/include/node/res")

# 收集 gyp 产出的静态库（libnode 本体 + v8 各库 + 内嵌第三方库 + node_base 等）。
if(VCPKG_TARGET_IS_WINDOWS)
    set(_node_lib_suffix ".lib")
else()
    set(_node_lib_suffix ".a")
endif()
file(GLOB_RECURSE _node_archives "${SOURCE_PATH}/out/Release/obj/*${_node_lib_suffix}")
foreach(_a IN LISTS _node_archives)
    file(INSTALL "${_a}" DESTINATION "${CURRENT_PACKAGES_DIR}/lib")
endforeach()

# Windows 平台兼容性清单：消费方也要嵌（缺了一跑退出码 216）。
if(VCPKG_TARGET_IS_WINDOWS)
    file(INSTALL "${SOURCE_PATH}/src/res/node.exe.extra.manifest"
        DESTINATION "${CURRENT_PACKAGES_DIR}/share/node" RENAME node.exe.extra.manifest)
endif()

# ---- 手写消费配置（不用 install(EXPORT)：库是 gyp 产物、不是 CMake 目标）--------
#
# ★ gyp 的静态库命名规则（tools/gyp/pylib/gyp/generator/ninja.py 的
#   ComputeOutputFileName，以及 node.gyp:16-18 的注释"Gyp will prefix this with `lib`
#   if this name does not start with `lib`"）：
#     * 非 Windows：前缀 "lib"，且**先把 target_name 开头的 "lib" 剥掉**再补前缀
#       → target `libnode` 的产物是 `libnode.a`（**不是** liblibnode.a），
#         target `node_base` 的产物是 `libnode_base.a`。
#     * Windows：前缀为空 → `libnode.lib` / `node_base.lib`。
#   直接拼 "lib" + target + ".a" 会在 Linux/macOS 上算出 liblibnode.a 这个不存在的
#   文件，消费端 CMake 立刻报 "imported target … references the file … but this file
#   does not exist"。所以这里按 gyp 的语义算文件名。
function(_node_archive_filename _target _out)
    if(VCPKG_TARGET_IS_WINDOWS)
        set(${_out} "${_target}.lib" PARENT_SCOPE)
    else()
        string(REGEX REPLACE "^lib" "" _node_stripped "${_target}")
        set(${_out} "lib${_node_stripped}.a" PARENT_SCOPE)
    endif()
endfunction()

set(_cfg "# 由 node port 生成：node 的 CMake 消费配置。\n")
string(APPEND _cfg "include(CMakeFindDependencyMacro)\n")
# hdr_histogram-config.cmake 内部用 find_dependency(ZLIB) module mode，
# 在 Windows static 下找不到 zs.lib。必须在 hdr_histogram 之前先用 CONFIG 模式
# 找到 ZLIB，并设好 cache 变量 ZLIB_LIBRARY / ZLIB_INCLUDE_DIR，
# 这样 hdr_histogram 内部的 module-mode find_dependency(ZLIB) 就能复用。
string(APPEND _cfg "find_dependency(ZLIB CONFIG)\n")
string(APPEND _cfg
    "if(TARGET ZLIB::ZLIB)\n"
    "  get_target_property(_zlib_loc ZLIB::ZLIB IMPORTED_LOCATION)\n"
    "  if(_zlib_loc)\n"
    "    set(ZLIB_LIBRARY \"\${_zlib_loc}\" CACHE FILEPATH \"Path to zlib library\")\n"
    "  endif()\n"
    "  get_target_property(_zlib_inc ZLIB::ZLIB INTERFACE_INCLUDE_DIRECTORIES)\n"
    "  if(_zlib_inc)\n"
    "    set(ZLIB_INCLUDE_DIR \"\${_zlib_inc}\" CACHE PATH \"Path to zlib headers\")\n"
    "  endif()\n"
    "endif()\n")
foreach(_dep "OpenSSL" "libuv CONFIG" "llhttp CONFIG" "c-ares CONFIG"
             "unofficial-brotli CONFIG" "ada CONFIG" "simdjson CONFIG"
             "simdutf CONFIG" "ngtcp2 CONFIG" "zstd CONFIG"
             "ICU COMPONENTS uc i18n data" "unofficial-sqlite3 CONFIG"
             "hdr_histogram CONFIG")
    string(APPEND _cfg "find_dependency(${_dep})\n")
endforeach()
string(APPEND _cfg
    "get_filename_component(_node_prefix \"\${CMAKE_CURRENT_LIST_DIR}/../..\" ABSOLUTE)\n"
    "set(_node_lib \"\${_node_prefix}/lib\")\n")

# node 自身口径下需要串起来的静态库全集（gyp 目标）。
set(_node_all_archives
    libnode node_base
    v8_base_without_compiler v8_compiler v8_init v8_initializers
    v8_initializers_slow v8_snapshot v8_libbase v8_libplatform v8_zlib
    abseil highway
    ncrypto ncrypto_engine nbytes merve uvwasi crdtp)
foreach(_a IN LISTS _node_all_archives)
    _node_archive_filename("${_a}" _node_file)
    string(APPEND _cfg
        "if(NOT TARGET node::${_a})\n"
        "  add_library(node::${_a} STATIC IMPORTED)\n"
        "  set_target_properties(node::${_a} PROPERTIES IMPORTED_LOCATION"
        " \"\${_node_lib}/${_node_file}\")\n"
        "endif()\n")
endforeach()
unset(_node_file)

string(APPEND _cfg
    "add_library(node::node INTERFACE IMPORTED)\n"
    "set_target_properties(node::node PROPERTIES"
    " INTERFACE_INCLUDE_DIRECTORIES \"\${_node_prefix}/include;\${_node_prefix}/include/node\")\n")
# 链接顺序：libnode 先，其余静态库在后；循环引用由链接器自行处理（Windows 直接列）。
string(APPEND _cfg "set(_node_link node::libnode node::node_base")
foreach(_a IN LISTS _node_all_archives)
    if(NOT _a STREQUAL "libnode" AND NOT _a STREQUAL "node_base")
        string(APPEND _cfg " node::${_a}")
    endif()
endforeach()
string(APPEND _cfg ")\n")
# nghttp2 没有 CMake config 文件，手动建 imported target。
string(APPEND _cfg
    "find_library(_nghttp2_lib nghttp2 HINTS \${_node_lib} REQUIRED)\n"
    "if(NOT TARGET node::nghttp2)\n"
    "  add_library(node::nghttp2 STATIC IMPORTED)\n"
    "  set_target_properties(node::nghttp2 PROPERTIES IMPORTED_LOCATION \"\${_nghttp2_lib}\")\n"
    "endif()\n")
string(APPEND _cfg
    "target_link_libraries(node::node INTERFACE \${_node_link}"
    " OpenSSL::SSL OpenSSL::Crypto libuv::uv_a c-ares::cares"
    " unofficial::brotli::brotlidec unofficial::brotli::brotlienc"
    " unofficial::brotli::brotlicommon ZLIB::ZLIB ada::ada simdjson::simdjson"
    " simdutf::simdutf ngtcp2::ngtcp2_static zstd::libzstd_static"
    " ICU::uc ICU::i18n ICU::data unofficial::sqlite3::sqlite3"
    " hdr_histogram::hdr_histogram_static node::nghttp2"
    " llhttp::llhttp_static)\n")
# Windows 额外系统库：
#   * winmm：V8 的 timeGetTime。
#   * compiler-rt 内建库：hdr_histogram（以及别的 clang 编出来的 C 代码）用
#     __builtin_cpu_supports 时引用 __cpu_model，而 CMake 对 MSVC 前端的链接规则是
#     直接调 lld-link，绕过了 clang 驱动 —— 内建库不会自动带上。
#     名字**按架构取**（x64 → x86_64，arm64 → aarch64）；若消费端的 chainload toolchain
#     已经算出了绝对路径（NODE_PORT_CLANG_RT_BUILTINS），优先用它。
if(VCPKG_TARGET_IS_WINDOWS)
    string(APPEND _cfg "set(_node_rt_builtins \"clang_rt.builtins-${_node_rt_arch}\")\n")
    string(APPEND _cfg
        "if(DEFINED NODE_PORT_CLANG_RT_BUILTINS AND EXISTS \"\${NODE_PORT_CLANG_RT_BUILTINS}\")\n"
        "  set(_node_rt_builtins \"\${NODE_PORT_CLANG_RT_BUILTINS}\")\n"
        "endif()\n")
    string(APPEND _cfg
        "target_link_libraries(node::node INTERFACE winmm \${_node_rt_builtins})\n")
endif()
string(APPEND _cfg
    "set(node_NODE_SOURCE_MANIFEST \"\${CMAKE_CURRENT_LIST_DIR}/node.exe.extra.manifest\")\n")
file(WRITE "${CURRENT_PACKAGES_DIR}/share/node/node-config.cmake" "${_cfg}")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
