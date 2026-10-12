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

# ---------------------------------------------------------------------------
# debug 口径：**从未实测过**，所以这里明说，而不是沉默。
#
# 事实（欠账 §1）：CI 全部 triplet 都是 VCPKG_BUILD_TYPE=release，debug 从未被编译过。
# 路线 B 的补丁（PCH、`/std:` 分语言发出、rsp 文本处理）在 debug 下都没验证过，
# V8 的 debug 构建体积/时长约翻倍 + 内存占用显著上升。
#
# 为什么只 WARNING 不 FATAL_ERROR：我们**确实不知道**它能否建起来 ——
# 断言"一定失败"是过度声称，而阻塞一个也许能成功的用法更糟。
# 等哪天真跑通了（或真确认不行），再把这里换成对应的结论。
#
# ★ 来源：1013 评审报告 G6。这条我接受一半 —— 接受"必须显式声明"，
#   不接受"直接报错"（依据不足）。
if(NOT VCPKG_BUILD_TYPE OR VCPKG_BUILD_TYPE STREQUAL "debug")
    message(WARNING
        "node port 的 **debug 口径从未实测**（CI 只跑 release，见欠账清单 §1）。\n"
        "  V8 的 debug 构建体积/时长约翻倍、内存占用显著上升，且路线 B 的几个补丁\n"
        "  （PCH、/std: 分语言发出、rsp 文本处理）在 debug 下没有验证过。\n"
        "  能建起来的话欢迎反馈；建不起来也属预期。要避开：用设了 VCPKG_BUILD_TYPE=release\n"
        "  的 triplet（本仓库的消费端示例工程里，cmake/triplets/ 下有一份可抄的参考）。")
endif()

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
        # v8 自带的 abseil-cpp / highway/src 必须排在 <prefix>/include **之前**，
        # 否则 v8 自己的 absl/*.cc 会编到 vcpkg 那份同名不同版本的 absl/*.h 上。
        # 配一条可执行红线（下面的 scripts/redline-include-order.cmake）：这个顺序
        # 一旦退化，构建当场红，而不是等到编 absl 时才炸。
        "${CMAKE_CURRENT_LIST_DIR}/patches/0015-configure-prepend-v8-bundled-includes.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0016-gyp-ninja-no-thin-archives.patch"
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

# 每一条的 --shared-*-includes 都是 ${_inc}：vcpkg 把所有包的头都装进同一个
# <prefix>/include，单个包没有自己的独立 include 目录（manifest 模式下
# CURRENT_INSTALLED_DIR 还是**整个工程共用**的 vcpkg_installed）。
#
# 顺序问题不在这里解决：configure_library() 按调用顺序 append，而
# configure_openssl() 在 configure.py 里是**最后**被调用的（2641 行），所以靠
# --shared-*-includes 抢不到前排；gyp 对 include_dirs 去重只保留首次出现，
# 一旦 ${_inc} 先出现就永远赢。v8 自带 abseil / highway 的"排到最前"改由
# patches/0015 在 configure.py 末尾整体前插，并用下面的红线断言钉住。
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

# 14 条共享依赖一律用 ${_inc}。v8 自带 abseil / highway 的头文件必须排在 ${_inc}
# **之前**（否则 v8 的 absl/*.cc 会编到 vcpkg 那份同名不同版本的 absl/*.h 上，
# run #17 的 x64-linux / arm64-linux 就是这么死的），这个前插由 patches/0015
# 完成，紧跟在 configure 之后有红线断言检查它真的生效了。
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
# 0) Windows：node.gyp 的 /WHOLEARCHIVE 路径是照 **msvs 生成器** 写的
#    （<(PRODUCT_DIR)/lib/node_base.lib），但 ninja 生成器在 Windows 上把静态库
#    放到 obj/ 下（gyp/generator/ninja.py 里 win 的 type_in_output_root 只有
#    executable / loadable_module / shared_library，static_library 走
#    GypPathToUniqueOutput）。于是 link.exe 报
#    LNK1356: 找不到为延迟加载指定的库 lib/node_base.lib。
#    Linux 那侧本来就写的是 <(obj_dir)/...，macOS 的 static_library 在 output root，
#    只有 Windows 这一条对不上，所以只改 Windows。
#
#    ★ 必须在 **configure.py 之前** 改：改的是 gyp 的**输入**，而 ninja 文件是
#    configure.py 内部调 gyp 生成的；放在后面改，gyp 早就把老路径写进
#    node.exe.rsp 了（试过一次，替换确实生效、链接照样失败）。
#    用 vcpkg_replace_string 而不是补丁：两处字符串各自唯一，不怕上游改行号。
# ---------------------------------------------------------------------------
if(VCPKG_TARGET_IS_WINDOWS)
    vcpkg_replace_string("${SOURCE_PATH}/node.gyp"
        "/WHOLEARCHIVE:<(PRODUCT_DIR)/lib/<(STATIC_LIB_PREFIX)node_base<(STATIC_LIB_SUFFIX)"
        "/WHOLEARCHIVE:<(obj_dir)/<(STATIC_LIB_PREFIX)node_base<(STATIC_LIB_SUFFIX)")
    vcpkg_replace_string("${SOURCE_PATH}/node.gyp"
        "/WHOLEARCHIVE:<(PRODUCT_DIR)/lib/<(STATIC_LIB_PREFIX)v8_base_without_compiler<(STATIC_LIB_SUFFIX)"
        "/WHOLEARCHIVE:<(obj_dir)/tools/v8_gypfiles/<(STATIC_LIB_PREFIX)v8_base_without_compiler<(STATIC_LIB_SUFFIX)")
