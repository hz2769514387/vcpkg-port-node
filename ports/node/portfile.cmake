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
# 口径要点：
#   * Windows **必须用 clang-cl** 驱动 gyp（`configure.py` 写入 `make_global_settings`，
#     见 patches/0008）：这是 node 24+ 的官方口径（vcbuild.bat 强制 ClangCL），也是
#     ninja 生成器能编过 node 的 DevTools 协议模板的前提。
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
        0001-icu-system-add-icudata.patch
        0002-gyp-ninja-clang-cl-libpath-asm.patch
        0003-gyp-msvs-emulation-rsp-pch-std.patch
        0004-gyp-msvs-settings-language-standard.patch
        0005-gyp-win-tool-utf8-decode.patch
        0006-gyp-ninja-syntax-iterable-guard.patch
        0007-gyp-common-predefines-clang-cl.patch
        0008-configure-shared-syslibs-and-clang-cl.patch
        0009-js2c-normalize-windows-paths.patch
        0010-torque-normalize-windows-paths.patch
        0011-v8-use-vcpkg-simdutf-target.patch
        0012-v8-simdutf-system-include.patch
        0013-v8-compiler-add-descriptor-array-inl.patch
)

# 构建期工具（都用 vcpkg 自带的，不要求系统装）。
vcpkg_find_acquire_program(PYTHON3)
vcpkg_find_acquire_program(NINJA)

# ---------------------------------------------------------------------------
# 编译环境：三平台一律 clang（工程约定）。
#   * Windows：clang-cl（含 MSVC 命令行环境，clang-cl 需要 INCLUDE/LIB）。
#   * Linux / macOS：直接用系统 cc / clang。
# configure.py 通过 CC/CXX 环境变量决定 make_global_settings，进而决定 gyp 的 cl 规则。
# ---------------------------------------------------------------------------
set(_node_cc "")
set(_node_cxx "")
if(VCPKG_TARGET_IS_WINDOWS)
    # 复用仓库的 toolchain 脚本：它发布 NODE_PORT_LLVM_BIN（clang-cl 所在目录）
    # 并设好 MSVC 命令行环境（INCLUDE/LIB/PATH）。
    include("${CMAKE_CURRENT_LIST_DIR}/../../toolchains/clang-cl.cmake")
    set(_node_cc "${NODE_PORT_LLVM_BIN}/clang-cl.exe")
    set(_node_cxx "${NODE_PORT_LLVM_BIN}/clang-cl.exe")
    # gyp 在中文 locale 下的两个已知坑：VS 定位失败 / reg.exe 解码失败。
    set(ENV{GYP_MSVS_VERSION} 2022)
    if(NODE_PORT_VS_INSTALL_ROOT)
        set(ENV{GYP_MSVS_OVERRIDE_PATH} "${NODE_PORT_VS_INSTALL_ROOT}")
    endif()
    set(ENV{DXSDK_DIR} "C:/nonexistent")
    # system-icu 需要 pkg-config（Windows 上由 msys2 提供）。
    vcpkg_acquire_msys(_node_msys PACKAGES pkg-config)
    vcpkg_add_to_path("${_node_msys}/usr/bin")
    set(ENV{PKG_CONFIG} "${_node_msys}/mingw64/bin/pkg-config.exe")
else()
    find_program(_node_c_prog NAMES cc gcc)
    find_program(_node_cxx_prog NAMES c++ g++ clang++)
    set(_node_cc "${_node_c_prog}")
    set(_node_cxx "${_node_cxx_prog}")
    set(ENV{PKG_CONFIG} "pkg-config")
endif()

# shlex 会吃反斜杠：CC/CCX 与 PKG_CONFIG 一律用正斜杠（Windows 上尤其重要）。
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
_node_shared(openssl       openssl     "libcrypto,libssl")
_node_shared(zlib          zlib        "zs")            # Windows+static 的 zlib 库名是 zs
_node_shared(libuv         libuv       "libuv")
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
_node_shared(hdr-histogram hdr-histogram "hdr_histogram_static")

# Linux/macOS 上 zlib 静态库名是 z，不是 zs —— 平台修正。
if(NOT VCPKG_TARGET_IS_WINDOWS)
    string(REPLACE "libname=zs" "libname=z" _node_shared_args "${_node_shared_args}")
    string(REPLACE "libname=hdr_histogram_static" "libname=hdr_histogram" _node_shared_args "${_node_shared_args}")
endif()

# ---------------------------------------------------------------------------
# 1) configure.py：生成 config.gypi（含 shared 归属、make_global_settings、openssl 版本）。
# ---------------------------------------------------------------------------
vcpkg_execute_required_process(
    COMMAND "${PYTHON3}" configure.py
        --with-intl=system-icu
        ${_node_shared_args}
    WORKING_DIRECTORY "${SOURCE_PATH}"
    LOGNAME configure
)

