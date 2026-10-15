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
# ★ 本 port 是**自包含**的：目录里只有 portfile / vcpkg.json / patches / scripts / usage，
#   不引用 port 目录外的任何文件，也不自带 triplet / toolchain（那是消费端的构建配置）。
#
# 口径要点（2026-10-14 重构后的对外契约）：
#   * **消费方用标准 triplet 就行**：Windows 的 MSVC 命令行环境（INCLUDE/LIB/PATH）与
#     clang-cl 的发现都由**本 port 自己**完成（scripts/node-msvc-env.cmake +
#     vcpkg_find_acquire_program(CLANG)），不再要求消费方复刻任何工具链/triplet。
#     本机实测（干净 shell + 标准 triplet）：vcpkg 会给**依赖**摆好 MSVC 环境
#     （c-ares/openssl 双份都编过）；port 自己的 gyp 构建经 scripts/node-msvc-env.cmake
#     同样自摆。参考写法仍在 `test/`（它只是示例，不再是"必抄手册"）。
#   * Windows **必须用 clang-cl 编 node**（node 24+ 的官方口径，vcbuild.bat 强制），
#     这也是 ninja 生成器能编过 node 的 DevTools 协议模板的前提。
#   * 依赖全部走 vcpkg（`--shared-*`），不编 node 内嵌副本；ICU 走 system-icu。
#   * **构建口径跟随 triplet**：`VCPKG_BUILD_TYPE` 未设（双份 triplet）⇒ Release + Debug
#     都编，debug 库按 vcpkg 惯例进 `debug/lib`；设 `release` ⇒ 只编 Release；
#     设 `debug` ⇒ 直接 FATAL（debug-only 会让 brotli 等上游 port 的 vcpkg_copy_tools
#     布局 BUILD_FAILED，且 release 消费方无库可链）。消费方 Debug/Release 都原生可用。
#   * **CRT 跟随 triplet**：`VCPKG_CRT_LINKAGE` static ⇒ /MT(/MTd)，dynamic ⇒ /MD(/MDd)。
#     node 上游只通过 `--shared` 支持动态 CRT（那会同时把库变成 DLL），我们补上
#     force_dynamic_crt 通路（见下面 CRT 段）让静态库 + 动态 CRT 也能编。
#   * 交付物是**静态库**：请求动态库时报错（本 port 只实现静态形态；动态交付需要另一套
#     triplet/口径，属"未实现"而非"不可能"——Debian/conda 的 --shared 先例存在）。
#   * 交叉编译走 node 自己的机制（`--dest-cpu` + `--no-cross-compiling`），
#     目前覆盖 macOS（arm64 宿主 × x64-osx；工具/测试经 Rosetta 运行）—— 详见 0.5 段。

vcpkg_check_linkage(ONLY_STATIC_LIBRARY)

# ---------------------------------------------------------------------------
# 构建计划：按 VCPKG_BUILD_TYPE 决定编哪几份（vcpkg 正统做法，与 ace/activemq-cpp 等
# 官方双份 port 同款判据）。这里**不设** = 双份（release + debug），是 vcpkg 的默认。
#
# 为什么 debug-only 直接 FATAL 而不是"那就只编 debug"：
#   ① 依赖侧：VCPKG_BUILD_TYPE=debug 是 debug-**only**，vcpkg 会把可执行类产物放进
#      debug/tools/，而 brotli 等上游 port 的 vcpkg_copy_tools 在 tools/ 找 ⇒
#      BUILD_FAILED（2026-10-14 arm64-linux 实测）。这类上游 port 不止一个。
#   ② 消费侧：debug-only 安装没有 release 库，Release 消费方无库可链。
#   要 debug 的正确姿势是**不设** VCPKG_BUILD_TYPE 的双份 triplet。
# ---------------------------------------------------------------------------
set(_node_configs "")
if(NOT DEFINED VCPKG_BUILD_TYPE OR VCPKG_BUILD_TYPE STREQUAL "")
    set(_node_configs Release Debug)
    message(STATUS "node port: VCPKG_BUILD_TYPE 未设 ⇒ 双份构建（Release → lib/，Debug → debug/lib/）")
elseif(VCPKG_BUILD_TYPE STREQUAL "release")
    set(_node_configs Release)
    message(STATUS "node port: VCPKG_BUILD_TYPE=release ⇒ 只编 Release（lib/）")
elseif(VCPKG_BUILD_TYPE STREQUAL "debug")
    message(FATAL_ERROR
        "node port 不支持 debug-only triplet（VCPKG_BUILD_TYPE=debug）：\n"
        "  1) 依赖侧：debug-only 布局会让 brotli 等上游 port 的 vcpkg_copy_tools 直接\n"
        "     BUILD_FAILED（2026-10-14 arm64-linux 实测：SEARCH_DIR .../tools/brotli must be a directory）；\n"
        "  2) 消费侧：debug-only 安装没有 release 库，Release 消费方无库可链。\n"
        "  要 debug 的正确姿势：用**不设** VCPKG_BUILD_TYPE 的双份 triplet\n"
        "  （如 vcpkg 自带的 x64-windows-static / x64-linux），本 port 会编两份并按\n"
        "  vcpkg 惯例装进 lib/ 与 debug/lib/，消费方 Debug/Release 都原生可用。")
else()
    message(FATAL_ERROR
        "node port: 认不出的 VCPKG_BUILD_TYPE='${VCPKG_BUILD_TYPE}'（只认 release / debug / 不设）。")
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
        "${CMAKE_CURRENT_LIST_DIR}/patches/0017-gyp-ninja-clang-cl-arm64-target.patch"
        # 给**测试驱动** tools/test.py 加一行诊断：失败用例一律打印退出码（含十六进制）。
        # 起因：CI 上 Windows 出现"零输出 + 非零退出"的静默失败，上游只在 crash/timeout
        # 时才打印退出码 ⇒ 日志里没有任何可判读的线索（run #29~#31 实测）。
        # 它只影响 test-suite feature 里那份测试驱动，与库本体无关。
        "${CMAKE_CURRENT_LIST_DIR}/patches/0018-test-py-print-exit-code.patch"
        # gyp 的 msvs_emulation 还有三处 decode("utf-8")（reg.exe 查询、`cmd /c set`
        # 环境快照、where cl.exe）—— 0005 只修了 win_tool.py 的。中文 Windows 上
        # PATH 里一个非 ASCII 目录（本机实测：`微信web开发者工具` 的 GBK 字节 0xd0）
        # 就让 GenerateEnvironmentFiles 当场 UnicodeDecodeError，而这是**每一次**
        # Windows 构建都会走的路。同类问题、同款修法（errors="replace"）。
        "${CMAKE_CURRENT_LIST_DIR}/patches/0019-gyp-msvs-emulation-utf8-decode.patch"
)

# 构建期工具（都用 vcpkg 自带的，不要求系统装）。
vcpkg_find_acquire_program(PYTHON3)
vcpkg_find_acquire_program(NINJA)

# ---------------------------------------------------------------------------
# 编译环境。
#   * Windows：clang-cl（node 24+ 官方口径）。**编译器与 MSVC 命令行环境都由本 port
#     自己摆**（2026-10-14 重构：原来靠消费端 triplet 交接，见 scripts/node-msvc-env.cmake
#     头部说明）。使用者因此可以用标准 triplet，不需要复刻任何工具链。
#   * Linux / macOS：用系统 cc / c++。
# configure.py 通过 CC/CXX 环境变量决定 make_global_settings，进而决定 gyp 的 cl 规则。
# ---------------------------------------------------------------------------
set(_node_cc "")
set(_node_cxx "")
set(_node_clang_cl_arg "")
set(_node_rt_builtins_lib "")   # Windows：clang 的 compiler-rt 内建库（要装进产物里）
set(_node_dynamic_crt 0)        # Windows：CRT 口径（1 = /MD）