endif()

# ---------------------------------------------------------------------------
# ★ arm64：把 common.gypi 的 msvs_configuration_platform 从小写 'arm64' 改成 'ARM64'。
#
# 为什么（run #27 的 arm64 实测，第一版把 v8 编起来才暴露）：
#   gyp 的 msvs_emulation.GetArch() 是**大小写敏感的字典查找**：
#       return {"Win32":"x86", "x64":"x64", "ARM64":"arm64"}.get(platform, "x86")
#   而 node 的 common.gypi 在 target_arch=="arm64" 时写的是 **'arm64'（小写）**
#   ⇒ .get('arm64', 'x86') 落到默认值 'x86' ✗
#   ⇒ gyp 的 ninja 生成器认为目标是 x86：
#        ninja.py:2358   command += " -m32" if arch == "x86" else " -m64"
#        ninja.py:405    self.ninja.variable("arch", self.win_env[arch])  → environment.x86
#   ⇒ 编译命令变成 `ninja -t msvc -e environment.x86 -- clang-cl.exe -m32 …`
#     ⇒ v8 的**第一个**编译单元就挂（[1/1922]），报错却只是 `FAILED: ... abort-mode.obj`。
#
#   * x64 不受影响：'x64' 恰好就在那张映射表里。
#   * 上游也从未暴露：官方 Windows 构建走 MSBuild 生成器，不经过 GetArch 这条取 flag 的路径
#     （MSBuild 的 Platform 名大小写不敏感）。
#   * 只用 ninja 生成器 + arm64 才踩得到 —— 正是本 port 的组合。
#
# 为什么用 vcpkg_replace_string 而不是补丁 gyp：
#   ① 这里要修的是 **node 自己的 gyp 输入**（common.gypi），不是 gyp 工具本身；
#   ② 锚点字符串唯一（本文件里只有 x64 与 arm64 两条，值不同），不怕上游挪行号；
#   ③ 少一个需要 rebase 的补丁（评审 G1 也提过这件事）；
#   ④ 字符串找不到时 vcpkg_replace_string 会**报错**，所以上游若自己改成 'ARM64'
#      我们会立刻知道（而不是静默地替换成空）。
# ★ 必须在 configure.py 之前改：改的是 gyp 的**输入**，ninja 文件是 configure.py 内部生成的。
if(VCPKG_TARGET_IS_WINDOWS AND VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
    vcpkg_replace_string("${SOURCE_PATH}/common.gypi"
        "'msvs_configuration_platform': 'arm64'"
        "'msvs_configuration_platform': 'ARM64'")
endif()

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
# 1b) 红线裁判：config.gypi 的 target_defaults.include_dirs 前两条必须是
#     v8 自带的 abseil-cpp 与 highway/src。判定逻辑单独放在 scripts/ 下，
#     这样"故意弄坏一次"的正反两个方向都能真跑（见 .tmp/gen 的验证脚本），
#     而不是只写在注释里说"应该如此"。
# ---------------------------------------------------------------------------
include("${CMAKE_CURRENT_LIST_DIR}/scripts/redline-include-order.cmake")

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

set(_node_ninja_targets libnode)
if("tools" IN_LIST FEATURES)
    list(APPEND _node_ninja_targets node)  # tools 要 node.exe
endif()

vcpkg_execute_required_process(
    COMMAND "${NINJA}" -C "${SOURCE_PATH}/out/Release" ${_node_ninja_jobs} ${_node_ninja_targets}
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
# macOS：gyp 把 static_library 直接放在 out/Release 根下（ninja.py 的 type_in_output_root
# 含 static_library），不在 obj/ 里。不补这一条，装出来的包没有 libnode.a，
# 消费端 ninja 报 "libnode.a ... missing and no known rule to make it"。
file(GLOB _node_archives_root "${SOURCE_PATH}/out/Release/*${_node_lib_suffix}")
list(APPEND _node_archives ${_node_archives_root})
foreach(_a IN LISTS _node_archives)
    file(INSTALL "${_a}" DESTINATION "${CURRENT_PACKAGES_DIR}/lib")
endforeach()

# 记下"本 port 到底装了哪些库"（只要文件名），写进消费配置给符号审计用。
#
# 为什么必须显式给：manifest 模式下 <prefix>/lib 是**整个工程共用**的目录，里面还
# 混着使用者自己声明的库（本仓库的 test 工程就声明了 gtest / fmt / ...）。审计如果
# 把整个目录当成"node 的库"，再拿去和 vcpkg 的 packages 目录比，就成了"自己比自己"
# —— 每次都报一堆 gtest.lib vs gtest/gtest.lib 这种假阳性，闸门等于常红、没人再看。
set(_node_installed_libs "")
foreach(_a IN LISTS _node_archives)
    get_filename_component(_node_lib_name "${_a}" NAME)
    list(APPEND _node_installed_libs "${_node_lib_name}")
endforeach()
list(REMOVE_DUPLICATES _node_installed_libs)
unset(_node_lib_name)

# Windows 平台兼容性清单：消费方也要嵌（缺了一跑退出码 216）。
if(VCPKG_TARGET_IS_WINDOWS)
    file(INSTALL "${SOURCE_PATH}/src/res/node.exe.extra.manifest"
        DESTINATION "${CURRENT_PACKAGES_DIR}/share/node" RENAME node.exe.extra.manifest)
endif()

# ---- 可选 feature：官方测试套件 -------------------------------------------------
# 消费端要跑 node 官方用例，就得有测试套件**以及它运行时会读的那部分源码树**。
# 它是经**安装产物**（share/node/test-suite）给出的，而不是让消费端去 port 源码目录里拿
# —— 依赖方向只有一条：消费端 -> port。
#
# 为什么要连 tools/test.py 一起装：node 官方的 skip / flaky 列表（各套件下的
# *.status）只有 tools/test.py 会读，直接 `node --test` 会把这些状态全丢掉、
# 于是满屏假失败。test.py 用 --shell=<你的 node 嵌入可执行> 驱动，
# 且它按 dirname(sys.argv[0])/.. 推 workspace，所以 tools/ 与 test/ 必须同层。
#
# ★ run #21 的教训：只装 test/ + tools/test.py 不够。官方用例是按"在源码树里跑"
#   写的，有一批会去读套件目录的**兄弟目录**，缺了就是 ENOENT/MODULE_NOT_FOUND
#   （28 个失败里 12 个属于这一类，全是假失败）：
#     doc/node.1、doc/api/cli.md      → test-cli-node-cli-manpage-*、test-cli-node-options-docs、
#                                       test-process-env-allowed-flags-are-documented
#     doc/changelogs/CHANGELOG_V24.md、CHANGELOG.md、src/node_version.h
#                                     → test-release-changelog
#     deps/npm/{package.json,bin/npm-cli.js} → test-npm-version、test-npm-install、test-release-npm
#     deps/corepack/package.json      → test-corepack-version
#     deps/acorn/acorn/package.json   → test-process-versions（该用例第 6 行读它核对 acorn 版本）
#     deps/undici/src/package.json    → test-process-versions（同一用例第 115 行还要读它核对
#                                       undici 版本）★ 2026-10-12 补：只装了 acorn 没装 undici，
#                                       于是这个用例先过第 6 行、再挂在第 115 行（run #23 实测）
#     benchmark/_cli.js               → test-benchmark-cli
#     lib/                            → test-process-load-env-file
#     tools/icu/icu_versions.json     → test-icu-minimum-version
#   doc/ 是这里最贵的一块（约 54 MB），但少了它那几个文档一致性用例永远跑不了。
if("test-suite" IN_LIST FEATURES)
    set(_node_suite "${CURRENT_PACKAGES_DIR}/share/node/test-suite")
    file(INSTALL "${SOURCE_PATH}/test/" DESTINATION "${_node_suite}/test")
    # 整棵 tools/（约 6 MB）：test.py / utils.py 是驱动，tools/icu/icu_versions.json
    # 等是上游用例会读的数据。
    file(INSTALL "${SOURCE_PATH}/tools/" DESTINATION "${_node_suite}/tools")

    # 用例会按相对路径读的兄弟目录（漏一个就多一片假失败）。
    file(INSTALL "${SOURCE_PATH}/benchmark/" DESTINATION "${_node_suite}/benchmark")
    file(INSTALL "${SOURCE_PATH}/doc/" DESTINATION "${_node_suite}/doc")
    file(INSTALL "${SOURCE_PATH}/lib/" DESTINATION "${_node_suite}/lib")
    # .cc 也要装：test-cli-node-options-docs 读 src/node_options.cc 去核对
    # CLI 选项与文档的一致性。只装 .h/.hpp 会让它 ENOENT。
    file(INSTALL "${SOURCE_PATH}/src/" DESTINATION "${_node_suite}/src"
        FILES_MATCHING PATTERN "*.h" PATTERN "*.hpp" PATTERN "*.cc")
    file(INSTALL "${SOURCE_PATH}/CHANGELOG.md" DESTINATION "${_node_suite}")

    # deps/ 只装用例真正引用的那几份：整棵 deps/ 有 400+ MB（openssl 230、v8 94），
    # 而用例只碰这几个包的 package.json / bin / 少量 js。
    # 口径：目录便宜就整目录装，贵的话单文件装（v8 就是单文件，见下面）。
    # 体积记在这里，免得以后有人以为"顺手多加一个"不要钱：
    #   npm 19 MB、undici 3.7 MB、acorn 0.6 MB、corepack ~0.3 MB。
    foreach(_node_dep IN ITEMS npm corepack acorn undici)
        if(EXISTS "${SOURCE_PATH}/deps/${_node_dep}")
            # file(INSTALL <dir> DEST) 把 <dir> 本体拷进 DEST → DEST/<dir>/...
            # 所以 DEST 给 .../deps 而不是 .../deps/<dir>（后者会出 deps/npm/npm/）。
            file(INSTALL "${SOURCE_PATH}/deps/${_node_dep}"
                DESTINATION "${_node_suite}/deps")
        endif()
    endforeach()
    unset(_node_dep)

    # test-icu-minimum-version 读 deps/v8/src/objects/intl-objects.h 去核对
    # ICU 版本与 V8 里硬编码的版本一致。整棵 deps/v8 有 94 MB，只装这一个文件。
    if(EXISTS "${SOURCE_PATH}/deps/v8/src/objects/intl-objects.h")
        file(INSTALL "${SOURCE_PATH}/deps/v8/src/objects/intl-objects.h"
            DESTINATION "${_node_suite}/deps/v8/src/objects")
    endif()
endif()

# ---- 可选 feature：tools（node 可执行 + npm / npx / corepack）--------------------
# vcpkg 的规矩是**按用途分目录**（参考 directx-dxc / vtk / qtbase 这些"复杂 port"）：
#   * 可执行文件 → tools/<port>/  —— **不是** share/。share/ 放 cmake 配置、usage、数据；
#   * 由 <port>-config.cmake 导出变量给使用者 —— directx-dxc 导 DIRECTX_DXC_TOOL 就是这个套路，
#     使用者因此不用去猜路径；
#   * triplet / toolchain **不输出** —— 那是消费端的构建配置（本 port 目录里也没有，
#     使用者在自己的工程里放 triplet，本仓库 test/ 下的 cmake/ 子目录里有一份可抄的参考）。
#
# 布局照 node 官方发行版：可执行 + node_modules/{npm,corepack} + 垫片。
# 垫片两套都装（POSIX sh 与 Windows .cmd）—— 这样 cmd / PowerShell / Git-Bash / 跨平台
# 脚本都能用；它们只用相对路径定位（%~dp0 / $0），不依赖 PATH 上的 node/npm。
if("tools" IN_LIST FEATURES)
    set(_node_tools "${CURRENT_PACKAGES_DIR}/tools/${PORT}")

    if(VCPKG_TARGET_IS_WINDOWS)
        file(INSTALL "${SOURCE_PATH}/out/Release/node.exe" DESTINATION "${_node_tools}")
    else()
        file(INSTALL "${SOURCE_PATH}/out/Release/node" DESTINATION "${_node_tools}"
            FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                            GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
    endif()

    # npm 与 corepack 就是 node 源码树里 vendor 的那两份（发行版同源）
    file(INSTALL "${SOURCE_PATH}/deps/npm/" DESTINATION "${_node_tools}/node_modules/npm")
    file(INSTALL "${SOURCE_PATH}/deps/corepack/" DESTINATION "${_node_tools}/node_modules/corepack")

    foreach(_node_shim IN ITEMS npm npx corepack)
        file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/scripts/${_node_shim}"
            DESTINATION "${_node_tools}" RENAME "${_node_shim}"
            FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                            GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
        file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/scripts/${_node_shim}.cmd"
            DESTINATION "${_node_tools}" RENAME "${_node_shim}.cmd")
    endforeach()

    # 说明：node.exe 用静态 CRT，正常没有需要一起带的 DLL；将来若切动态 CRT，
    # 这里要按 vcpkg 惯例补 vcpkg_copy_tool_dependencies。
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
    "set(_node_lib \"\${_node_prefix}/lib\")\n"
    # 本 port 装进 <prefix>/lib 的库文件名清单。符号审计靠它把"node 的库"和
    # "使用者自己装的库"分开（<prefix>/lib 是共用的，见上面那段说明）。
    "set(node_INSTALLED_LIBRARIES \"${_node_installed_libs}\")\n")

# tools feature 的输出位置也要导出 —— 光把文件装出去、不给变量，使用者只能自己去猜
# 路径（而 vcpkg 的规矩正是"由 config 导出变量"，见 directx-dxc 的 DIRECTX_DXC_TOOL）。
# ★ 2026-10-12 补：之前**只装了文件没导变量**，于是消费端 ctest 的 tools 组一直是
#   "没有 node_EXECUTABLE → 跳过"，静默地什么都没验。
if("tools" IN_LIST FEATURES)
    if(VCPKG_TARGET_IS_WINDOWS)
        # Windows 上给 .cmd 垫片：POSIX sh 脚本在 cmd / PowerShell 下跑不起来。
        set(_node_exe_name "node.exe")
        set(_node_shim_ext ".cmd")
    else()
        set(_node_exe_name "node")
        set(_node_shim_ext "")
    endif()
    # 导出**可移植**的形式：`${_node_prefix}` 相对 + 正斜杠。
    # 不要在这里做 TO_NATIVE_PATH —— 那会把 ${CURRENT_PACKAGES_DIR}（packages 目录）
    # 烤死进配置里，而 vcpkg 之后会把产物搬进真正的安装目录。
    # 需要反斜杠的消费端（`cmd /c` 不认正斜杠的程序名）自己在 find_package 之后转，
    # 见 test/tests/ctest_tools.cmake。
    string(APPEND _cfg
        "set(node_TOOLS_DIR \"\${_node_prefix}/tools/node\")\n"
        "set(node_EXECUTABLE \"\${_node_prefix}/tools/node/${_node_exe_name}\")\n"
        "set(node_NPM \"\${_node_prefix}/tools/node/npm${_node_shim_ext}\")\n"
        "set(node_NPX \"\${_node_prefix}/tools/node/npx${_node_shim_ext}\")\n"
        "set(node_COREPACK \"\${_node_prefix}/tools/node/corepack${_node_shim_ext}\")\n")
endif()

# node 自身口径下需要串起来的静态库全集（gyp 目标）。
set(_node_all_archives
    libnode node_base
    v8_base_without_compiler v8_compiler v8_init v8_initializers
    v8_initializers_slow v8_snapshot v8_libbase v8_libplatform v8_zlib
    abseil highway
    ncrypto ncrypto_engine nbytes merve uvwasi crdtp)
set(_node_archive_links "")
foreach(_a IN LISTS _node_all_archives)
    _node_archive_filename("${_a}" _node_file)
    string(APPEND _cfg
        "if(NOT TARGET node::${_a})\n"
        "  add_library(node::${_a} STATIC IMPORTED)\n"
        "  set_target_properties(node::${_a} PROPERTIES IMPORTED_LOCATION"
        " \"\${_node_lib}/${_node_file}\")\n"
        "endif()\n")
    string(APPEND _node_archive_links " node::${_a}")
endforeach()
unset(_node_file)

string(APPEND _cfg
    "add_library(node::node INTERFACE IMPORTED)\n"
    "set_target_properties(node::node PROPERTIES"
    " INTERFACE_INCLUDE_DIRECTORIES \"\${_node_prefix}/include;\${_node_prefix}/include/node\")\n")
# nghttp2 没有 CMake config 文件，手动建 imported target。
string(APPEND _cfg
    "find_library(_nghttp2_lib nghttp2 HINTS \${_node_lib} REQUIRED)\n"
    "if(NOT TARGET node::nghttp2)\n"
    "  add_library(node::nghttp2 STATIC IMPORTED)\n"
    "  set_target_properties(node::nghttp2 PROPERTIES IMPORTED_LOCATION \"\${_nghttp2_lib}\")\n"
    "endif()\n")
# ---------------------------------------------------------------------------
# ★ 静态库之间的"环"怎么表达 —— 三个平台三条路，每条都有实测或上游原文依据。
#
# node 的 gyp 静态库之间有**真实的环**：libnode ↔ node_base（node_base 的 embed_helpers.cc 调
# node::SnapshotBuilder::GetEmbeddedSnapshotData()，而它由 libnode 的
# src/node_snapshot_stub.cc 提供 —— node_use_node_snapshot!="true" 时 node.gyp 把它塞进
# node_lib）；v8_compiler → v8_base_without_compiler（MachineReprToString / IsSubtype /
# CodeFactory::CEntry 等）。单趟左到右扫描的链接器遇到这种环必须先扫过的 archive 再回头，
# 于是 run #21 的 x64-linux / arm64-linux 在**消费端链接**时炸出几百条 `undefined reference`。
#
# 上游 gyp 是**按平台分开**处理的（tools/gyp/pylib/gyp/generator/make.py）：
#   * Linux/BSD 那条通用命令（159 行与 260 行）把 LD_INPUTS 与 LIBS 一起包进
#     `-Wl,--start-group … -Wl,--end-group`，注释原文："Due to circular dependencies
#     between libraries :(, we wrap the …flags around the entire input list during linking."
#   * macOS 的 LINK_COMMANDS_MAC（209 行起）**不带**这组开关，就是
#     `$(LINK) … -o "$@" $(LD_INPUTS) $(LIBS)`。
#     ★ 这里原先写的是"make.py 的 LINK_COMMANDS_MAC 用的是同一条命令 ⇒ macOS 的 ld64 也认
#       这组开关"——**已被实测证伪**（run #23）：arm64-osx 直接报
#         ld: unknown options: --start-group --end-group
#       抄错的原因：带 --start-group 的 cmd_link（260 行）属于通用（Linux/BSD）命令表，
#       不在 LINK_COMMANDS_MAC 里。
#   * Windows：node.gyp 用 `/WHOLEARCHIVE:node_base.lib` 整库强载（见欠账 §5i）。
#
# 本 port 跟着上游走，并把"手写链接标志"换成 CMake 官方机制：
#   * Windows（MSVC 前端）与 Apple：**平铺**。前者 link.exe 自己会反复扫描整条列表
#     （实测 x64-windows 全绿），后者 ld64 没有 rescan 构造、上游 MAC 命令也是平铺。
#   * 其余（GNU 系：Linux/BSD/SunOS —— CMake 的 Platform/Linux.cmake 与 GNU.cmake 定义了
#     RESCAN）：`$<LINK_GROUP:RESCAN,…>`，即 CMake 官方为"静态库之间有环"提供的构造。
#     ★ 它比手写 "-Wl,--start-group" 强在**去重不会把它拆散**：CMake 知道这些库属于一个组，
#       消费端若又显式列了组内某个库，那次出现会被替换回组内。手写标志没有这层语义 ——
#       消费端只要重复列一个 nghttp2，CMake 去重就会删掉"组内那份"、只留组外那份，
#       而组外那份的位置在 node 的静态库**之前**，单趟扫描早就扫过去了 ⇒ 组内照样解析不了
#       （run #23 的 x64-linux 就是这么挂的：174 条 undefined reference 里 173 条是 nghttp2）。
# ---------------------------------------------------------------------------
string(APPEND _cfg
    "set(_node_archives_link ${_node_archive_links})\n"
    "set(_node_deps_link OpenSSL::SSL OpenSSL::Crypto libuv::uv_a c-ares::cares\n"
    "    unofficial::brotli::brotlidec unofficial::brotli::brotlienc\n"
    "    unofficial::brotli::brotlicommon ZLIB::ZLIB ada::ada simdjson::simdjson\n"
    "    simdutf::simdutf ngtcp2::ngtcp2_static zstd::libzstd_static\n"
    "    ICU::uc ICU::i18n ICU::data unofficial::sqlite3::sqlite3\n"
    "    hdr_histogram::hdr_histogram_static node::nghttp2 llhttp::llhttp_static)\n")
if(VCPKG_TARGET_IS_WINDOWS OR VCPKG_TARGET_IS_OSX)
    # 平铺。Windows：link.exe 反复扫描；Apple：ld64 无 rescan 构造（上游 MAC 命令亦然）。
    string(APPEND _cfg
        "# 平铺：Windows 的 link.exe 会反复扫描；Apple 的 ld64 没有 rescan 构造。\n"
        "# （理由与依据见 port 侧 portfile.cmake 里那段注释。）\n"
        "target_link_libraries(node::node INTERFACE \${_node_archives_link} \${_node_deps_link})\n")
else()
    # GNU 系：用 CMake 官方的 RESCAN 链接组（落到链接器就是 --start-group/--end-group）。
    string(APPEND _cfg
        "# GNU 系链接器是单趟左到右，而 node 的 gyp 静态库之间有环 ⇒ 需要链接组重扫。\n"
        "# 用 CMake 官方的 $<LINK_GROUP:RESCAN,…>（等价于 --start-group/--end-group），\n"
        "# 而不是手写标志：手写的会被 CMake 的「链接项去重」拆散（详见 portfile.cmake）。\n"
        "if(CMAKE_VERSION VERSION_LESS 3.24)\n"
        "  message(FATAL_ERROR\n"
        "    \"本 port 在 GNU 平台的链接接口用了 \$<LINK_GROUP:RESCAN>（CMake 3.24 引入）。 \"\n"
        "    \"请把 CMake 升到 3.24 以上，或改用 Windows / macOS 口径的 triplet。\")\n"
        "endif()\n"
        "# LINK_GROUP 的参数是逗号分隔的，先把两张表 join 起来。\n"
        "set(_node_group_items \${_node_archives_link} \${_node_deps_link})\n"
        "string(REPLACE \";\" \",\" _node_group_items \"\${_node_group_items}\")\n"
        "target_link_libraries(node::node INTERFACE \"\$<LINK_GROUP:RESCAN,\${_node_group_items}>\")\n")
endif()
# macOS 系统 framework：node 自己的 node.gypi 就是这么链的
# （node.gypi:258 `'libraries': [ '-framework CoreFoundation -framework Security' ]`），
# 用来提供 CFArray*/CFDictionary*/CFTimeZone*（abseil 的 cctz 本地时区）与
# SecTrust*/SecItem*（node 的 crypto_context.cc 走钥匙串）。缺了它们 arm64-osx 在
# 消费端链接时就是一堆 `_CFArrayCreateMutable … not found`（run #21 实测）。
if(VCPKG_TARGET_IS_OSX)
    string(APPEND _cfg
        "target_link_libraries(node::node INTERFACE"
        " \"-framework CoreFoundation\" \"-framework Security\")\n")
endif()
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

    # ---------------------------------------------------------------------------
    # ★ 栈大小：**必须**导给消费端，否则使用者的可执行只有 1 MiB 栈。
    #
    # 上游 node.gyp 在 msvs_settings.VCLinkerTool 里设了
    #     'StackReserveSize': 0x800000
    # 并写着理由（原文）："By default, the MSVC linker only reserves 1 MiB of stack memory
    # for each thread, whereas other platforms typically allow much larger stack memory
    # sections. We raise the limit to make it more consistent across platforms and to
    # support the few use cases that require large amounts of stack memory, without having
    # to modify the node binary."
    #
    # 问题在于：那条设置只作用于 **gyp 自己生成的 node 可执行**。我们交付的是**静态库**，
    # 可执行是消费端（本仓库的 test/app 也一样）用自己的 CMake 链出来的 —— 它拿不到这条
    # 设置，于是栈就是链接器默认的 1 MiB。而 V8 / inspector 有一批路径真的要用更大的栈。
    #
    # ★ 实测（2026-10-12，本机）：`test-stack-size-limit` 在 1 MiB 栈下以
    #   `0xC00000FD (STATUS_STACK_OVERFLOW)` 挂掉（该用例的原话：默认 --stack-size=984 只比
    #   1 MiB 略小，稍微调大就会撞上；上游把它放到 8 MiB 就是为了这个）。
    #   实测对照：我们的 exe `0x100000`（1 MiB）vs 官方 node.exe `0x800000`（8 MiB）。
    #   ⇒ 这条欠账之前被两条 skip（test-stack-size-limit / test-debugger-probe-late-resolution）
    #     盖住了 —— 那正是 §5b 禁止的做法。现在把它变成导出的使用要求，那两条 skip 已撤销。
    #
    # 数值**从 node.gyp 里读**，不写死：上游若改了，这里跟着变；若那条设置被挪走/改名，
    # 我们宁可当场 configure 失败，也不要在这里留一个会悄悄过期的魔数。
    # ---------------------------------------------------------------------------
    file(READ "${SOURCE_PATH}/node.gyp" _node_gyp_text)
    string(REGEX MATCHALL "'StackReserveSize'[^0-9]*0x[0-9A-Fa-f]+"
        _node_stack_hits "${_node_gyp_text}")
    list(LENGTH _node_stack_hits _node_stack_hit_count)
    if(NOT _node_stack_hit_count EQUAL 1)
        message(FATAL_ERROR
            "在 node.gyp 里找到 ${_node_stack_hit_count} 处 'StackReserveSize'（期望恰好 1 处）。\n"
            "上游重构了这条 msvs 设置 —— 消费端的栈大小使用要求要跟着改，"
            "不要在这里猜一个数字（见 portfile.cmake 里那段注释）。")
    endif()
    string(REGEX MATCH "0x[0-9A-Fa-f]+" _node_stack_reserve "${_node_stack_hits}")
    unset(_node_gyp_text)
    unset(_node_stack_hits)
    unset(_node_stack_hit_count)

    string(APPEND _cfg
        "# 消费端可执行必须拿到 node 同款的 ${_node_stack_reserve} 栈"
        "（取自 node.gyp 的 msvs_settings.VCLinkerTool.StackReserveSize）。\n"
        "# 不导出的话链接器只给 1 MiB —— 实测 test-stack-size-limit 会以\n"
        "# 0xC00000FD(STATUS_STACK_OVERFLOW) 挂掉（V8 / inspector 有路径要用更大的栈）。\n"
        "# target_link_options 需要 CMake ≥ 3.13。\n"
        "target_link_options(node::node INTERFACE \"/STACK:${_node_stack_reserve}\")\n")
endif()
# 装了 test-suite feature 就导出官方套件的根目录（tools/test.py 以它的父目录为 workspace）。
string(APPEND _cfg
    "if(EXISTS \"\${CMAKE_CURRENT_LIST_DIR}/test-suite/tools/test.py\")\n"
    "  set(node_TEST_SUITE_DIR \"\${CMAKE_CURRENT_LIST_DIR}/test-suite\")\n"
    "endif()\n")
file(WRITE "${CURRENT_PACKAGES_DIR}/share/node/node-config.cmake" "${_cfg}")

# ---------------------------------------------------------------------------
# node-config-version.cmake —— 让 `find_package(node 24.21.0 CONFIG)` 能工作，
# 并给消费端一个 node_VERSION 变量。
#
# ★ 来源：1013 评审报告把它列为【严重】（S2）。**这条我接受** —— vcpkg 要求提供
#   CMake config 的端口必须同时提供 version 文件，而缺了它的直接后果就是
#   `find_package(node 24.21.0 CONFIG)` 直接失败、`node_VERSION` 为空。
#
# ★ 但**不接受**评审建议里的 `ARCH_INDEPENDENT`：我们交付的是**按架构编译的静态库**，
#   关掉架构校验会让消费端可能匹配到别的架构那份；这里保留 CMake 默认的架构检查。
#   兼容性用 SameMajorVersion（Node 的 embedder API 不保证跨大版本 ABI 稳定）。
# ---------------------------------------------------------------------------
if(VERSION STREQUAL "")
    message(FATAL_ERROR
        "portfile 里拿不到 VERSION（vcpkg 应从 vcpkg.json 注入）—— "
        "version 文件会写成 0.0.0，宁可在这里红。")
endif()
# ★ 为什么要显式给 CMAKE_SIZEOF_VOID_P：portfile 的 CMake 进程**没有配置过编译器**，
#   这个变量是空的；而 write_basic_package_version_file 的模板在"生成时它也为空"时会
#   直接 `return()` —— 实测：**悄悄跳过整段架构校验**，等于变相 ARCH_INDEPENDENT。
#   我们交付的是按架构编译的静态库，所以按目标架构把指针宽度告诉它，让校验真正生效
#   （否则消费端拿错架构那份，报错会晚到链接期且很难读）。
set(CMAKE_SIZEOF_VOID_P 8)
if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x86" OR VCPKG_TARGET_ARCHITECTURE STREQUAL "arm")
    set(CMAKE_SIZEOF_VOID_P 4)
endif()
include(CMakePackageConfigHelpers)
write_basic_package_version_file(
    "${CURRENT_PACKAGES_DIR}/share/node/node-config-version.cmake"
    VERSION "${VERSION}"
    COMPATIBILITY SameMajorVersion)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