# ---------------------------------------------------------------------------
# 2) gyp → ninja（generator 名就是 `ninja`，没有 `ninja-win`）。
#    VCPKG_SIMDUTF_INCLUDE 供 patches/0011 的 v8 simdutf 目标使用。
# ---------------------------------------------------------------------------
vcpkg_execute_required_process(
    COMMAND "${PYTHON3}" tools/gyp_node.py
        -f ninja
        "-Dpython=${PYTHON3}"
        -Dconfiguring_node=1
        -Dbuild_type=Release
        "-DVCPKG_SIMDUTF_INCLUDE=${_inc}"
    WORKING_DIRECTORY "${SOURCE_PATH}"
    LOGNAME gyp
)

# ---------------------------------------------------------------------------
# 3) ninja 构建可链接库 `libnode`（gyp 目标名，见 node.gyp 的 node_lib_target_name）。
# ---------------------------------------------------------------------------
vcpkg_execute_required_process(
    COMMAND "${NINJA}" -C "${SOURCE_PATH}/out/Release" libnode
    WORKING_DIRECTORY "${SOURCE_PATH}"
    LOGNAME build
)

# ---------------------------------------------------------------------------
# 4) 安装：头文件 + 全部 gyp 静态库 + 手写 CMake 消费配置。
# ---------------------------------------------------------------------------
file(INSTALL "${SOURCE_PATH}/src/" DESTINATION "${CURRENT_PACKAGES_DIR}/include/node"
    FILES_MATCHING PATTERN "*.h" PATTERN "*.hpp")
file(INSTALL "${SOURCE_PATH}/deps/v8/include/" DESTINATION "${CURRENT_PACKAGES_DIR}/include")

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
set(_cfg "# 由 node port 生成：node 的 CMake 消费配置。\n")
string(APPEND _cfg "include(CMakeFindDependencyMacro)\n")
foreach(_dep "OpenSSL" "libuv CONFIG" "llhttp CONFIG" "c-ares CONFIG"
             "unofficial-brotli CONFIG" "ZLIB" "ada CONFIG" "simdjson CONFIG"
             "simdutf CONFIG" "ngtcp2 CONFIG" "zstd CONFIG"
             "ICU COMPONENTS uc i18n data" "unofficial-sqlite3 CONFIG"
             "hdr_histogram CONFIG")
    string(APPEND _cfg "find_dependency(${_dep})\n")
endforeach()
string(APPEND _cfg
    "get_filename_component(_node_prefix \"\${CMAKE_CURRENT_LIST_DIR}/../..\" ABSOLUTE)\n"
    "set(_node_lib \"\${_node_prefix}/lib\")\n")
if(VCPKG_TARGET_IS_WINDOWS)
    string(APPEND _cfg "set(_node_pre \"\")\nset(_node_suf \".lib\")\n")
else()
    string(APPEND _cfg "set(_node_pre \"lib\")\nset(_node_suf \".a\")\n")
endif()
# node 自身口径下需要串起来的静态库全集（gyp 目标）。
set(_node_all_archives
    libnode node_base
    v8_base_without_compiler v8_compiler v8_init v8_initializers
    v8_initializers_slow v8_snapshot v8_libbase v8_libplatform v8_zlib
    abseil highway
    ncrypto ncrypto_engine nbytes merve uvwasi crdtp)
foreach(_a IN LISTS _node_all_archives)
    string(APPEND _cfg
        "if(NOT TARGET node::${_a})\n"
        "  add_library(node::${_a} STATIC IMPORTED)\n"
        "  set_target_properties(node::${_a} PROPERTIES IMPORTED_LOCATION"
        " \"\${_node_lib}/\${_node_pre}${_a}\${_node_suf}\")\n"
        "endif()\n")
endforeach()
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
string(APPEND _cfg
    "target_link_libraries(node::node INTERFACE \${_node_link}"
    " OpenSSL::SSL OpenSSL::Crypto libuv::uv_a c-ares::cares"
    " unofficial::brotli::brotlidec unofficial::brotli::brotlienc"
    " unofficial::brotli::brotlicommon ZLIB::ZLIB ada::ada simdjson::simdjson"
    " simdutf::simdutf ngtcp2::ngtcp2_static zstd::libzstd_static"
    " ICU::uc ICU::i18n ICU::data unofficial::sqlite3::sqlite3"
    " hdr_histogram::hdr_histogram_static nghttp2)\n")
string(APPEND _cfg
    "set(node_NODE_SOURCE_MANIFEST \"\${CMAKE_CURRENT_LIST_DIR}/node.exe.extra.manifest\")\n")
file(WRITE "${CURRENT_PACKAGES_DIR}/share/node/node-config.cmake" "${_cfg}")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")