if(VCPKG_TARGET_IS_WINDOWS)
    # port 自己把 MSVC 命令行环境摆好：nmake/PATH、INCLUDE/LIB（MSVC + SDK）、
    # rc.exe/mt.exe 就位，并发布 NODE_PORT_VS_INSTALL_ROOT / NODE_PORT_TARGET_ARCH。
    # 依赖侧不需要这些（vcpkg 自己给依赖摆），这是给**本 port 的 gyp/ninja 构建**用的。
    include("${CMAKE_CURRENT_LIST_DIR}/scripts/node-msvc-env.cmake")

    # ---- clang-cl 发现（七级回退）---------------------------------------------
    # ① NODE_PORT_LLVM_BIN（显式覆盖，CI 用它钉 runner 上的 VS LLVM 布局）
    # ② NODE_PORT_LLVM_ROOT（指向 LLVM 安装根，含 x64/bin 或 bin/）
    # ③ VS 自带 LLVM，**按宿主架构挑**（node-msvc-env.cmake 已解析出
    #    NODE_PORT_VS_INSTALL_ROOT 与 NODE_PORT_HOST_ARCH）：VS 会同时装
    #    x64 与 ARM64 两套（Llvm/x64、Llvm/ARM64），必须按宿主挑。
    # ④ 独立 LLVM 发行版（LLVM_ROOT / LLVMInstallDir / Program Files 下两个固定位置）
    # ⑤ vcpkg_find_acquire_program(CLANG) —— vcpkg 自带的编译器获取器（openssl/nettle/
    #    libass/libxt/gmp/vcpkg-make 六个官方 port 在用），必要时下载 LLVM。
    #    ★ 它在 Windows 上**写死搜 x64**（VCINSTALLDIR/Tools/Llvm/x64/bin），
    #    arm64 宿主上会拿错 ⇒ 所以它排在③之后，只当前面全落空时兜底。
    #    它找到的是 `clang`（gcc 驱动），与 clang-cl.exe 同目录 ⇒ 取其目录拼。
    # ⑥ $ENV{CC} 匹配 clang-cl → ⑦ find_program(clang-cl)
    set(_node_clang_cl "")
    if(DEFINED NODE_PORT_LLVM_BIN AND NOT NODE_PORT_LLVM_BIN STREQUAL ""
       AND EXISTS "${NODE_PORT_LLVM_BIN}/clang-cl.exe")
        set(_node_clang_cl "${NODE_PORT_LLVM_BIN}/clang-cl.exe")
    endif()
    if(_node_clang_cl STREQUAL "" AND DEFINED NODE_PORT_LLVM_ROOT AND NOT NODE_PORT_LLVM_ROOT STREQUAL "")
        foreach(_node_llvm_cand "${NODE_PORT_LLVM_ROOT}/x64/bin/clang-cl.exe"
                                 "${NODE_PORT_LLVM_ROOT}/bin/clang-cl.exe")
            if(EXISTS "${_node_llvm_cand}")
                set(_node_clang_cl "${_node_llvm_cand}")
                break()
            endif()
        endforeach()
        unset(_node_llvm_cand)
    endif()
    if(_node_clang_cl STREQUAL "" AND DEFINED NODE_PORT_VS_INSTALL_ROOT
       AND NOT NODE_PORT_VS_INSTALL_ROOT STREQUAL "")
        # 宿主架构优先，再 x64，再 ARM64（找到后统一过架构核对）。
        set(_node_llvm_arch_order "")
        if(DEFINED NODE_PORT_HOST_ARCH)
            list(APPEND _node_llvm_arch_order "${NODE_PORT_HOST_ARCH}")
        endif()
        list(APPEND _node_llvm_arch_order x64 ARM64)
        foreach(_node_llvm_arch IN LISTS _node_llvm_arch_order)
            if(EXISTS "${NODE_PORT_VS_INSTALL_ROOT}/VC/Tools/Llvm/${_node_llvm_arch}/bin/clang-cl.exe")
                set(_node_clang_cl
                    "${NODE_PORT_VS_INSTALL_ROOT}/VC/Tools/Llvm/${_node_llvm_arch}/bin/clang-cl.exe")
                break()
            endif()
        endforeach()
        unset(_node_llvm_arch_order)
        unset(_node_llvm_arch)
    endif()
    if(_node_clang_cl STREQUAL "")
        foreach(_node_llvm_cand
            "$ENV{LLVM_ROOT}/bin/clang-cl.exe"
            "$ENV{LLVMInstallDir}/bin/clang-cl.exe"
            "C:/Program Files/LLVM/bin/clang-cl.exe"
            "C:/Program Files (x86)/LLVM/bin/clang-cl.exe")
            if(EXISTS "${_node_llvm_cand}")
                set(_node_clang_cl "${_node_llvm_cand}")
                break()
            endif()
        endforeach()
        unset(_node_llvm_cand)
    endif()
    if(_node_clang_cl STREQUAL "")
        # vcpkg_find_acquire_program 只在没有显式覆盖时才调用（它可能触发下载）。
        vcpkg_find_acquire_program(CLANG)
        if(DEFINED CLANG AND NOT CLANG STREQUAL "")
            get_filename_component(_node_clang_bin "${CLANG}" DIRECTORY)
            if(EXISTS "${_node_clang_bin}/clang-cl.exe")
                set(_node_clang_cl "${_node_clang_bin}/clang-cl.exe")
            endif()
            unset(_node_clang_bin)
        endif()
    endif()
    if(_node_clang_cl STREQUAL "" AND DEFINED ENV{CC} AND "$ENV{CC}" MATCHES "clang-cl")
        set(_node_clang_cl "$ENV{CC}")
    endif()
    if(_node_clang_cl STREQUAL "")
        find_program(_node_clang_cl NAMES clang-cl)
    endif()
    if(NOT _node_clang_cl)
        message(FATAL_ERROR
            "Windows 上构建本 port 需要 clang-cl（node 24+ 官方口径）。\n"
            "本 port 会按以下顺序自己找：NODE_PORT_LLVM_BIN → NODE_PORT_LLVM_ROOT →\n"
            "VS 自带 LLVM（按宿主架构）→ 独立 LLVM → vcpkg_find_acquire_program(CLANG)\n"
            "（必要时下载）→ $ENV{CC} → PATH。全都没命中。请装 Visual Studio 的\n"
            "「C++ Clang 编译器」组件（或独立 LLVM），或把 NODE_PORT_LLVM_ROOT 指向\n"
            "LLVM 安装根目录。注意：只装「Clang 工具」是只有 clang-format/clang-tidy 的，\n"
            "没有 clang-cl。")
    endif()
    # ★ 按宿主架构核对：VS 会同时装 x64 与 ARM64 两套 LLVM（Llvm/x64、Llvm/ARM64），
    #   在 x64 宿主上拿到 ARM64 那份 ⇒ 一执行就是 WinError 216（"%1 与你运行的 Windows
    #   版本不兼容"），而报错点在 configure.py 的宏探测里、离真因极远（探针实测）。
    #   反过来 arm64 宿主上拿到 x64 那份更糟：能跑（仿真）但会编出 x64 的 node 库，
    #   直到链接期才 machine type 冲突（run #29 同款）。所以两个方向都拦。
    #   host 架构由 scripts/node-msvc-env.cmake 解析（NODE_PORT_HOST_ARCH）。
    if(DEFINED NODE_PORT_HOST_ARCH AND EXISTS "${_node_clang_cl}")
        get_filename_component(_node_clang_cl_parent "${_node_clang_cl}" DIRECTORY)
        get_filename_component(_node_clang_cl_llvm_arch "${_node_clang_cl_parent}" DIRECTORY)
        get_filename_component(_node_clang_cl_llvm_arch "${_node_clang_cl_llvm_arch}" NAME)
        if(_node_clang_cl_llvm_arch MATCHES "^(x64|ARM64|arm64)$"
           AND NOT _node_clang_cl_llvm_arch STREQUAL "${NODE_PORT_HOST_ARCH}")
            message(FATAL_ERROR
                "找到的 clang-cl 是 ${_node_clang_cl_llvm_arch} 架构（${_node_clang_cl}），"
                "但本机宿主架构是 ${NODE_PORT_HOST_ARCH} ⇒ 编译产物架构会错。\n"
                "VS 同时装了两套 LLVM 时按目录名挑会挑错。请设置 NODE_PORT_LLVM_ROOT\n"
                "指向 ${NODE_PORT_HOST_ARCH} 那一套（<VS>/VC/Tools/Llvm/${NODE_PORT_HOST_ARCH}）。")
        endif()
        unset(_node_clang_cl_parent)
        unset(_node_clang_cl_llvm_arch)
    endif()
    message(STATUS "node port: clang-cl = ${_node_clang_cl}")

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

    # vcpkg 依赖的头文件加入 INCLUDE：gyp 的非 v8 目标（如 js2c）也需要 simdutf.h
    # —— 不加这里，每个目标都要单独配路径。（头文件两边共用 release 侧 include/。）
    # （MSVC/SDK 的 INCLUDE/LIB 已由 scripts/node-msvc-env.cmake 摆好。）
    set(ENV{INCLUDE} "${CURRENT_INSTALLED_DIR}/include;$ENV{INCLUDE}")

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

    # ---- CRT 口径：跟随 VCPKG_CRT_LINKAGE --------------------------------------
    # node 上游只有 `--shared` 一条路能切动态 CRT（那会把库也变成 DLL），静态库交付下
    # 想要 /MD 必须自己补通路。本机实测的两件套（2026-10-14，探针：common.gypi 打条件 +
    # 环境变量 ⇒ 77 个编译单位全部从 /MT 翻到 /MD）：
    #   ① configure.py 的 force_dynamic_crt 赋值改成"或读环境变量"（下面 replace_string）；
    #   ② common.gypi 的两处 MSVC_runtimeType 条件加上 force_dynamic_crt != 1
    #      （v8 侧 toolchain.gypi 本来就认 force_dynamic_crt，不用改）。
    # 静态 CRT（默认）时环境变量不设，两处 replace 的语义与上游完全一致（0 即假）。
    if(VCPKG_CRT_LINKAGE STREQUAL "dynamic")
        set(_node_dynamic_crt 1)
        set(ENV{NODE_PORT_FORCE_DYNAMIC_CRT} "1")
        message(STATUS "node port: VCPKG_CRT_LINKAGE=dynamic ⇒ node 按动态 CRT（/MD、/MDd）编")
    else()
        message(STATUS "node port: VCPKG_CRT_LINKAGE=${VCPKG_CRT_LINKAGE} ⇒ node 按静态 CRT（/MT、/MTd）编")
    endif()

    # ---- compiler-rt 内建库：编出来、装进产物 ------------------------------------
    # node 的 clang-cl 产物引用 __cpu_model（__builtin_cpu_supports），而消费端链接
    # （不管 cl.exe 还是 lld-link）都不会自动带上 clang 的 compiler-rt —— 驱动那套
    # 自动挂载只在 clang 驱动直链时成立。原来靠消费端工具链把绝对路径塞进 cache 变量
    # （NODE_PORT_CLANG_RT_BUILTINS），那正是被本次重构干掉的 543 行之一。
    # 现在由 port 把 clang_rt.builtins-<arch>.lib 装进 <prefix>/lib（与 debug/lib），
    # 导出配置按绝对路径链 —— 消费端机器上没有匹配的 LLVM（含二进制缓存还原场景）
    # 也能链。文件数百 KB，按架构各一份，互不冲突（没有同名 vcpkg port）。
    execute_process(
        COMMAND "${_node_cc}" --print-resource-dir
        OUTPUT_VARIABLE _node_clang_resource_dir
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE)
    if(NOT _node_clang_resource_dir STREQUAL "")
        file(TO_CMAKE_PATH "${_node_clang_resource_dir}" _node_clang_resource_dir)
        set(_node_rt_cand
            "${_node_clang_resource_dir}/lib/windows/clang_rt.builtins-${_node_rt_arch}.lib")
        if(EXISTS "${_node_rt_cand}")
            set(_node_rt_builtins_lib "${_node_rt_cand}")
            message(STATUS "node port: compiler-rt 内建库 ${_node_rt_cand}")
        else()
            message(FATAL_ERROR
                "在 clang 资源目录里找不到 compiler-rt 内建库：\n"
                "  ${_node_rt_cand}\n"
                "（--print-resource-dir = ${_node_clang_resource_dir}）。\n"
                "缺它消费端链接必挂 __cpu_model。请检查 clang-cl 安装是否完整。")
        endif()
    else()
        message(FATAL_ERROR "clang-cl --print-resource-dir 没有输出（${_node_cc}）")
    endif()
    unset(_node_clang_resource_dir)
    unset(_node_rt_cand)
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
# ★ PKG_CONFIG_PATH 不在这里设 —— 构建循环里按口径切（ICU 走 pkg-config，
#   debug 构建必须用 debug 侧的 pkgconfig，见循环内注释）。

# ---------------------------------------------------------------------------
# prepare_shared：把 vcpkg 依赖以 --shared-<lib> 的形式喂给 configure.py。
# 库名必须写 vcpkg 包里真实的库文件名（不含扩展名），Windows 静态口径有若干差异
# （zlib → zs；brotli 去 lib 前缀；openssl 保留 lib 前缀）。
#
# ★ 双份构建时 Debug 那份要链**依赖的 debug 库**（${CURRENT_INSTALLED_DIR}/debug/lib），
#   否则 _ITERATOR_DEBUG_LEVEL 对不上（依赖 debug 库是 /MTd 或 /MDd）。
#   头文件两边共用 release 侧的 include/（vcpkg 双份布局里 debug/ 只有 lib）。
# ---------------------------------------------------------------------------
set(_inc "${CURRENT_INSTALLED_DIR}/include")

# 每一条的 --shared-*-includes 都是 ${_inc}：vcpkg 把所有包的头都装进同一个
# <prefix>/include，单个包没有自己的独立 include 目录（manifest 模式下
# CURRENT_INSTALLED_DIR 还是**整个工程共用**的 vcpkg_installed）。
#
# 顺序问题不在这里解决：configure_library() 按调用顺序 append，而
# configure_openssl() 在 configure.py 里是**最后**被调用的（2641 行），所以靠
# --shared-*-includes 抢不到前排；gyp 对 include_dirs 去重只保留首次出现，
# 一旦 ${_inc} 先出现就永远赢。v8 自带 abseil / highway 的"排到最前"改由
# patches/0015 在 configure.py 末尾整体前插，并用下面的红线断言钉住。
function(_node_shared_args _out _libdir)
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
    set(_args "")
    foreach(_node_spec
        "openssl|${_openssl_lib}"
        "zlib|${_zlib_lib}"
        "libuv|${_libuv_lib}"
        "cares|cares"
        "brotli|brotlidec,brotlienc,brotlicommon"
        "nghttp2|nghttp2"
        "ngtcp2|ngtcp2"
        "http-parser|llhttp"
        "zstd|zstd"
        "simdjson|simdjson"
        "simdutf|simdutf"
        "sqlite|sqlite3"
        "ada|ada"
        "hdr-histogram|${_hdrhist_lib}")
        string(REPLACE "|" ";" _node_pair "${_node_spec}")
        list(GET _node_pair 0 _node_opt)
        list(GET _node_pair 1 _node_libnames)
        list(APPEND _args
            "--shared-${_node_opt}"
            "--shared-${_node_opt}-includes=${_inc}"
            "--shared-${_node_opt}-libpath=${_libdir}"
            "--shared-${_node_opt}-libname=${_node_libnames}")
    endforeach()
    set(${_out} "${_args}" PARENT_SCOPE)
endfunction()

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
#    ★ 必须在 **configure.py 之前**改：改的是 gyp 的**输入**，而 ninja 文件是
#    configure.py 内部调 gyp 生成的；放在后面改，gyp 早就把老路径写进
#    node.exe.rsp 了（试过一次，替换确实生效、链接照样失败）。
#    用 vcpkg_replace_string 而不是补丁：两处字符串各自唯一，不怕上游改行号。
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
# ★ CRT 通路（见上面 CRT 段的两件套，本机实测过）：
#   ① configure.py：force_dynamic_crt 改为"或读环境变量 NODE_PORT_FORCE_DYNAMIC_CRT"；
#   ② common.gypi：两处 MSVC_runtimeType 条件从只看 node_shared 改成
#      "node_shared != true 且 force_dynamic_crt != 1"。
#   静态 CRT 时环境变量不设、条件语义与上游逐字等价（force_dynamic_crt=0 即假）。
#   两条都做 anchored replace：上游改了写法会当场红，不会静默失效。
#   上游化候选：node 官方只认 --shared 才切动态 CRT，这个补丁是"静态库 + 动态 CRT"
#   的最小通路（Electron 把 use_system_* 上游化的同款思路）。
vcpkg_replace_string("${SOURCE_PATH}/configure.py"
    "o['variables']['force_dynamic_crt'] = 1 if options.shared else 0"
    "o['variables']['force_dynamic_crt'] = 1 if (options.shared or os.environ.get('NODE_PORT_FORCE_DYNAMIC_CRT') == '1') else 0")
if(VCPKG_TARGET_IS_WINDOWS)
    # 两处条件各用不同的尾锚（MSVC_runtimeType 的值不同），所以两条 replace 互不干扰。
    vcpkg_replace_string("${SOURCE_PATH}/common.gypi"
        "['node_shared != \"true\"', {\n              'MSVC_runtimeType': 1,    # MultiThreadedDebug (/MTd)"
        "['node_shared != \"true\" and force_dynamic_crt != 1', {\n              'MSVC_runtimeType': 1,    # MultiThreadedDebug (/MTd)")
    vcpkg_replace_string("${SOURCE_PATH}/common.gypi"
        "['node_shared != \"true\"', {\n              'MSVC_runtimeType': 0    # MultiThreaded (/MT)"
        "['node_shared != \"true\" and force_dynamic_crt != 1', {\n              'MSVC_runtimeType': 0    # MultiThreaded (/MT)")
endif()

# ---------------------------------------------------------------------------
# 0.5) 交叉编译：目标架构与宿主不同时，用 node 自己的机制声明目标架构。
#
# 为什么必须传（2026-10-14 run #39 x64-osx 实测）：不传的话 configure.py 的
# target_arch 静默等于宿主架构 —— arm64 宿主机上整棵 node 按 arm64 编，再去链
# vcpkg 装出来的 x86_64 外部库，死在
#   ld: symbol(s) not found for architecture arm64（icu_78::… 一片 undefined）
# 而且报错离真因极远（先编完 1900 个目标才在链接处炸）。
#
# 两个 flag 是一套，缺一不可（都查过 node 24.21.0 源码确认）：
#   --dest-cpu=<arch> → configure_arch() 设 target_arch → common.gypi 的
#     `['OS=="mac"', … target_arch=="x64" → xcode_settings.ARCHS=['x86_64']]`
#     → gyp 的 xcode 仿真把它翻译成每条编译/链接命令的 `-arch x86_64`。
#   --no-cross-compiling → 不置 GYP_CROSSCOMPILE。一旦置位，gyp 的
#     xcode_emulation 会**跳过** ARCHS→-arch 的翻译（注释原话：假设架构由
#     CC_host/CXX_host/CC_target/CXX_target 提供），且
#     want_separate_host_toolset=1 会把构建工具切成**宿主**架构 —— 而工具
#     同样要链 vcpkg 的**目标**架构外部库（gen-regexp-special-case 链 ICU），
#     又是 not found。不置位则 ninja 生成器直接忽略 host toolset
#     （generator_supports_multiple_toolsets = CrossCompileRequested()），
#     全部按目标架构编；arm64 宿主上这些 x86_64 工具与测试经 Rosetta 2 运行
#     （workflow 里有守卫步骤确保 Rosetta 装着）。
#
# 只覆盖 macOS：Linux/Windows 的交叉是另一套故事（separate host toolset 需要
# 宿主架构的外部库、clang-cl 的 -m64 那套），当前矩阵没有那些组合，
# 不臆造实现。本机原生构建不受影响：目标==宿主时不加这两个 flag。
#
# 参考：Debian 的 nodejs 打包总是传 --dest-cpu（debian/rules 的 destCpu 映射），
# 交叉时再加 --cross-compiling + CC_host/CXX_host（他们有 multiarch 宿主库，
# 与我们的处境不同）。
#
# ★★ 宿主架构必须用 `VCPKG_DETECTED_CMAKE_HOST_SYSTEM_PROCESSOR`，**不能**用
#   `CMAKE_HOST_SYSTEM_PROCESSOR`（2026-10-14 run #40 实测，整整浪费一轮 13 分钟）：
#     * vcpkg 用 `cmake -P`（**脚本模式**）执行 portfile。脚本模式下
#       `CMAKE_HOST_SYSTEM_PROCESSOR` **不会被定义**（那是 `project()` 才设的），
#       所以 `MATCHES` 是拿空串比 ⇒ 恒假 ⇒ 这个 if 块**一次都没进**。
#     * 证据：整份 run #40 日志里下面那句 `message(STATUS "node port: 交叉编译 …")`
#       **出现 0 次**，而失败的链接命令仍带 `-arch arm64`：
#         /usr/bin/c++ … -arch arm64 … gen-regexp-special-case … libcrypto.a …
#         ld: warning: ignoring file '…/libcrypto.a(…)': found architecture
#             'x86_64', required architecture 'arm64'
#       ⇒ 症状与 run #39 一模一样，`--dest-cpu` 一次都没传出去。
#     * 正确变量由 vcpkg 自己导出：`scripts/get_cmake_vars/CMakeLists.txt` 把
#       `CMAKE_HOST_SYSTEM_PROCESSOR` 写进 buildtrees 下的 cmake-vars-*.log，形如
#       `set(VCPKG_DETECTED_CMAKE_HOST_SYSTEM_PROCESSOR "AMD64")`，并在
#       `scripts/ports.cmake:99` include 那个文件。vcpkg 自家
#       `scripts/cmake/vcpkg_configure_make.cmake:8` 用的就是这个变量。
#       `scripts/ports.cmake:186-194` 的告警注释也明说：宿主信息看
#       `CMAKE_HOST_<SYSTEM>` / `VCPKG_HOST_IS_<SYSTEM>`，目标信息看
#       `VCPKG_DETECTED_<VARIABLE>`。
#
# ★★ 下面**任何情况都要打一行 STATUS**（"决定走哪条路"），否则"分支没走"在日志里
#   只有"少了某一行"这种极弱信号：run #40 就是因为静默跳过，判读时先怀疑了半天才
#   确认 if 没进。判读方法论：先 grep 这三句话，再看后面的报错。
# ---------------------------------------------------------------------------
set(_node_dest_cpu_args "")
if(VCPKG_TARGET_IS_OSX)
    # 优先 vcpkg 导出的那个；万一将来 vcpkg 改了导出机制，退回 CMAKE_HOST_*，
    # 再退回 `uname -m`（POSIX 一定有，且不受 CMake 模式影响）。
    set(_node_host_raw "${VCPKG_DETECTED_CMAKE_HOST_SYSTEM_PROCESSOR}")
    if(_node_host_raw STREQUAL "")
        set(_node_host_raw "${CMAKE_HOST_SYSTEM_PROCESSOR}")
    endif()
    if(_node_host_raw STREQUAL "")
        find_program(_node_uname uname)
        if(_node_uname)
            vcpkg_execute_required_process(
                COMMAND "${_node_uname}" -m
                WORKING_DIRECTORY "${SOURCE_PATH}"
                OUTPUT_VARIABLE _node_host_raw
                ERROR_QUIET OUTPUT_QUIET
            )
            string(STRIP "${_node_host_raw}" _node_host_raw)
        endif()
        unset(_node_uname)
    endif()

    set(_node_host_arch "")
    if(_node_host_raw MATCHES "^(arm64|aarch64|ARM64)$")
        set(_node_host_arch "arm64")
    elseif(_node_host_raw MATCHES "^(x86_64|AMD64|[Xx]64)$")
        set(_node_host_arch "x64")
    endif()
    # node 的 valid_arch 含 x86/x64/arm/arm64（x86 由 configure_arch 归一成
    # ia32），与 vcpkg 的 VCPKG_TARGET_ARCHITECTURE 用词一致，可直接透传。
    if(NOT _node_host_arch)
        # 认不出来 ⇒ 只能当原生构建（不加 flag）。这不是安全的默认：万一真在交叉，
        # 后面就会重演 run #39/#40 那种"编完 1900 个目标才在链接处炸"的远距离报错。
        # 所以这里把判据原样打出来，让人一眼看出是"变量没取到"而不是"目标==宿主"。
        message(WARNING
            "node port: **认不出宿主架构**（VCPKG_DETECTED_CMAKE_HOST_SYSTEM_PROCESSOR="
            "'${VCPKG_DETECTED_CMAKE_HOST_SYSTEM_PROCESSOR}'、"
            "CMAKE_HOST_SYSTEM_PROCESSOR='${CMAKE_HOST_SYSTEM_PROCESSOR}'、"
            "uname -m='${_node_host_raw}'），"
            "无法判断目标 ${VCPKG_TARGET_ARCHITECTURE} 是否与宿主不同。"
            "按原生构建处理（不加 --dest-cpu）。"
            "若是交叉构建，请到 vcpkg/issues 反馈并附上这三个值。")
    elseif(NOT VCPKG_TARGET_ARCHITECTURE MATCHES "^(x86|x64|arm|arm64)$")
        message(WARNING
            "node port: 目标架构 ${VCPKG_TARGET_ARCHITECTURE} 不在 node 的 valid_arch "
            "（x86/x64/arm/arm64）里，交叉声明跳过（当原生处理）")
    elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "${_node_host_arch}")
        message(STATUS
            "node port: 目标 ${VCPKG_TARGET_ARCHITECTURE} == 宿主 "
            "（读自 '${_node_host_raw}'），原生构建，不加 --dest-cpu")
    else()
        set(_node_dest_cpu_args
            "--dest-cpu=${VCPKG_TARGET_ARCHITECTURE}"
            "--no-cross-compiling")
        message(STATUS
            "node port: 交叉编译 ${_node_host_arch} → ${VCPKG_TARGET_ARCHITECTURE}"
            "（--dest-cpu + --no-cross-compiling；x86_64 工具/测试经 Rosetta 运行）")
    endif()
endif()

# ---------------------------------------------------------------------------
# 1) 构建循环：每个口径跑一遍 configure.py → gyp → ninja。
#    --ninja → configure.py 传 `-f ninja-<flavor>`（Windows 上是 ninja-win）。这是合法
#    写法：gyp 的 Load() 里有 `if "-" in format: format, flavor = format.split("-", 1)`，
#    会把它拆成 format=ninja + flavor=win（见 tools/gyp/pylib/gyp/__init__.py）。
#    -DVCPKG_SIMDUTF_INCLUDE 供 patches/0011 的 v8 simdutf 目标使用。
#
#    并发度跟随 vcpkg（VCPKG_CONCURRENCY，来自 VCPKG_MAX_CONCURRENCY）：ninja 默认是
#    "核数+2"，在 3 核 / 7 GB 的 macOS arm64 runner 上会同时跑 5 个重型 V8 编译单元，
#    容易 OOM。vcpkg 自带的 vcpkg_build_ninja 反而不传 -j，所以这里显式传。
#
#    node 可执行（tools feature）只从 **Release** 编：它是给人跑 node/npm 用的，
#    调试版可执行没有消费场景；debug-only triplet 已在上面 FATAL，所以 Release 一定在。
# ---------------------------------------------------------------------------
set(_node_ninja_jobs "")
if(DEFINED VCPKG_CONCURRENCY AND NOT VCPKG_CONCURRENCY STREQUAL "")
    set(_node_ninja_jobs "-j${VCPKG_CONCURRENCY}")
endif()

set(_node_installed_libs "")

foreach(_node_cfg IN LISTS _node_configs)
    if(_node_cfg STREQUAL "Debug")
        set(_node_cfg_arg "--debug")
        set(_node_lib_dir "${CURRENT_INSTALLED_DIR}/debug/lib")
        # ★ ICU 不走 --shared-*（node 24 没有 --shared-icu），它走
        #   `--with-intl=system-icu` + **pkg-config**。所以每个口径必须把
        #   PKG_CONFIG_PATH 也切到对应侧，否则 debug 构建会经 pkg-config 链到
        #   **release** 的 icuuc.lib ⇒ LNK2038（_ITERATOR_DEBUG_LEVEL 0 vs 2，
        #   RuntimeLibrary MT_StaticRelease vs MTd_StaticDebug）。
        #   这是双份构建第一次真编 debug 才暴露的潜伏 bug（旧的私有开关
        #   NODE_PORT_BUILD_TYPE 不进 ABI 哈希，"debug 腿"其实复用了 release 产物）。
        set(ENV{PKG_CONFIG_PATH} "${CURRENT_INSTALLED_DIR}/debug/lib/pkgconfig")
        # 同理，LIB 搜索路径也要切到 debug 侧：gyp 有目标按名字链依赖库
        # （原 portfile 在这里挂过 release 的 lib），debug 构建不该看见 release 库。
        set(ENV{LIB} "${_node_lib_dir};$ENV{LIB}")
    else()
        set(_node_cfg_arg "")
        set(_node_lib_dir "${CURRENT_INSTALLED_DIR}/lib")
        set(ENV{PKG_CONFIG_PATH} "${CURRENT_INSTALLED_DIR}/lib/pkgconfig")
        set(ENV{LIB} "${_node_lib_dir};$ENV{LIB}")
    endif()

    _node_shared_args(_node_shared_args "${_node_lib_dir}")

    vcpkg_execute_required_process(
        COMMAND "${PYTHON3}" configure.py
            --ninja
            ${_node_cfg_arg}
            ${_node_clang_cl_arg}
            ${_node_dest_cpu_args}
            --with-intl=system-icu
            ${_node_shared_args}
            "-DVCPKG_SIMDUTF_INCLUDE=${_inc}"
        WORKING_DIRECTORY "${SOURCE_PATH}"
        LOGNAME "configure-${_node_cfg}"
    )

    # 红线裁判：config.gypi 的 target_defaults.include_dirs 前两条必须是
    # v8 自带的 abseil-cpp 与 highway/src。判定逻辑单独放在 scripts/ 下，
    # 这样"故意弄坏一次"的正反两个方向都能真跑（见 .tmp/gen 的验证脚本），
    # 而不是只写在注释里说"应该如此"。每个口径都查（便宜，且防第二遍 configure 退化）。
    include("${CMAKE_CURRENT_LIST_DIR}/scripts/redline-include-order.cmake")

    set(_node_ninja_targets libnode)
    if(_node_cfg STREQUAL "Release" AND "tools" IN_LIST FEATURES)
        list(APPEND _node_ninja_targets node)  # tools 要 node.exe
    endif()

    vcpkg_execute_required_process(
        COMMAND "${NINJA}" -C "${SOURCE_PATH}/out/${_node_cfg}" ${_node_ninja_jobs} ${_node_ninja_targets}
        WORKING_DIRECTORY "${SOURCE_PATH}"
        LOGNAME "build-${_node_cfg}"
    )
endforeach()

# ---------------------------------------------------------------------------
# 2) 安装：头文件 + 各口径 gyp 静态库 + compiler-rt 内建库 + 手写 CMake 消费配置。
# ---------------------------------------------------------------------------
file(INSTALL "${SOURCE_PATH}/src/" DESTINATION "${CURRENT_PACKAGES_DIR}/include/node"
    FILES_MATCHING PATTERN "*.h" PATTERN "*.hpp")
# ★ V8 头装到 include/node-v8/，**不再**平铺到 include/ 根目录。
#
# 为什么（1013 评审 B1，我接受）：vcpkg 的 Unique File Mapping Rule —— 端口之间不能
#   装同名/同位的文件。vcpkg 官方有 `v8` 端口（9.1.269.39，`supports: !(arm|arm64|uwp|
#   osx|linux)` ⇒ Windows x86/x64 可装），它装的就是 `include/v8.h`；我们平铺的话，
#   用户同时装 `node` 与 `v8` 会直接 FILE_CONFLICTS，而且 V8 头文件铺在全局 include
#   根下也会污染别的项目。
#
# 消费端不受影响：include 路径由我们的 CMake 配置给（`INTERFACE_INCLUDE_DIRECTORIES`
#   里加 `<prefix>/include/node-v8`），所以 node.h 里的 `#include <v8.h>` 照样找得到。
#   —— 这也是**不需要给 node 源码打补丁**就能挪的原因（当初差点以为要改上游）。
file(INSTALL "${SOURCE_PATH}/deps/v8/include/" DESTINATION "${CURRENT_PACKAGES_DIR}/include/node-v8")

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
# ★ 与 vcpkg 其他端口**同名符号**的库，必须装进 lib/manual-link/，由消费配置用
#   绝对路径引用 —— 不能让链接器在全局 lib 目录里自己搜到它们（评审 B1 的要求）。
#   只这四个：abseil / highway（vcpkg 有独立端口，V8 用的还是它们的**内部符号**，
#   见 §5g：换成 vcpkg 那份会在链接期挂）；v8_zlib（定义 zlib 相关符号，与 vcpkg
#   zlib 撞）；crdtp（DevTools 协议，名字太泛）。其余（libnode / node_base / v8_* /
#   uvwasi / merve / nbytes / ncrypto / node_mksnapshot）是本端口独有名字，留在 lib/。
set(_node_manual_link_archives abseil highway v8_zlib crdtp)

foreach(_node_cfg IN LISTS _node_configs)
    if(_node_cfg STREQUAL "Debug")
        set(_node_out_dir "${SOURCE_PATH}/out/Debug")
        set(_node_pkg_lib_dir "${CURRENT_PACKAGES_DIR}/debug/lib")
    else()
        set(_node_out_dir "${SOURCE_PATH}/out/Release")
        set(_node_pkg_lib_dir "${CURRENT_PACKAGES_DIR}/lib")
    endif()

    file(GLOB_RECURSE _node_cfg_archives "${_node_out_dir}/obj/*${_node_lib_suffix}")
    file(GLOB _node_cfg_archives_root "${_node_out_dir}/*${_node_lib_suffix}")
    list(APPEND _node_cfg_archives ${_node_cfg_archives_root})

    foreach(_a IN LISTS _node_cfg_archives)
        get_filename_component(_node_archive_stem "${_a}" NAME_WE)
        if(NOT VCPKG_TARGET_IS_WINDOWS)
            # POSIX 上是 libabseil.a 这种，去掉前缀才能对上 gyp 的目标名。
            string(REGEX REPLACE "^lib" "" _node_archive_stem "${_node_archive_stem}")
        endif()
        if(_node_archive_stem IN_LIST _node_manual_link_archives)
            file(INSTALL "${_a}" DESTINATION "${_node_pkg_lib_dir}/manual-link")
        else()
            file(INSTALL "${_a}" DESTINATION "${_node_pkg_lib_dir}")
        endif()
    endforeach()
    unset(_node_archive_stem)
    unset(_node_cfg_archives)
    unset(_node_cfg_archives_root)

    # compiler-rt 内建库跟着每个口径各装一份（同名同内容，但 lib/ 与 debug/lib
    # 是两个目录；导出配置按口径选）。它没有同名 vcpkg port，不进 manual-link。
    if(_node_rt_builtins_lib)
        file(INSTALL "${_node_rt_builtins_lib}" DESTINATION "${_node_pkg_lib_dir}")
    endif()

    # 记下"本 port 到底装了哪些库"（只要文件名），写进消费配置给符号审计用。
    # 只从 Release 记（各口径文件名相同；且 release-only 安装时它就是全部）。
    if(_node_cfg STREQUAL "Release")
        set(_node_installed_libs "")
        foreach(_a IN LISTS _node_archives)
            get_filename_component(_node_lib_name "${_a}" NAME)
            list(APPEND _node_installed_libs "${_node_lib_name}")
        endforeach()
        list(REMOVE_DUPLICATES _node_installed_libs)
        unset(_node_lib_name)
    endif()
endforeach()
unset(_node_out_dir)
unset(_node_pkg_lib_dir)

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

    # ★★ 这一整段的 file(INSTALL) 都必须带 USE_SOURCE_PERMISSIONS。
    #
    # 为什么：CMake 的文档在 `file(COPY|INSTALL)` 一节里写"默认就是 USE_SOURCE_PERMISSIONS"，
    # **但对 file(INSTALL) 不成立** —— 它的默认是 0644/0755（install() 那一套），
    # 源码树里的执行位会**悄悄**丢掉。（实测 2026-10-13：源里的 `x` 是 755，
    # `cmake -E tar xzf` 解出来还是 755，`file(INSTALL <dir>/ DESTINATION)` 之后变成 644；
    # 补上 USE_SOURCE_PERMISSIONS 才是 755。）
    #
    # 后果有多大（run #29 实测，Linux + macOS 稳定复现）：node 官方套件里
    # `test/fixtures/run-script/node_modules/.bin/{ada,positional-args,path-env,
    # special-env-variables,custom-env}` 被 `node --run <script>` 当命令执行，
    # 掉位之后 `sh -c <script>` 直接失败 ⇒ **子进程 stdout 为空、stderr 进 child.stderr
    # （用例不打印它）**，于是 test-node-run 里 6 个子用例全红、而报错信息里
    # 完全看不出是权限问题（Windows 不受影响：那边走 `.bat`，cmd.exe 不看执行位）。
    # 这类"红线变脚本"的检查见 test/test_official_suite/ctest_node_suite.cmake 里的
    # `node-suite-fixtures-executable` 用例。
    file(INSTALL "${SOURCE_PATH}/test/" DESTINATION "${_node_suite}/test"
        USE_SOURCE_PERMISSIONS)
    # 整棵 tools/（约 6 MB）：test.py / utils.py 是驱动，tools/icu/icu_versions.json
    # 等是上游用例会读的数据。
    file(INSTALL "${SOURCE_PATH}/tools/" DESTINATION "${_node_suite}/tools"
        USE_SOURCE_PERMISSIONS)

    # 用例会按相对路径读的兄弟目录（漏一个就多一片假失败）。
    file(INSTALL "${SOURCE_PATH}/benchmark/" DESTINATION "${_node_suite}/benchmark"
        USE_SOURCE_PERMISSIONS)
    file(INSTALL "${SOURCE_PATH}/doc/" DESTINATION "${_node_suite}/doc"
        USE_SOURCE_PERMISSIONS)
    file(INSTALL "${SOURCE_PATH}/lib/" DESTINATION "${_node_suite}/lib"
        USE_SOURCE_PERMISSIONS)
    # .cc 也要装：test-cli-node-options-docs 读 src/node_options.cc 去核对
    # CLI 选项与文档的一致性。只装 .h/.hpp 会让它 ENOENT。
    file(INSTALL "${SOURCE_PATH}/src/" DESTINATION "${_node_suite}/src"
        USE_SOURCE_PERMISSIONS
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
            # 所以 DEST 给 .../deps 而不是 .../deps/<dep>（后者会出 deps/npm/npm/）。
            file(INSTALL "${SOURCE_PATH}/deps/${_node_dep}"
                DESTINATION "${_node_suite}/deps"
                USE_SOURCE_PERMISSIONS)
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
#   * triplet / toolchain **不输出** —— 那是消费端的构建配置（2026-10-14 重构后 port 自己
#     会摆 MSVC 环境，消费端用标准 triplet 即可；参考写法在本仓库的示例工程里，只是示例）。
#
# 布局照 node 官方发行版：可执行 + node_modules/{npm,corepack} + 垫片。
# 垫片两套都装（POSIX sh 与 Windows .cmd）—— 这样 cmd / PowerShell / Git-Bash / 跨平台
# 脚本都能用；它们只用相对路径定位（%~dp0 / $0），不依赖 PATH 上的 node/npm。
#
# ★ 双份构建时可执行只取 **Release** 那份（给人跑 node/npm 用，调试版没有消费场景；
#   debug-only triplet 已在开头 FATAL，所以 Release 一定在）。
if("tools" IN_LIST FEATURES)
    set(_node_tools "${CURRENT_PACKAGES_DIR}/tools/${PORT}")

    if(VCPKG_TARGET_IS_WINDOWS)
        file(INSTALL "${SOURCE_PATH}/out/Release/node.exe" DESTINATION "${_node_tools}")
    else()
        file(INSTALL "${SOURCE_PATH}/out/Release/node" DESTINATION "${_node_tools}"
            FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                            GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
    endif()

    # npm 与 corepack 就是 node 源码树里 vendor 的那两份（发行版同源）。
    # USE_SOURCE_PERMISSIONS：它们自带的 POSIX 可执行文件（deps/npm/bin/npm 等）
    # 在源码树里是 755，别被 file(INSTALL) 的默认 0644 抹掉（理由见 test-suite 那段）。
    file(INSTALL "${SOURCE_PATH}/deps/npm/" DESTINATION "${_node_tools}/node_modules/npm"
        USE_SOURCE_PERMISSIONS)
    file(INSTALL "${SOURCE_PATH}/deps/corepack/" DESTINATION "${_node_tools}/node_modules/corepack"
        USE_SOURCE_PERMISSIONS)

    foreach(_node_shim IN ITEMS npm npx corepack)
        file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/scripts/${_node_shim}"
            DESTINATION "${_node_tools}" RENAME "${_node_shim}"
            FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                            GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
        file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/scripts/${_node_shim}.cmd"
            DESTINATION "${_node_tools}" RENAME "${_node_shim}.cmd")
    endforeach()

    # 说明：node.exe 用静态 CRT 时正常没有需要一起带的 DLL；/MD 口径下
    # vcruntime 不在 vcpkg 产物里，消费端按自己的部署常规处理（与 vcpkg 其他
    # /MD 可执行一致）。
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
    # "使用者自己装的库"分开（<prefix>/lib 是共用的，见安装阶段那段说明）。
    "set(node_INSTALLED_LIBRARIES \"${_node_installed_libs}\")\n")

# ★ release-only 安装 + Windows Debug 消费方 ⇒ 配置期就红，别等链接期 LNK2038。
#   双份安装（debug/lib 存在）时 Debug 消费方拿的是 /MTd（或 /MDd）的 node 库，
#   与自己 /MTd 的代码天然一致 —— 这正是路线 A（双份构建）消灭的那条约束。
#   Linux/macOS 没有双 CRT 概念，release-only 安装给 Debug 用是 vcpkg `-release`
#   triplet 的既有行为（CMake 自动回落到 IMPORTED_LOCATION），不拦。
if(VCPKG_TARGET_IS_WINDOWS)
    string(APPEND _cfg
        "if(CMAKE_BUILD_TYPE STREQUAL \"Debug\" AND NOT EXISTS \"\${_node_prefix}/debug/lib\")\n"
        "  message(FATAL_ERROR\n"
        "    \"本 node 安装是 release-only（triplet 设了 VCPKG_BUILD_TYPE=release），没有 debug 库。\\n\"\n"
        "    \"Windows 上 Debug 消费方（/MTd 或 /MDd）无法链接 release（/MT 或 /MD）编出来的 node 库。\\n\"\n"
        "    \"两个选择：\\n\"\n"
        "    \"  1) 换用不设 VCPKG_BUILD_TYPE 的双份 triplet（如 x64-windows-static），\\n\"\n"
        "    \"     port 会编两份并装进 lib/ 与 debug/lib/；\\n\"\n"
        "    \"  2) 把消费方改成 Release 构建。\")\n"
        "endif()\n")
endif()

# ★ Windows：消费端的 CRT 选择 **vcpkg 不会替它做** —— 这里在配置期就挡住。
#   设 /MT 的那份脚本（scripts/toolchains/windows.cmake）只作用于 **port 构建**：
#   vcpkg 把它当 chainload toolchain 传给 port 的 cmake，而消费端的 cmake 走的是
#   CMAKE_TOOLCHAIN_FILE=vcpkg.cmake，**不会加载它**（本机实测：CMAKE_MSVC_RUNTIME_LIBRARY
#   根本不在消费端的 CMakeCache 里）⇒ CMake 给默认值 /MD，与 node 的 /MT 在链接期
#   喷一整屏 LNK2038「MT_StaticRelease 不匹配 MD_DynamicRelease」（2026-10-15）。
#   这条闸门不替消费端做决定，只把"你还没决定"这件事在配置期说出来并给出确切修法
#   —— 省掉一轮 CI（单腿 1～1.5h）。
if(VCPKG_TARGET_IS_WINDOWS)
    if(VCPKG_CRT_LINKAGE STREQUAL "static")
        string(APPEND _cfg
            "if(MSVC AND (NOT DEFINED CMAKE_MSVC_RUNTIME_LIBRARY"
            " OR CMAKE_MSVC_RUNTIME_LIBRARY STREQUAL \"\""
            " OR CMAKE_MSVC_RUNTIME_LIBRARY MATCHES \"DLL\"))\n"
            "  message(FATAL_ERROR\n"
            "    \"本 node 安装是**静态** CRT（/MT）编的，而消费端会按 CMake 默认值用动态 CRT（/MD）：\\n\"\n"
            "    \"    CMAKE_MSVC_RUNTIME_LIBRARY = '\${CMAKE_MSVC_RUNTIME_LIBRARY}'（未设置 = 默认 /MD）\\n\"\n"
            "    \"vcpkg 那份设 /MT 的脚本（scripts/toolchains/windows.cmake）**只作用于 port 构建**，\\n\"\n"
            "    \"消费端的 cmake 不会加载它 ⇒ 这个值必须由消费端自己给：\\n\"\n"
            "    \"\\n\"\n"
            "    \"    set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreaded)\\n\"\n"
            "    \"    双份安装想让 Debug 也一致：\\n\"\n"
            "    \"    set(CMAKE_MSVC_RUNTIME_LIBRARY \\\"MultiThreaded$<$<CONFIG:Debug>:Debug>\\\")\\n\"\n"
            "    \"\\n\"\n"
            "    \"不给的话，链接期是一整屏 LNK2038：mismatch detected for 'RuntimeLibrary' ——\\n\"\n"
            "    \"    MT_StaticRelease 不匹配 MD_DynamicRelease。\")\n"
            "endif()\n")
    else()
        string(APPEND _cfg
            "if(MSVC AND DEFINED CMAKE_MSVC_RUNTIME_LIBRARY"
            " AND NOT CMAKE_MSVC_RUNTIME_LIBRARY STREQUAL \"\""
            " AND NOT CMAKE_MSVC_RUNTIME_LIBRARY MATCHES \"DLL\")\n"
            "  message(FATAL_ERROR\n"
            "    \"本 node 安装是**动态** CRT（/MD）编的（triplet: ${VCPKG_TARGET_TRIPLET}），\\n\"\n"
            "    \"而消费端被设成了静态 CRT：'\${CMAKE_MSVC_RUNTIME_LIBRARY}'。两边必须一致 ——\\n\"\n"
            "    \"放开这个变量（让它回到默认的 /MD），或改用静态 CRT 的 triplet 装 node。\")\n"
            "endif()\n")
    endif()
endif()

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
    # 见 test/test_tools/ctest_tools.cmake。
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
    # ★ 与 vcpkg 同端口名冲突的那几个装在 lib/manual-link/ 下（见安装阶段），
    #   所以这里要用**绝对路径**指过去，不能让链接器在 <prefix>/lib 里搜。
    set(_node_archive_subdir "")
    if(_a IN_LIST _node_manual_link_archives)
        set(_node_archive_subdir "manual-link/")
    endif()
    string(APPEND _cfg
        "if(NOT TARGET unofficial::node::${_a})\n"
        "  add_library(unofficial::node::${_a} STATIC IMPORTED)\n"
        "  set_target_properties(unofficial::node::${_a} PROPERTIES IMPORTED_LOCATION"
        " \"\${_node_lib}/${_node_archive_subdir}${_node_file}\")\n")
    # 双份安装才给 debug 侧；release-only 安装**不能**给（路径不存在，CMake 不会
    # 回落、而是拿这个不存在的文件去链 ⇒ Linux/macOS 上 release-only + Debug
    # 消费方本来能用的场景会被打破）。缺了 CMake 自动回落到 IMPORTED_LOCATION。
    if("Debug" IN_LIST _node_configs)
        string(APPEND _cfg
            "  set_target_properties(unofficial::node::${_a} PROPERTIES IMPORTED_LOCATION_DEBUG"
            " \"\${_node_prefix}/debug/lib/${_node_archive_subdir}${_node_file}\")\n")
    endif()
    string(APPEND _cfg "endif()\n")
    string(APPEND _node_archive_links " unofficial::node::${_a}")
endforeach()
unset(_node_file)
unset(_node_archive_subdir)

# ★ 命名空间改成 unofficial::node:: —— 评审 B5（用户已拍板"现在改"）。
#   vcpkg 的规则：上游**不提供**的 CMake config，一律加 `unofficial-` 前缀、
#   目标进 `unofficial::<port>::` 命名空间。Node 上游用 gyp、没有官方 CMake config，
#   所以我们导出的全部属于这一类 —— 这样将来若出现官方 `node` 端口不会撞名。
#   消费端写法随之变成：find_package(unofficial-node CONFIG REQUIRED) +
#   target_link_libraries(<目标> PRIVATE unofficial::node::node)
string(APPEND _cfg
    "add_library(unofficial::node::node INTERFACE IMPORTED)\n"
    "set_target_properties(unofficial::node::node PROPERTIES"
    # include/node-v8：V8 的头文件挪到了这个子目录（见安装阶段），这里把路径给消费端，
    # 于是 node.h 里的 `#include <v8.h>` 照样成立。
    " INTERFACE_INCLUDE_DIRECTORIES"
    " \"\${_node_prefix}/include;\${_node_prefix}/include/node;\${_node_prefix}/include/node-v8\")\n")
# ---------------------------------------------------------------------------
# 语言层要求：**由本 port 在 INTERFACE 上声明**，消费端一行都不用写。
#   ① C++20 —— v8config.h 第一行实质内容就是
#        `#if __cplusplus <= 201703L  →  #error "C++20 or later required."`
#      CMake 默认是 C++14/17，谁都不写就必红。
#   ② MSVC 的 /Zc:__cplusplus —— cl.exe **默认把 __cplusplus 报成 199711L**
#      （哪怕已经开了 /std:c++20），于是上面那条检查必然红；clang-cl 没这个毛病，
#      所以只对 cl.exe 加。
#   2026-10-15 实测：消费端从 clang-cl 换成 triplet 原生的 cl.exe 之后，第一个红就是
#     v8config.h(13): fatal error C1189: #error: "C++20 or later required."
#   （加了 /Zc:__cplusplus 才过）。这不是"替消费端做决定"：这是 node/v8 头文件的硬要求，
#   不声明就等于让每个使用者自己去撞一遍。
#   用 set_property 写属性而不是 target_compile_features：后者在 IMPORTED 目标上
#   的可用性随 CMake 版本摇摆，INTERFACE_COMPILE_FEATURES 属性本身是稳定的。
# ---------------------------------------------------------------------------
string(APPEND _cfg
    "set_property(TARGET unofficial::node::node PROPERTY INTERFACE_COMPILE_FEATURES cxx_std_20)\n")
if(VCPKG_TARGET_IS_WINDOWS)
    string(APPEND _cfg
        "if(MSVC AND NOT CMAKE_CXX_COMPILER_ID MATCHES \"Clang\")\n"
        "  target_compile_options(unofficial::node::node INTERFACE \"/Zc:__cplusplus\")\n"
        "endif()\n")
endif()
# nghttp2 没有 CMake config 文件，手动建 imported target。
# debug 侧的库名按平台算（Windows: nghttp2.lib；POSIX: libnghttp2.a）——
# 双份安装才给，缺了 CMake 自动回落到 IMPORTED_LOCATION。
string(APPEND _cfg
    "find_library(_nghttp2_lib nghttp2 HINTS \${_node_lib} REQUIRED)\n"
    "if(NOT TARGET unofficial::node::nghttp2)\n"
    "  add_library(unofficial::node::nghttp2 STATIC IMPORTED)\n"
    "  set_target_properties(unofficial::node::nghttp2 PROPERTIES IMPORTED_LOCATION \"\${_nghttp2_lib}\")\n")
if("Debug" IN_LIST _node_configs)
    _node_archive_filename("nghttp2" _node_nghttp2_file)
    string(APPEND _cfg
        "  set_target_properties(unofficial::node::nghttp2 PROPERTIES IMPORTED_LOCATION_DEBUG"
        " \"\${_node_prefix}/debug/lib/${_node_nghttp2_file}\")\n")
    unset(_node_nghttp2_file)
endif()
string(APPEND _cfg
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
    "    hdr_histogram::hdr_histogram_static unofficial::node::nghttp2 llhttp::llhttp_static)\n")
if(VCPKG_TARGET_IS_WINDOWS OR VCPKG_TARGET_IS_OSX)
    # 平铺。Windows：link.exe 反复扫描；Apple：ld64 无 rescan 构造（上游 MAC 命令亦然）。
    string(APPEND _cfg
        "# 平铺：Windows 的 link.exe 会反复扫描；Apple 的 ld64 没有 rescan 构造。\n"
        "# （理由与依据见 port 侧 portfile.cmake 里那段注释。）\n"
        "target_link_libraries(unofficial::node::node INTERFACE \${_node_archives_link} \${_node_deps_link})\n")
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
        "target_link_libraries(unofficial::node::node INTERFACE \"\$<LINK_GROUP:RESCAN,\${_node_group_items}>\")\n")
endif()
# macOS 系统 framework：node 自己的 node.gypi 就是这么链的
# （node.gypi:258 `'libraries': [ '-framework CoreFoundation -framework Security' ]`），
# 用来提供 CFArray*/CFDictionary*/CFTimeZone*（abseil 的 cctz 本地时区）与
# SecTrust*/SecItem*（node 的 crypto_context.cc 走钥匙串）。缺了它们 arm64-osx 在
# 消费端链接时就是一堆 `_CFArrayCreateMutable … not found`（run #21 实测）。
if(VCPKG_TARGET_IS_OSX)
    string(APPEND _cfg
        "target_link_libraries(unofficial::node::node INTERFACE"
        " \"-framework CoreFoundation\" \"-framework Security\")\n")
endif()
# Windows 额外系统库与链接设置：
#   * winmm：V8 的 timeGetTime。
#   * compiler-rt 内建库：node 的 clang-cl 产物引用 __cpu_model，而消费端的链接
#     （cl.exe 的 link.exe 或 CMake 对 MSVC 前端的 lld-link 直链）都不会自动带上
#     clang 的 compiler-rt —— 原来靠消费端工具链算绝对路径（NODE_PORT_CLANG_RT_BUILTINS），
#     现在由 port 装进 lib/（与 debug/lib），配置按口径选绝对路径。
if(VCPKG_TARGET_IS_WINDOWS)
    string(APPEND _cfg
        "if(NOT TARGET unofficial::node::clang_rt_builtins)\n"
        "  add_library(unofficial::node::clang_rt_builtins STATIC IMPORTED)\n"
        "  set_target_properties(unofficial::node::clang_rt_builtins PROPERTIES\n"
        "    IMPORTED_LOCATION \"\${_node_lib}/clang_rt.builtins-${_node_rt_arch}.lib\")\n")
    if("Debug" IN_LIST _node_configs)
        string(APPEND _cfg
            "  set_target_properties(unofficial::node::clang_rt_builtins PROPERTIES\n"
            "    IMPORTED_LOCATION_DEBUG \"\${_node_prefix}/debug/lib/clang_rt.builtins-${_node_rt_arch}.lib\")\n")
    endif()
    string(APPEND _cfg
        "endif()\n")
    string(APPEND _cfg
        "target_link_libraries(unofficial::node::node INTERFACE winmm unofficial::node::clang_rt_builtins)\n")

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
        "target_link_options(unofficial::node::node INTERFACE \"/STACK:${_node_stack_reserve}\")\n")

    # ---------------------------------------------------------------------------
    # ★ Windows 平台兼容性清单 + 增量链接：由配置**自动带上**（2026-10-14 重构，
    #   原来是 usage 里让用户手抄的三行片段 —— 与 /STACK: 同性质，都是"消费端可执行
    #   必须带的链接设置"，没理由一条自动一条手动）。
    #
    # 为什么必须嵌：缺了它进程一启动就退出码 216（实测）。
    # 为什么必须 /INCREMENTAL:NO：Debug 构建默认带 /INCREMENTAL，cmake 的 vs_link_exe
    #   会走增量两遍链接、在命令尾部追加裸 `/MANIFEST /MANIFESTFILE:`，把
    #   `/MANIFESTINPUT:` 的嵌入模式顶掉（lld-link: `/manifestinput: requires
    #   /manifest:embed`）；关掉增量即回到非增量路径（Release 一直在走的那条）。
    #   静态库消费者不受影响：CMake 的 target_link_options 只作用于可执行/共享库的
    #   链接步（example_multitarget 的静态库引擎实测链接通过）。
    # ---------------------------------------------------------------------------
    # 变量先设（下面那段 target_link_options 读它）。
    string(APPEND _cfg
        "set(node_NODE_SOURCE_MANIFEST \"\${_node_prefix}/share/node/node.exe.extra.manifest\")\n")
    string(APPEND _cfg
        "# Windows 平台兼容性清单：消费端可执行必须嵌它，否则一启动就退出码 216。\n"
        "# /INCREMENTAL:NO 防止 vs_link_exe 的增量两遍链接把嵌入模式顶掉。\n"
        "if(DEFINED node_NODE_SOURCE_MANIFEST AND EXISTS \"\${node_NODE_SOURCE_MANIFEST}\")\n"
        "  target_link_options(unofficial::node::node INTERFACE\n"
        "    \"/MANIFEST:EMBED\"\n"
        "    \"/MANIFESTINPUT:\${node_NODE_SOURCE_MANIFEST}\"\n"
        "    \"/INCREMENTAL:NO\")\n"
        "endif()\n")
endif()
# 装了 test-suite feature 就导出官方套件的根目录（tools/test.py 以它的父目录为 workspace）。
# ★ 本文件现在装在 share/unofficial-node/（目录名必须与**包名**一致，find_package(unofficial-node)
#   才找得到，见上面那段），而套件仍在 share/node/test-suite/ ⇒ 相对路径要走隔壁那层。
string(APPEND _cfg
    "if(EXISTS \"\${CMAKE_CURRENT_LIST_DIR}/../node/test-suite/tools/test.py\")\n"
    "  set(node_TEST_SUITE_DIR \"\${CMAKE_CURRENT_LIST_DIR}/../node/test-suite\")\n"
    "endif()\n")
file(WRITE "${CURRENT_PACKAGES_DIR}/share/unofficial-node/unofficial-node-config.cmake" "${_cfg}")

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
    "${CURRENT_PACKAGES_DIR}/share/unofficial-node/unofficial-node-config-version.cmake"
    VERSION "${VERSION}"
    COMPATIBILITY SameMajorVersion)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
