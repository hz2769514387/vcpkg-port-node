# node - build the Node.js v26.12.0 source tree (V8 included) into a linkable
# static library, using Node.js's own gyp -> ninja route.
#
# Why gyp -> ninja and not a CMake translation: upstream's only build entry
# point is gyp - MSBuild on Windows, Make on Unix, both through
# tools/gyp_node.py. Driving the ninja generator is the closest to the official
# path and avoids maintaining a translated CMake tree. gyp's own cmake
# generator is declared experimental and Linux-only upstream.
#
# This port is self-contained: portfile / vcpkg.json / patches / scripts /
# usage, nothing outside its own directory, and no triplet or toolchain (those
# belong to the consumer). A stock vcpkg triplet is enough: on Windows this
# port locates clang-cl and assembles the MSVC command-line environment itself
# (see scripts/node-msvc-env.cmake).
#
# Dependencies come from vcpkg through the official --shared-* channels, and
# ICU goes through --with-intl=system-icu (the bundled icu-small does not build
# with clang-cl). The four third-party libraries V8 would otherwise compile
# into the delivered artifacts - abseil, highway, simdutf, zlib - are
# externalized too, because two copies of the same symbols in one process is
# exactly what must not happen.

vcpkg_check_linkage(ONLY_STATIC_LIBRARY)

# ---------------------------------------------------------------------------
# Build scope follows VCPKG_BUILD_TYPE, the standard vcpkg rule for ports that
# can produce both configurations.
#
# debug-only is rejected rather than honoured: several upstream ports this one
# depends on run vcpkg_copy_tools, and a debug-only tree puts executables under
# debug/tools/ where they are not found (brotli and friends fail that way); and
# a debug-only install leaves release consumers without a library.
# ---------------------------------------------------------------------------
set(_node_configs "")
if(NOT DEFINED VCPKG_BUILD_TYPE OR VCPKG_BUILD_TYPE STREQUAL "")
    set(_node_configs Release Debug)
    message(STATUS "node port: VCPKG_BUILD_TYPE unset -> building Release + Debug")
elseif(VCPKG_BUILD_TYPE STREQUAL "release")
    set(_node_configs Release)
    message(STATUS "node port: VCPKG_BUILD_TYPE=release -> building Release only")
elseif(VCPKG_BUILD_TYPE STREQUAL "debug")
    message(FATAL_ERROR
        "node port: a debug-only triplet (VCPKG_BUILD_TYPE=debug) is not supported:\n"
        "  1) several upstream ports use vcpkg_copy_tools, which fails in a debug-only\n"
        "     tree because the executables land under debug/tools/;\n"
        "  2) a debug-only install has no release library, so Release consumers cannot link.\n"
        "  Use a dual triplet (VCPKG_BUILD_TYPE unset, e.g. x64-windows-static); this port\n"
        "  builds both and installs them into lib/ and debug/lib/.")
else()
    message(FATAL_ERROR
        "node port: unrecognised VCPKG_BUILD_TYPE='${VCPKG_BUILD_TYPE}' "
        "(only release / debug / unset).")
endif()

vcpkg_download_distfile(NODE_ARCHIVE
    URLS "https://nodejs.org/dist/v26.12.0/node-v26.12.0.tar.xz"
    SHA512 c3c41462198c6bedc1f2136a7f421a7cc757996ae49486c4c82b7ee75b2294b298c14f7e838b83da04a789f50722247ab448dd3bac8a07ac0d49047ee33c1c05
    FILENAME node-v26.12.0.tar.xz
)

# The patch set fixes defects in gyp's ninja/MSVC emulation that upstream never
# sees (its Windows build goes through MSBuild, its Unix builds through Make),
# plus the v26 crates target and the externalization of simdutf/zlib.
vcpkg_extract_source_archive(SOURCE_PATH
    ARCHIVE "${NODE_ARCHIVE}"
    SOURCE_BASE node-v26.12.0
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
        "${CMAKE_CURRENT_LIST_DIR}/patches/0012-v8-use-vcpkg-zlib-target.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0013-v8-compiler-add-descriptor-array-inl.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0014-crates-target-arch.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0015-js2c-report-unusable-input.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0016-torque-normalize-source-position-paths.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0017-js2c-fallback-simdutf-convert.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0018-macos-deployment-target-from-the-build.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0019-libffi-win-arm64-asm-reaches-ninja.patch"
)

# Build-time tools from vcpkg's tool cache, so nothing has to be preinstalled.
vcpkg_find_acquire_program(PYTHON3)
vcpkg_find_acquire_program(NINJA)

# ---------------------------------------------------------------------------
# Compiler and environment.
#   * Windows: clang-cl (Node.js 24+ requires it). The compiler and the MSVC
#     command-line environment are both set up here, so the consumer needs
#     nothing beyond a stock triplet.
#   * Linux / macOS: the system cc / c++.
# configure.py reads CC/CXX to choose the compiler rule in the generated ninja.
# ---------------------------------------------------------------------------
set(_node_cc "")
set(_node_cxx "")
set(_node_clang_cl_arg "")
set(_node_rt_builtins_lib "")
set(_node_rt_arch "")
set(_node_dynamic_crt 0)

if(VCPKG_TARGET_IS_WINDOWS)
    # Put INCLUDE / LIB / PATH together for the gyp/ninja build (nmake, MSVC and
    # SDK headers, rc.exe/mt.exe) and publish NODE_PORT_VS_INSTALL_ROOT and
    # NODE_PORT_HOST_ARCH.
    include("${CMAKE_CURRENT_LIST_DIR}/scripts/node-msvc-env.cmake")

    # --- locate clang-cl ---
    #   (1) NODE_PORT_LLVM_BIN     explicit override (CI pins the runner layout)
    #   (2) NODE_PORT_LLVM_ROOT    an LLVM install root (with x64/bin or bin)
    #   (3) VS's bundled LLVM, picked by host architecture (VS ships x64 and
    #       ARM64 trees side by side; the wrong one either will not run or
    #       silently produces the wrong machine type)
    #   (4) a standalone LLVM install in the usual place
    #   (5) vcpkg_find_acquire_program(CLANG), which may download LLVM
    #   (6) $ENV{CC} when it names clang-cl
    #   (7) find_program(clang-cl)
    set(_node_clang_cl "")
    if(DEFINED NODE_PORT_LLVM_BIN AND NOT NODE_PORT_LLVM_BIN STREQUAL ""
       AND EXISTS "${NODE_PORT_LLVM_BIN}/clang-cl.exe")
        set(_node_clang_cl "${NODE_PORT_LLVM_BIN}/clang-cl.exe")
    endif()
    if(_node_clang_cl STREQUAL "" AND DEFINED NODE_PORT_LLVM_ROOT AND NOT NODE_PORT_LLVM_ROOT STREQUAL "")
        foreach(_cand "${NODE_PORT_LLVM_ROOT}/x64/bin/clang-cl.exe"
                      "${NODE_PORT_LLVM_ROOT}/bin/clang-cl.exe")
            if(EXISTS "${_cand}")
                set(_node_clang_cl "${_cand}")
                break()
            endif()
        endforeach()
        unset(_cand)
    endif()
    if(_node_clang_cl STREQUAL "" AND DEFINED NODE_PORT_VS_INSTALL_ROOT
       AND NOT NODE_PORT_VS_INSTALL_ROOT STREQUAL "")
        set(_node_llvm_arch_order "")
        if(DEFINED NODE_PORT_HOST_ARCH)
            list(APPEND _node_llvm_arch_order "${NODE_PORT_HOST_ARCH}")
        endif()
        list(APPEND _node_llvm_arch_order x64 ARM64)
        foreach(_arch IN LISTS _node_llvm_arch_order)
            if(EXISTS "${NODE_PORT_VS_INSTALL_ROOT}/VC/Tools/Llvm/${_arch}/bin/clang-cl.exe")
                set(_node_clang_cl "${NODE_PORT_VS_INSTALL_ROOT}/VC/Tools/Llvm/${_arch}/bin/clang-cl.exe")
                break()
            endif()
        endforeach()
        unset(_node_llvm_arch_order)
        unset(_arch)
    endif()
    if(_node_clang_cl STREQUAL "")
        foreach(_cand
            "$ENV{LLVM_ROOT}/bin/clang-cl.exe"
            "$ENV{LLVMInstallDir}/bin/clang-cl.exe"
            "C:/Program Files/LLVM/bin/clang-cl.exe"
            "C:/Program Files (x86)/LLVM/bin/clang-cl.exe")
            if(EXISTS "${_cand}")
                set(_node_clang_cl "${_cand}")
                break()
            endif()
        endforeach()
        unset(_cand)
    endif()
    if(_node_clang_cl STREQUAL "")
        vcpkg_find_acquire_program(CLANG)
        if(DEFINED CLANG AND NOT CLANG STREQUAL "")
            get_filename_component(_clang_bin "${CLANG}" DIRECTORY)
            if(EXISTS "${_clang_bin}/clang-cl.exe")
                set(_node_clang_cl "${_clang_bin}/clang-cl.exe")
            endif()
            unset(_clang_bin)
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
            "node port: clang-cl is required on Windows (Node.js 24+ upstream rule).\n"
            "Looked at NODE_PORT_LLVM_BIN, NODE_PORT_LLVM_ROOT, VS's bundled LLVM\n"
            "(by host architecture), a standalone LLVM install, vcpkg's CLANG\n"
            "acquisition, $ENV{CC} and PATH - none matched. Install Visual Studio's\n"
            "'C++ Clang compiler' component (or a standalone LLVM) and retry.")
    endif()
    # Verify the architecture: a VS that ships both x64 and ARM64 LLVM trees can
    # hand out the wrong one, which fails far away from here.
    if(DEFINED NODE_PORT_HOST_ARCH AND EXISTS "${_node_clang_cl}")
        get_filename_component(_clang_parent "${_node_clang_cl}" DIRECTORY)
        get_filename_component(_clang_llvm_arch "${_clang_parent}" DIRECTORY)
        get_filename_component(_clang_llvm_arch "${_clang_llvm_arch}" NAME)
        if(_clang_llvm_arch MATCHES "^(x64|ARM64|arm64)$"
           AND NOT _clang_llvm_arch STREQUAL "${NODE_PORT_HOST_ARCH}")
            message(FATAL_ERROR
                "node port: found the ${_clang_llvm_arch} clang-cl (${_node_clang_cl}) but "
                "the host is ${NODE_PORT_HOST_ARCH} - the build would produce the wrong "
                "machine type. Point NODE_PORT_LLVM_ROOT at the ${NODE_PORT_HOST_ARCH} tree.")
        endif()
        unset(_clang_parent)
        unset(_clang_llvm_arch)
    endif()
    message(STATUS "node port: clang-cl = ${_node_clang_cl}")
    set(_node_cc "${_node_clang_cl}")
    set(_node_cxx "${_node_clang_cl}")

    # gyp's VS probe reads registry keys modern VS does not write, and its
    # DirectX probe decodes reg.exe output as UTF-8 (dies on a localized code
    # page). Both are avoided by pinning these.
    set(ENV{GYP_MSVS_VERSION} 2022)
    if(NODE_PORT_VS_INSTALL_ROOT)
        set(ENV{GYP_MSVS_OVERRIDE_PATH} "${NODE_PORT_VS_INSTALL_ROOT}")
    endif()
    set(ENV{DXSDK_DIR} "C:/nonexistent")

    # system-icu is resolved through pkg-config; vcpkg's PKGCONFIG is a native
    # Windows build that understands PKG_CONFIG_PATH.
    vcpkg_find_acquire_program(PKGCONFIG)
    set(ENV{PKG_CONFIG} "${PKGCONFIG}")

    # vcpkg's headers go on INCLUDE too: some non-V8 targets (js2c, torque) need
    # simdutf.h and friends, and adding the directory once beats repeating it
    # per target.
    set(ENV{INCLUDE} "${CURRENT_INSTALLED_DIR}/include;$ENV{INCLUDE}")

    # --clang-cl=<ver> makes configure.py set clang=1, which is what turns
    # V8's asm_to_inline_asm action on (otherwise the embedded blob symbols go
    # missing and the link fails).
    execute_process(
        COMMAND "${_node_cc}" --version
        OUTPUT_VARIABLE _clang_version_output
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE)
    string(REGEX REPLACE "^clang version ([0-9]+[.][0-9]+[.][0-9]+).*" "\\1"
           _llvm_version "${_clang_version_output}")
    set(_node_clang_cl_arg "--clang-cl=${_llvm_version}")

    # The patches that probe macros/OpenSSL need the clang.exe sibling and a
    # target triple, and hdr-histogram's __cpu_model needs clang's compiler-rt
    # builtins. Both come from the environment so the patches carry no
    # architecture constants.
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

    # --- CRT: follow VCPKG_CRT_LINKAGE ---
    # Node.js upstream only switches to a dynamic CRT through --shared, which
    # also turns the library into a DLL. For a static library with /MD the port
    # adds the minimal channel - two anchored edits with the same shape:
    #   * configure.py: force_dynamic_crt additionally reads NODE_PORT_FORCE_DYNAMIC_CRT;
    #   * common.gypi: the two MSVC_runtimeType conditions also check force_dynamic_crt.
    # With a static CRT the variable is unset, so both edits are semantically
    # identical to upstream (0 is false). vcpkg_replace_string makes an upstream
    # wording change fail loudly rather than silently.
    if(VCPKG_CRT_LINKAGE STREQUAL "dynamic")
        set(_node_dynamic_crt 1)
        set(ENV{NODE_PORT_FORCE_DYNAMIC_CRT} "1")
        message(STATUS "node port: VCPKG_CRT_LINKAGE=dynamic -> /MD, /MDd")
    else()
        message(STATUS "node port: VCPKG_CRT_LINKAGE=${VCPKG_CRT_LINKAGE} -> /MT, /MTd")
    endif()

    # --- compiler-rt builtins: ship them ---
    # The clang-cl objects reference __cpu_model (__builtin_cpu_supports), and a
    # consumer link (cl.exe's link.exe or lld-link) never pulls in clang's
    # compiler-rt on its own. The port installs the archive and the exported
    # config links it by absolute path, so a consumer without a matching LLVM
    # still links.
    execute_process(
        COMMAND "${_node_cc}" --print-resource-dir
        OUTPUT_VARIABLE _clang_resource_dir
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE)
    if(NOT _clang_resource_dir STREQUAL "")
        file(TO_CMAKE_PATH "${_clang_resource_dir}" _clang_resource_dir)
        set(_rt_cand "${_clang_resource_dir}/lib/windows/clang_rt.builtins-${_node_rt_arch}.lib")
        if(EXISTS "${_rt_cand}")
            set(_node_rt_builtins_lib "${_rt_cand}")
            message(STATUS "node port: compiler-rt builtins ${_rt_cand}")
        else()
            message(FATAL_ERROR
                "node port: compiler-rt builtins not found at ${_rt_cand} "
                "(--print-resource-dir = ${_clang_resource_dir}). A consumer link "
                "would fail on __cpu_model; check the clang-cl installation.")
        endif()
    else()
        message(FATAL_ERROR "node port: clang-cl --print-resource-dir returned nothing (${_node_cc})")
    endif()
    unset(_clang_resource_dir)
    unset(_rt_cand)
else()
    find_program(_node_c_prog NAMES cc gcc clang)
    find_program(_node_cxx_prog NAMES c++ g++ clang++)
    set(_node_cc "${_node_c_prog}")
    set(_node_cxx "${_node_cxx_prog}")
    set(ENV{PKG_CONFIG} "pkg-config")
endif()

# shlex eats backslashes: CC/CXX and PKG_CONFIG use forward slashes.
set(ENV{CC} "${_node_cc}")
set(ENV{CXX} "${_node_cxx}")

# ---------------------------------------------------------------------------
# Apple: system frameworks the static archives drag in.
#
# abseil's time_zone reaches CoreFoundation (cctz), and Node.js's own certificate
# gathering reaches Security. Upstream states both in node.gyp's `libraries` for
# its own build, but the way a consumer links this port is through the exported
# CMake config, which is a different link line - so they have to be stated here
# too, for the port's own host tools (LDFLAGS) and for consumers (the config).
#
# The ninja generator reads LDFLAGS / LDFLAGS_host from the environment when gyp
# runs, which is inside configure.py, so setting them here is enough.
#
# VCPKG_TARGET_IS_OSX rather than APPLE: in port script mode a bare APPLE is
# ambiguous about target versus host, and vcpkg says so on every configure.
# ---------------------------------------------------------------------------
if(VCPKG_TARGET_IS_OSX)
    set(ENV{LDFLAGS} "-framework CoreFoundation -framework Security")
    set(ENV{LDFLAGS_host} "-framework CoreFoundation -framework Security")
endif()

# ---------------------------------------------------------------------------
# The Node.js crates target is built from Rust. The port only needs cargo on
# PATH; it is not something vcpkg can acquire.
# ---------------------------------------------------------------------------
find_program(_node_cargo NAMES cargo)
if(NOT _node_cargo)
    foreach(_cargo_hint
            "$ENV{USERPROFILE}/.cargo/bin/cargo.exe"
            "$ENV{HOME}/.cargo/bin/cargo.exe"
            "$ENV{HOME}/.cargo/bin/cargo"
            "C:/Users/$ENV{USERNAME}/.cargo/bin/cargo.exe")
        if(EXISTS "${_cargo_hint}")
            set(_node_cargo "${_cargo_hint}")
            get_filename_component(_cargo_dir "${_cargo_hint}" DIRECTORY)
            set(ENV{PATH} "${_cargo_dir};$ENV{PATH}")
            break()
        endif()
    endforeach()
endif()
if(NOT _node_cargo)
    message(FATAL_ERROR
        "node port: cargo is required to build Node.js's Temporal C API "
        "(deps/crates). Install a Rust toolchain and make sure cargo is on PATH.")
endif()
message(STATUS "node port: cargo = ${_node_cargo}")

# ---------------------------------------------------------------------------
# 0) Windows: node.gyp's /WHOLEARCHIVE paths are written for the msvs generator
#    (<(PRODUCT_DIR)/lib/...), but the ninja generator puts static libraries
#    under obj/ (and obj/tools/v8_gypfiles/ for V8's). The link then fails with
#    LNK1356. This must happen before configure.py, because the ninja files are
#    generated inside it.
# ---------------------------------------------------------------------------
if(VCPKG_TARGET_IS_WINDOWS)
    vcpkg_replace_string("${SOURCE_PATH}/node.gyp"
        "/WHOLEARCHIVE:<(PRODUCT_DIR)/lib/<(STATIC_LIB_PREFIX)node_base<(STATIC_LIB_SUFFIX)"
        "/WHOLEARCHIVE:<(obj_dir)/<(STATIC_LIB_PREFIX)node_base<(STATIC_LIB_SUFFIX)")
    vcpkg_replace_string("${SOURCE_PATH}/node.gyp"
        "/WHOLEARCHIVE:<(PRODUCT_DIR)/lib/<(STATIC_LIB_PREFIX)v8_base_without_compiler<(STATIC_LIB_SUFFIX)"
        "/WHOLEARCHIVE:<(obj_dir)/tools/v8_gypfiles/<(STATIC_LIB_PREFIX)v8_base_without_compiler<(STATIC_LIB_SUFFIX)")

    # arm64: gyp's ninja generator looks the MSBuild platform up in a
    # case-sensitive map ({'ARM64': 'arm64'}), while common.gypi writes the
    # lowercase 'arm64' - which falls back to 'x86', so clang-cl gets -m32.
    # x64 is unaffected. Only the ninja generator takes this path.
    if(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
        vcpkg_replace_string("${SOURCE_PATH}/common.gypi"
            "'msvs_configuration_platform': 'arm64'"
            "'msvs_configuration_platform': 'ARM64'")
    endif()

    # CRT channel (see the CRT section above): configure.py reads
    # NODE_PORT_FORCE_DYNAMIC_CRT, and common.gypi's two MSVC_runtimeType
    # conditions additionally check force_dynamic_crt.
    vcpkg_replace_string("${SOURCE_PATH}/configure.py"
        "o['variables']['force_dynamic_crt'] = 1 if options.shared else 0"
        "o['variables']['force_dynamic_crt'] = 1 if (options.shared or os.environ.get('NODE_PORT_FORCE_DYNAMIC_CRT') == '1') else 0")
    vcpkg_replace_string("${SOURCE_PATH}/common.gypi"
        "['node_shared != \"true\"', {\n              'MSVC_runtimeType': 1,    # MultiThreadedDebug (/MTd)"
        "['node_shared != \"true\" and force_dynamic_crt != 1', {\n              'MSVC_runtimeType': 1,    # MultiThreadedDebug (/MTd)")
    vcpkg_replace_string("${SOURCE_PATH}/common.gypi"
        "['node_shared != \"true\"', {\n              'MSVC_runtimeType': 0    # MultiThreaded (/MT)"
        "['node_shared != \"true\" and force_dynamic_crt != 1', {\n              'MSVC_runtimeType': 0    # MultiThreaded (/MT)")
endif()

# ---------------------------------------------------------------------------
# macOS: declare the target architecture through Node's own mechanism, always.
#
# Both flags are needed, and they only work together - checked against
# configure.py:1977-1983 and common.gypi:782-790 of the Node.js release this port
# builds:
#   * --dest-cpu=<arch> is what makes common.gypi's `OS=="mac"` block set
#     xcode_settings.ARCHS, which gyp's xcode emulation turns into `-arch <arch>`
#     on every compile and link command. Without it configure.py uses the *host*
#     architecture, and the build then links host-architecture objects against the
#     libraries vcpkg installed for the target.
#   * --no-cross-compiling keeps GYP_CROSSCOMPILE unset, so
#     want_separate_host_toolset stays 0 and every build tool (torque, mksnapshot,
#     js2c) is compiled as the target architecture too. Cross-compiling for real
#     would need host-architecture libraries, which a target triplet does not
#     install; building the tools as the target and running them under Rosetta 2 on
#     an arm64 machine is what this port does instead. The CI leg guards for
#     Rosetta.
#
# They are passed unconditionally rather than only when a host probe reports a
# difference. That probe is a silent-failure trap: a vcpkg portfile runs under
# `cmake -P`, where CMAKE_HOST_SYSTEM_PROCESSOR is not defined, and the variable
# vcpkg does export (VCPKG_DETECTED_CMAKE_HOST_SYSTEM_PROCESSOR) exists only once
# the generated variable file has been asked for. When the probe comes back empty
# the build quietly takes the native path and fails about 1900 targets later, in
# the linker - which is what x64-osx did in run 39020793981 ("cannot determine the
# host architecture ... Treating this as a native build"). Stating the target
# cannot fail that way, and it is what distributions do: Debian, conda, Arch and
# Homebrew all pass --dest-cpu on their own native builds.
#
# Linux and Windows are deliberately left alone: neither has a cross leg in this
# repository's matrix, and their cross-compilation stories (a separate host
# toolset needing host-architecture libraries, clang-cl's -m64 handling) are not
# this macOS mechanism.
# ---------------------------------------------------------------------------
set(_node_dest_cpu_args "")
if(VCPKG_TARGET_IS_OSX)
    if(NOT VCPKG_TARGET_ARCHITECTURE MATCHES "^(x86|x64|arm|arm64)$")
        message(WARNING
            "node port: target architecture ${VCPKG_TARGET_ARCHITECTURE} is not one of "
            "Node's (x86/x64/arm/arm64); not declaring a target architecture, so "
            "configure.py will use the host's.")
    else()
        set(_node_dest_cpu_args
            "--dest-cpu=${VCPKG_TARGET_ARCHITECTURE}"
            "--no-cross-compiling")
        message(STATUS
            "node port: declaring target architecture ${VCPKG_TARGET_ARCHITECTURE} "
            "(--dest-cpu + --no-cross-compiling); the build tools are built for the "
            "target as well")
    endif()
endif()

# ---------------------------------------------------------------------------
# macOS: hand Node.js's build the deployment target the rest of the graph uses.
#
# Node.js pins its own macOS floor in common.gypi ('MACOSX_DEPLOYMENT_TARGET', 13.5),
# and nothing else on macOS agrees with it: every dependency vcpkg builds takes the
# deployment target vcpkg was given - VCPKG_OSX_DEPLOYMENT_TARGET, which a consumer
# states in a triplet - or, when it was given none, the SDK's default, because no
# stock vcpkg triplet pins one. Node.js's own objects are then the only ones in the
# link claiming a different system version, and every macOS build reports it:
#
#   ld: warning: object file (...libicuuc.a[24](errorcode.ao)) was built for newer
#     'macOS' version (15.0) than being linked (13.5)
#
# So the graph's value is handed to node's build through GYP_DEFINES, which overrides
# the gyp variable that patches/0018-macos-deployment-target-from-the-build.patch
# introduces for exactly this (gyp folds GYP_DEFINES into its defines, so a `x%`
# default is overridden the same way a command-line -D would override it). Node's own
# floor stays a lower bound: Node.js cannot be built for an older macOS than it
# supports, while objects built for an older one link into a newer target without
# complaint.
# ---------------------------------------------------------------------------
if(VCPKG_TARGET_IS_OSX)
    # Node's floor is read from the source rather than repeated here, so a Node.js
    # bump cannot leave a stale number behind. Patch 0018 is what puts the variable
    # into common.gypi, so its absence is a defect here, not a variation.
    file(READ "${SOURCE_PATH}/common.gypi" _node_common_gypi)
    string(REGEX MATCH "'node_port_macosx_deployment_target%': '([0-9.]+)'" _node_floor_match
                  "${_node_common_gypi}")
    if(NOT _node_floor_match)
        message(FATAL_ERROR
            "node port: common.gypi has no node_port_macosx_deployment_target% default. Either "
            "patches/0018-macos-deployment-target-from-the-build.patch did not apply or upstream "
            "moved the macOS deployment target; the value cannot be handed to the build without it.")
    endif()
    set(_node_macos_floor "${CMAKE_MATCH_1}")
    unset(_node_common_gypi)
    unset(_node_floor_match)

    # What the graph builds for. A consumer who states VCPKG_OSX_DEPLOYMENT_TARGET gets
    # exactly that; otherwise the value is read off a dependency, because vcpkg's own
    # detection reports the variable - empty here - and not the SDK default it falls
    # back to. zlib is a dependency of this port, so its library is always installed.
    set(_node_macos_target "${VCPKG_OSX_DEPLOYMENT_TARGET}")
    if(_node_macos_target STREQUAL "")
        foreach(_cand
            "${CURRENT_INSTALLED_DIR}/lib/libz.a"
            "${CURRENT_INSTALLED_DIR}/lib/libz.dylib"
            "${CURRENT_INSTALLED_DIR}/lib/libcrypto.a"
            "${CURRENT_INSTALLED_DIR}/lib/libcrypto.dylib")
            if(NOT EXISTS "${_cand}")
                continue()
            endif()
            execute_process(COMMAND /usr/bin/otool -l "${_cand}"
                            OUTPUT_VARIABLE _node_otool_out ERROR_QUIET)
            if(_node_otool_out MATCHES "minos ([0-9]+(\\.[0-9]+)?)")
                set(_node_macos_target "${CMAKE_MATCH_1}")
            elseif(_node_otool_out MATCHES "LC_VERSION_MIN_MACOSX[^;]*version ([0-9]+(\\.[0-9]+)?)")
                set(_node_macos_target "${CMAKE_MATCH_1}")
            endif()
            unset(_node_otool_out)
            if(NOT _node_macos_target STREQUAL "")
                break()
            endif()
        endforeach()
        unset(_cand)
    endif()

    if(_node_macos_target STREQUAL "")
        message(WARNING
            "node port: no macOS deployment target could be determined: VCPKG_OSX_DEPLOYMENT_TARGET "
            "is unset and no dependency library could be read. Node.js keeps its own floor "
            "${_node_macos_floor}, while the dependencies were built with whatever vcpkg used by "
            "default - which is newer - so the link will warn about every one of them. State the "
            "value with VCPKG_OSX_DEPLOYMENT_TARGET in your triplet to make them agree.")
        set(_node_macos_target "${_node_macos_floor}")
    elseif(_node_macos_target VERSION_LESS "${_node_macos_floor}")
        message(STATUS
            "node port: the graph builds for macOS ${_node_macos_target}, which is below Node.js's own "
            "floor ${_node_macos_floor}; node's build stays at the floor")
        set(_node_macos_target "${_node_macos_floor}")
    endif()

    set(ENV{GYP_DEFINES} "node_port_macosx_deployment_target=${_node_macos_target}")
    message(STATUS
        "node port: node's macOS deployment target ${_node_macos_target} (Node.js floor "
        "${_node_macos_floor}, graph ${VCPKG_OSX_DEPLOYMENT_TARGET})")
endif()

# ---------------------------------------------------------------------------
# 1) Feed vcpkg's dependencies to configure.py as --shared-*.
#    Library names are the real file names in the vcpkg package. On Windows
#    static there are a few differences (zlib -> zs, brotli without the lib
#    prefix, openssl keeps it). pkg-config does not exist on Windows, so the
#    library list has to be passed explicitly or nothing is added to the link
#    line at all.
#
#    Debug builds must link the dependencies' debug libraries, otherwise
#    _ITERATOR_DEBUG_LEVEL does not match.
# ---------------------------------------------------------------------------
function(_node_shared_args _out _libdir _is_debug)
    if(VCPKG_TARGET_IS_WINDOWS)
        set(_zlib_lib    "zs")
        set(_openssl_lib "libcrypto,libssl")
        set(_libuv_lib   "libuv")
        set(_absl_prefix "absl_")
        set(_absl_suffix ".lib")
        set(_hwy_lib     "hwy")
        # vcpkg's spdlog and fmt add the usual debug postfix.
        if(_is_debug)
            set(_spdlog_lib "spdlogd")
            set(_fmt_lib    "fmtd")
        else()
            set(_spdlog_lib "spdlog")
            set(_fmt_lib    "fmt")
        endif()
    else()
        set(_zlib_lib    "z")
        set(_openssl_lib "crypto,ssl")
        set(_libuv_lib   "uv")
        # The CI triplets on Unix are release-only, so only the release names
        # are exercised there; the debug postfix is a CMake-level convention
        # that holds on Unix too, but that combination is unverified.
        if(_is_debug)
            set(_spdlog_lib "spdlogd")
            set(_fmt_lib    "fmtd")
        else()
            set(_spdlog_lib "spdlog")
            set(_fmt_lib    "fmt")
        endif()
        set(_absl_prefix "libabsl_")
        set(_absl_suffix ".a")
        set(_hwy_lib     "hwy")
    endif()

    # abseil is split into ~90 archives; Node's own pkg-config list names only
    # part of them, so take every installed name.
    file(GLOB _absl_files RELATIVE "${_libdir}" "${_libdir}/${_absl_prefix}*${_absl_suffix}")
    set(_absl_libnames "")
    foreach(_f IN LISTS _absl_files)
        get_filename_component(_f "${_f}" NAME_WE)
        string(REGEX REPLACE "^lib" "" _f "${_f}")
        list(APPEND _absl_libnames "${_f}")
    endforeach()
    unset(_absl_files)
    unset(_f)
    list(JOIN _absl_libnames "," _absl_libnames)

    set(_hdrhist_lib "hdr_histogram_static")
    set(_args "")
    foreach(_spec
        "openssl|${_openssl_lib}"
        "zlib|${_zlib_lib}"
        "libuv|${_libuv_lib}"
        "cares|cares"
        "brotli|brotlidec,brotlienc,brotlicommon"
        "nghttp2|nghttp2"
        "ngtcp2|ngtcp2"
        # vcpkg's nghttp3 port devendors sfparse (001-devendor-sfparse.patch) and
        # its own libnghttp3.pc carries "Libs.private: -lsfparse", so the static
        # library leaves sfparse_* undefined: the link line needs it as well.
        # Order matters - nghttp3 references sfparse, not the other way round.
        "nghttp3|nghttp3,sfparse"
        "http-parser|llhttp"
        "zstd|zstd"
        "simdjson|simdjson"
        "simdutf|simdutf"
        "sqlite|sqlite3"
        "ada|ada"
        "hdr-histogram|${_hdrhist_lib}"
        "abseil|${_absl_libnames}"
        "highway|${_hwy_lib}"
        "ffi|ffi"
        # perfetto is deliberately absent: --shared-perfetto is gated on
        # --with-perfetto in configure.py, and enabling it trips a V8 gyp gap
        # in the shared-SDK path (v8_libplatform loses trace-object.cc from its
        # source list while legacy tracing members still reference
        # TraceObject::~TraceObject, so mksnapshot fails to link). perfetto
        # tracing is an opt-in embedder feature that Node's own release build
        # does not enable, so the channel stays unwired until that is fixed;
        # ports/perfetto is ready and the issue is written up in docs.
        # "perfetto|perfetto"
        # LIEF is a C++ static library whose own TUs use spdlog (which is built
        # against external fmt) and mbedtls directly, so a consumer has to put
        # the providers after it on the link line - exactly what LIEFConfig.cmake
        # does for CMake consumers through find_dependency. Order: consumers
        # first, providers later (mbedx509 references tfpsacrypto symbols).
        # bcrypt is mbedtls's Windows entropy source (BCryptGenRandom); LIEF's
        # own CMake adds it on WIN32 for the same reason. LIEF, mbedtls and
        # bcrypt keep their names in the debug tree; spdlog/fmt carry the d
        # postfix, hence the per-config names above.
        "lief|LIEF,${_spdlog_lib},${_fmt_lib},mbedx509,tfpsacrypto,bcrypt")
        string(REPLACE "|" ";" _pair "${_spec}")
        list(GET _pair 0 _opt)
        list(GET _pair 1 _libnames)
        list(APPEND _args
            "--shared-${_opt}"
            "--shared-${_opt}-includes=${CURRENT_INSTALLED_DIR}/include"
            "--shared-${_opt}-libpath=${_libdir}"
            "--shared-${_opt}-libname=${_libnames}")
    endforeach()
    unset(_spec)
    unset(_pair)
    unset(_opt)
    unset(_libnames)
    set(${_out} "${_args}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# 2) Build loop: configure.py -> gyp -f ninja -> ninja, once per configuration.
# ---------------------------------------------------------------------------
set(_node_ninja_jobs "")
if(DEFINED VCPKG_CONCURRENCY AND NOT VCPKG_CONCURRENCY STREQUAL "")
    set(_node_ninja_jobs "-j${VCPKG_CONCURRENCY}")
endif()

set(_node_installed_libs "")

foreach(_node_cfg IN LISTS _node_configs)
    if(_node_cfg STREQUAL "Debug")
        set(_node_cfg_arg "--debug")
        set(_node_is_debug TRUE)
        set(_node_lib_dir "${CURRENT_INSTALLED_DIR}/debug/lib")
        set(ENV{PKG_CONFIG_PATH} "${CURRENT_INSTALLED_DIR}/debug/lib/pkgconfig")
        set(ENV{LIB} "${_node_lib_dir};$ENV{LIB}")
    else()
        set(_node_cfg_arg "")
        set(_node_is_debug FALSE)
        set(_node_lib_dir "${CURRENT_INSTALLED_DIR}/lib")
        set(ENV{PKG_CONFIG_PATH} "${CURRENT_INSTALLED_DIR}/lib/pkgconfig")
        set(ENV{LIB} "${_node_lib_dir};$ENV{LIB}")
    endif()


    _node_shared_args(_node_shared_args "${_node_lib_dir}" "${_node_is_debug}")

    vcpkg_execute_required_process(
        COMMAND "${PYTHON3}" configure.py
            --ninja
            ${_node_cfg_arg}
            ${_node_clang_cl_arg}
            ${_node_dest_cpu_args}
            --with-intl=system-icu
            ${_node_shared_args}
            "-DVCPKG_SIMDUTF_INCLUDE=${CURRENT_INSTALLED_DIR}/include"
        WORKING_DIRECTORY "${SOURCE_PATH}"
        LOGNAME "configure-${_node_cfg}"
    )

    set(_node_ninja_targets libnode)
    if(_node_cfg STREQUAL "Release" AND "tools" IN_LIST FEATURES)
        list(APPEND _node_ninja_targets node)
    endif()

    vcpkg_execute_required_process(
        COMMAND "${NINJA}" -C "${SOURCE_PATH}/out/${_node_cfg}" ${_node_ninja_jobs} ${_node_ninja_targets}
        WORKING_DIRECTORY "${SOURCE_PATH}"
        LOGNAME "build-${_node_cfg}"
    )

    # -----------------------------------------------------------------------
    # Ask the generated build graph whether any library this port externalizes
    # is *also* compiled from its vendored copy.
    #
    # The --shared-* switches remove dependency edges, but a target that pulls a
    # vendored gyp in unconditionally still compiles it - simdutf.gyp arrives
    # through ada.gyp that way, which is what patch 0011 had to gate. Nothing
    # downstream reports the result: the linker silently picks one definition and
    # the consumer finds out later, as an unexplained duplicate symbol. The graph
    # states every source it compiles, so one pass over it is the whole check.
    # -----------------------------------------------------------------------
    vcpkg_execute_required_process(
        COMMAND "${PYTHON3}" "${CMAKE_CURRENT_LIST_DIR}/scripts/check_no_vendored_build.py"
                --build-dir "${SOURCE_PATH}/out/${_node_cfg}"
        WORKING_DIRECTORY "${SOURCE_PATH}"
        LOGNAME "vendored-check-${_node_cfg}"
    )
endforeach()

# ---------------------------------------------------------------------------
# 3) Install headers, the gyp archives, compiler-rt and the consumer config.
# ---------------------------------------------------------------------------
file(INSTALL "${SOURCE_PATH}/src/" DESTINATION "${CURRENT_PACKAGES_DIR}/include/node"
    FILES_MATCHING PATTERN "*.h" PATTERN "*.hpp")
# V8's headers live under include/node-v8, not the include root: vcpkg's Unique
# File Mapping Rule forbids two ports installing the same file, and the official
# `v8` port installs include/v8.h. The consumer config adds this directory to
# the include path, so `#include <v8.h>` still resolves.
file(INSTALL "${SOURCE_PATH}/deps/v8/include/" DESTINATION "${CURRENT_PACKAGES_DIR}/include/node-v8")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/include/node/api" "${CURRENT_PACKAGES_DIR}/include/node/res")

if(VCPKG_TARGET_IS_WINDOWS)
    set(_node_lib_suffix ".lib")
else()
    set(_node_lib_suffix ".a")
endif()

foreach(_node_cfg IN LISTS _node_configs)
    if(_node_cfg STREQUAL "Debug")
        set(_node_out_dir "${SOURCE_PATH}/out/Debug")
        set(_node_pkg_lib_dir "${CURRENT_PACKAGES_DIR}/debug/lib")
    else()
        set(_node_out_dir "${SOURCE_PATH}/out/Release")
        set(_node_pkg_lib_dir "${CURRENT_PACKAGES_DIR}/lib")
    endif()

    # Windows/macOS: gyp puts static libraries under obj/ (recursively) and, on
    # macOS, static_library lands in the output root as well.  Rust crates
    # (node_crates) land under gen/ on Windows.
    file(GLOB_RECURSE _node_archives "${_node_out_dir}/obj/*${_node_lib_suffix}")
    file(GLOB _node_archives_root "${_node_out_dir}/*${_node_lib_suffix}")
    list(APPEND _node_archives ${_node_archives_root})
    file(GLOB_RECURSE _node_gen_archives "${_node_out_dir}/gen/*${_node_lib_suffix}")
    foreach(_g IN LISTS _node_gen_archives)
        get_filename_component(_gname "${_g}" NAME)
        if(_gname MATCHES "^[a-zA-Z_]+${_node_lib_suffix}$")
            list(APPEND _node_archives "${_g}")
        endif()
    endforeach()
    unset(_g)
    unset(_gname)
    unset(_node_gen_archives)
    file(INSTALL ${_node_archives} DESTINATION "${_node_pkg_lib_dir}")

    if(_node_rt_builtins_lib)
        file(INSTALL "${_node_rt_builtins_lib}" DESTINATION "${_node_pkg_lib_dir}")
    endif()

    if(_node_cfg STREQUAL "Release")
        set(_node_installed_libs "")
        foreach(_a IN LISTS _node_archives)
            get_filename_component(_n "${_a}" NAME)
            list(APPEND _node_installed_libs "${_n}")
        endforeach()
        list(REMOVE_DUPLICATES _node_installed_libs)
        unset(_n)
    endif()
    unset(_node_archives)
    unset(_node_archives_root)
endforeach()
unset(_node_out_dir)
unset(_node_pkg_lib_dir)

if(VCPKG_TARGET_IS_WINDOWS)
    file(INSTALL "${SOURCE_PATH}/src/res/node.exe.extra.manifest"
        DESTINATION "${CURRENT_PACKAGES_DIR}/share/node" RENAME node.exe.extra.manifest)
endif()

# ---------------------------------------------------------------------------
# 4) tools feature: node executable + npm / npx / corepack.
# ---------------------------------------------------------------------------
if("tools" IN_LIST FEATURES)
    set(_node_tools "${CURRENT_PACKAGES_DIR}/tools/${PORT}")
    if(VCPKG_TARGET_IS_WINDOWS)
        file(INSTALL "${SOURCE_PATH}/out/Release/node.exe" DESTINATION "${_node_tools}")
    else()
        file(INSTALL "${SOURCE_PATH}/out/Release/node" DESTINATION "${_node_tools}"
            FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                            GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
    endif()
    file(INSTALL "${SOURCE_PATH}/deps/npm/" DESTINATION "${_node_tools}/node_modules/npm"
        USE_SOURCE_PERMISSIONS)
    if(EXISTS "${SOURCE_PATH}/deps/corepack/package.json")
        file(INSTALL "${SOURCE_PATH}/deps/corepack/" DESTINATION "${_node_tools}/node_modules/corepack"
            USE_SOURCE_PERMISSIONS)
    endif()
    foreach(_shim IN ITEMS npm npx)
        file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/scripts/${_shim}" DESTINATION "${_node_tools}"
            RENAME "${_shim}"
            FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                            GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
        file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/scripts/${_shim}.cmd" DESTINATION "${_node_tools}"
            RENAME "${_shim}.cmd")
    endforeach()
    if(EXISTS "${SOURCE_PATH}/deps/corepack/package.json")
        file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/scripts/corepack" DESTINATION "${_node_tools}"
            RENAME "corepack"
            FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                            GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
        file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/scripts/corepack.cmd" DESTINATION "${_node_tools}"
            RENAME "corepack.cmd")
    endif()
    unset(_shim)
endif()

# ---------------------------------------------------------------------------
# 5) test-suite feature: the official test tree and the tools/test.py driver.
# ---------------------------------------------------------------------------
if("test-suite" IN_LIST FEATURES)
    set(_node_suite "${CURRENT_PACKAGES_DIR}/share/node/test-suite")
    # USE_SOURCE_PERMISSIONS: file(INSTALL) defaults to 0644/0755 and would drop
    # the executable bits the suite relies on for its fixture scripts.
    file(INSTALL "${SOURCE_PATH}/test/" DESTINATION "${_node_suite}/test" USE_SOURCE_PERMISSIONS)
    file(INSTALL "${SOURCE_PATH}/tools/" DESTINATION "${_node_suite}/tools" USE_SOURCE_PERMISSIONS)
    file(INSTALL "${SOURCE_PATH}/benchmark/" DESTINATION "${_node_suite}/benchmark" USE_SOURCE_PERMISSIONS)
    file(INSTALL "${SOURCE_PATH}/doc/" DESTINATION "${_node_suite}/doc" USE_SOURCE_PERMISSIONS)
    file(INSTALL "${SOURCE_PATH}/lib/" DESTINATION "${_node_suite}/lib" USE_SOURCE_PERMISSIONS)
    file(INSTALL "${SOURCE_PATH}/src/" DESTINATION "${_node_suite}/src" USE_SOURCE_PERMISSIONS
        FILES_MATCHING PATTERN "*.h" PATTERN "*.hpp" PATTERN "*.cc")
    file(INSTALL "${SOURCE_PATH}/CHANGELOG.md" DESTINATION "${_node_suite}")
    foreach(_dep IN ITEMS npm corepack acorn undici)
        if(EXISTS "${SOURCE_PATH}/deps/${_dep}")
            file(INSTALL "${SOURCE_PATH}/deps/${_dep}" DESTINATION "${_node_suite}/deps"
                USE_SOURCE_PERMISSIONS)
        endif()
    endforeach()
    unset(_dep)
    if(EXISTS "${SOURCE_PATH}/deps/v8/src/objects/intl-objects.h")
        file(INSTALL "${SOURCE_PATH}/deps/v8/src/objects/intl-objects.h"
            DESTINATION "${_node_suite}/deps/v8/src/objects")
    endif()
endif()

# ---------------------------------------------------------------------------
# 6) Consumer config (unofficial-node).
#    The libraries are gyp artifacts, not CMake targets, so the config is
#    written by hand rather than with install(EXPORT).
# ---------------------------------------------------------------------------
function(_node_archive_filename _target _out)
    if(VCPKG_TARGET_IS_WINDOWS)
        set(${_out} "${_target}.lib" PARENT_SCOPE)
    else()
        # gyp strips a leading "lib" from the target name before adding its own
        # prefix, so target `libnode` yields libnode.a, `node_base` yields
        # libnode_base.a.
        string(REGEX REPLACE "^lib" "" _stripped "${_target}")
        set(${_out} "lib${_stripped}.a" PARENT_SCOPE)
    endif()
endfunction()

set(_cfg "# Generated by the node port: CMake consumer config for Node.js.\n")
string(APPEND _cfg "include(CMakeFindDependencyMacro)\n")
# Two things have to be solved around zlib, and neither is obvious:
#
#   1. Which imported name exists is not ours to choose. vcpkg's zlib ships a config file
#      that exports ZLIB::ZLIBSTATIC, and ZLIB::ZLIB only appears when the vcpkg toolchain
#      intercepts the lookup through its cmake wrapper. Depending on one of the two would
#      silently tie this config to being used together with the vcpkg toolchain, so pick
#      whichever exists and normalize it onto unofficial::node::zlib.
#   2. hdr_histogram's config asks for ZLIB in *module* mode, and FindZLIB cannot find
#      zs.lib (the Windows static name) by itself - so do it here and hand FindZLIB the
#      cache variables it needs. The location itself is usually only set per configuration
#      (IMPORTED_LOCATION_<CONFIG>), which is why reading IMPORTED_LOCATION alone is not
#      enough.
string(APPEND _cfg
    "find_dependency(ZLIB CONFIG)\n"
    "if(NOT TARGET unofficial::node::zlib)\n"
    "  add_library(unofficial::node::zlib INTERFACE IMPORTED)\n"
    "  if(TARGET ZLIB::ZLIB)\n"
    "    set(_node_zlib_target ZLIB::ZLIB)\n"
    "  elseif(TARGET ZLIB::ZLIBSTATIC)\n"
    "    set(_node_zlib_target ZLIB::ZLIBSTATIC)\n"
    "  else()\n"
    "    message(FATAL_ERROR\n"
    "      \"This node install needs zlib, and neither ZLIB::ZLIB nor ZLIB::ZLIBSTATIC was \"\n"
    "      \"exported by the zlib that was found. Check the zlib package.\")\n"
    "  endif()\n"
    "  set_target_properties(unofficial::node::zlib PROPERTIES\n"
    "    INTERFACE_LINK_LIBRARIES \"\${_node_zlib_target}\")\n"
    "  set(_node_zlib_loc \"\")\n"
    "  get_target_property(_node_zlib_configs \${_node_zlib_target} IMPORTED_CONFIGURATIONS)\n"
    "  foreach(_node_zlib_config IN LISTS _node_zlib_configs)\n"
    "    get_target_property(_node_zlib_config_loc \${_node_zlib_target}\n"
    "      IMPORTED_LOCATION_\${_node_zlib_config})\n"
    "    if(_node_zlib_config_loc AND\n"
    "       (_node_zlib_config STREQUAL \"RELEASE\" OR _node_zlib_loc STREQUAL \"\"))\n"
    "      set(_node_zlib_loc \"\${_node_zlib_config_loc}\")\n"
    "    endif()\n"
    "  endforeach()\n"
    "  if(NOT _node_zlib_loc)\n"
    "    get_target_property(_node_zlib_loc \${_node_zlib_target} IMPORTED_LOCATION)\n"
    "  endif()\n"
    "  if(_node_zlib_loc)\n"
    "    set(ZLIB_LIBRARY \"\${_node_zlib_loc}\" CACHE FILEPATH \"Path to zlib library\")\n"
    "  endif()\n"
    "  get_target_property(_node_zlib_inc \${_node_zlib_target} INTERFACE_INCLUDE_DIRECTORIES)\n"
    "  if(_node_zlib_inc)\n"
    "    set(ZLIB_INCLUDE_DIR \"\${_node_zlib_inc}\" CACHE PATH \"Path to zlib headers\")\n"
    "  endif()\n"
    "  unset(_node_zlib_target)\n"
    "  unset(_node_zlib_configs)\n"
    "  unset(_node_zlib_config)\n"
    "  unset(_node_zlib_config_loc)\n"
    "  unset(_node_zlib_loc)\n"
    "  unset(_node_zlib_inc)\n"
    "endif()\n")
foreach(_dep "OpenSSL" "libuv CONFIG" "llhttp CONFIG" "c-ares CONFIG"
             "unofficial-brotli CONFIG" "ada CONFIG" "simdjson CONFIG"
             "simdutf CONFIG" "ngtcp2 CONFIG" "zstd CONFIG"
             "ICU COMPONENTS uc i18n data" "unofficial-sqlite3 CONFIG"
             "hdr_histogram CONFIG" "hwy CONFIG")
    string(APPEND _cfg "find_dependency(${_dep})\n")
endforeach()
unset(_dep)
string(APPEND _cfg
    "get_filename_component(_node_prefix \"\${CMAKE_CURRENT_LIST_DIR}/../..\" ABSOLUTE)\n"
    "set(_node_lib \"\${_node_prefix}/lib\")\n"
    "set(node_INSTALLED_LIBRARIES \"${_node_installed_libs}\")\n")

# release-only install + a Debug consumer: fail at configure time rather than
# link time (LNK2038 RuntimeLibrary).
if(VCPKG_TARGET_IS_WINDOWS)
    string(APPEND _cfg
        "if(CMAKE_BUILD_TYPE STREQUAL \"Debug\" AND NOT EXISTS \"\${_node_prefix}/debug/lib\")\n"
        "  message(FATAL_ERROR\n"
        "    \"This node install is release-only (VCPKG_BUILD_TYPE=release); there is no debug library.\\n\"\n"
        "    \"On Windows a Debug consumer (/MTd or /MDd) cannot link a Release (/MT or /MD) node.\\n\"\n"
        "    \"Use a dual triplet (e.g. x64-windows-static) or build the consumer as Release.\")\n"
        "endif()\n")
    if(VCPKG_CRT_LINKAGE STREQUAL "static")
        string(APPEND _cfg
            "if(MSVC AND (NOT DEFINED CMAKE_MSVC_RUNTIME_LIBRARY"
            " OR CMAKE_MSVC_RUNTIME_LIBRARY STREQUAL \"\""
            " OR CMAKE_MSVC_RUNTIME_LIBRARY MATCHES \"DLL\"))\n"
            "  message(FATAL_ERROR\n"
            "    \"This node install uses the static CRT (/MT) but the consumer's CMake\\n\"\n"
            "    \"defaults to the dynamic one (/MD): CMAKE_MSVC_RUNTIME_LIBRARY = '\${CMAKE_MSVC_RUNTIME_LIBRARY}'.\\n\"\n"
            "    \"Set it yourself, e.g. set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreaded), or\\n\"\n"
            "    \"set(CMAKE_MSVC_RUNTIME_LIBRARY \\\"MultiThreaded$<$<CONFIG:Debug>:Debug>\\\") for Debug.\\n\"\n"
            "    \"Otherwise the link fails with a wall of LNK2038 RuntimeLibrary mismatches.\")\n"
            "endif()\n")
    else()
        string(APPEND _cfg
            "if(MSVC AND DEFINED CMAKE_MSVC_RUNTIME_LIBRARY"
            " AND NOT CMAKE_MSVC_RUNTIME_LIBRARY STREQUAL \"\""
            " AND NOT CMAKE_MSVC_RUNTIME_LIBRARY MATCHES \"DLL\")\n"
            "  message(FATAL_ERROR\n"
            "    \"This node install uses the dynamic CRT (/MD) but the consumer was set to the\\n\"\n"
            "    \"static one: '\${CMAKE_MSVC_RUNTIME_LIBRARY}'. The two must match.\")\n"
            "endif()\n")
    endif()
endif()

if("tools" IN_LIST FEATURES)
    if(VCPKG_TARGET_IS_WINDOWS)
        set(_node_exe_name "node.exe")
        set(_node_shim_ext ".cmd")
    else()
        set(_node_exe_name "node")
        set(_node_shim_ext "")
    endif()
    string(APPEND _cfg
        "set(node_TOOLS_DIR \"\${_node_prefix}/tools/node\")\n"
        "set(node_EXECUTABLE \"\${_node_prefix}/tools/node/${_node_exe_name}\")\n"
        "set(node_NPM \"\${_node_prefix}/tools/node/npm${_node_shim_ext}\")\n"
        "set(node_NPX \"\${_node_prefix}/tools/node/npx${_node_shim_ext}\")\n")
    if(EXISTS "${SOURCE_PATH}/deps/corepack/package.json")
        string(APPEND _cfg
            "set(node_COREPACK \"\${_node_prefix}/tools/node/corepack${_node_shim_ext}\")\n")
    endif()
endif()

# Everything gyp produces for a Node.js build. abseil/highway/simdutf/zlib come
# from vcpkg; v8_zlib remains (patched down to compression_utils_portable.cc, so
# it defines no zlib core symbols).
set(_node_all_archives
    libnode node_base
    v8_base_without_compiler v8_compiler v8_init v8_initializers
    v8_snapshot v8_libbase v8_libplatform v8_zlib
    ncrypto ncrypto_engine nbytes merve uvwasi crdtp node_crates
    liblief libffi)
set(_node_archive_links "")
foreach(_a IN LISTS _node_all_archives)
    _node_archive_filename("${_a}" _file)
    string(APPEND _cfg
        "if(NOT TARGET unofficial::node::${_a})\n"
        "  add_library(unofficial::node::${_a} STATIC IMPORTED)\n"
        "  set_target_properties(unofficial::node::${_a} PROPERTIES IMPORTED_LOCATION"
        " \"\${_node_lib}/${_file}\")\n")
    if("Debug" IN_LIST _node_configs)
        string(APPEND _cfg
            "  set_target_properties(unofficial::node::${_a} PROPERTIES IMPORTED_LOCATION_DEBUG"
            " \"\${_node_prefix}/debug/lib/${_file}\")\n")
    endif()
    string(APPEND _cfg "endif()\n")
    string(APPEND _node_archive_links " unofficial::node::${_a}")
endforeach()
unset(_a)
unset(_file)

# abseil ships one archive per component and its vcpkg config exposes them as
# individual absl::<component> targets with no aggregate, so import them by file
# name here. That stays correct across abseil versions without tracking target
# names, and the archives always sit in the same prefix as this port.
string(APPEND _cfg
    "file(GLOB _node_absl_libs \"\${_node_lib}/absl_*.lib\" \"\${_node_lib}/libabsl_*.a\")\n"
    "foreach(_l IN LISTS _node_absl_libs)\n"
    "  get_filename_component(_n \"\${_l}\" NAME_WE)\n"
    "  string(REGEX REPLACE \"^lib\" \"\" _n \"\${_n}\")\n"
    "  if(NOT TARGET unofficial::node::\${_n})\n"
    "    add_library(unofficial::node::\${_n} STATIC IMPORTED)\n"
    "    set_target_properties(unofficial::node::\${_n} PROPERTIES IMPORTED_LOCATION \"\${_l}\")\n")
if("Debug" IN_LIST _node_configs)
    string(APPEND _cfg
        "    if(EXISTS \"\${_node_prefix}/debug/lib/\${_n}.lib\")\n"
        "      set_target_properties(unofficial::node::\${_n} PROPERTIES IMPORTED_LOCATION_DEBUG \"\${_node_prefix}/debug/lib/\${_n}.lib\")\n"
        "    elseif(EXISTS \"\${_node_prefix}/debug/lib/lib\${_n}.a\")\n"
        "      set_target_properties(unofficial::node::\${_n} PROPERTIES IMPORTED_LOCATION_DEBUG \"\${_node_prefix}/debug/lib/lib\${_n}.a\")\n"
        "    endif()\n")
endif()
string(APPEND _cfg
    "  endif()\n"
    "  list(APPEND _node_absl_links unofficial::node::\${_n})\n"
    "endforeach()\n")

string(APPEND _cfg
    "add_library(unofficial::node::node INTERFACE IMPORTED)\n"
    "set_target_properties(unofficial::node::node PROPERTIES"
    " INTERFACE_INCLUDE_DIRECTORIES"
    " \"\${_node_prefix}/include;\${_node_prefix}/include/node;\${_node_prefix}/include/node-v8\")\n"
    "set_property(TARGET unofficial::node::node PROPERTY INTERFACE_COMPILE_FEATURES cxx_std_20)\n")
if(VCPKG_TARGET_IS_WINDOWS)
    string(APPEND _cfg
        "if(MSVC AND NOT CMAKE_CXX_COMPILER_ID MATCHES \"Clang\")\n"
        "  target_compile_options(unofficial::node::node INTERFACE \"/Zc:__cplusplus\")\n"
        "endif()\n")
endif()

# nghttp2 ships no CMake config; build an imported target for it.
string(APPEND _cfg
    "find_library(_nghttp2_lib nghttp2 HINTS \${_node_lib} REQUIRED)\n"
    "if(NOT TARGET unofficial::node::nghttp2)\n"
    "  add_library(unofficial::node::nghttp2 STATIC IMPORTED)\n"
    "  set_target_properties(unofficial::node::nghttp2 PROPERTIES IMPORTED_LOCATION \"\${_nghttp2_lib}\")\n")
if("Debug" IN_LIST _node_configs)
    _node_archive_filename("nghttp2" _nghttp2_file)
    string(APPEND _cfg
        "  set_target_properties(unofficial::node::nghttp2 PROPERTIES IMPORTED_LOCATION_DEBUG"
        " \"\${_node_prefix}/debug/lib/${_nghttp2_file}\")\n")
endif()
string(APPEND _cfg "endif()\n")

# The gyp archives have real cycles (libnode <-> node_base, v8_compiler ->
# v8_base_without_compiler). Windows' link.exe rescans the whole list, and Apple's
# ld64 has no rescan construct, so both are flat; GNU linkers get CMake's
# $<LINK_GROUP:RESCAN>.
string(APPEND _cfg
    "set(_node_archives_link ${_node_archive_links})\n"
    "set(_node_deps_link OpenSSL::SSL OpenSSL::Crypto libuv::uv_a c-ares::cares\n"
    "    unofficial::brotli::brotlidec unofficial::brotli::brotlienc\n"
    "    unofficial::brotli::brotlicommon unofficial::node::zlib ada::ada simdjson::simdjson\n"
    "    simdutf::simdutf ngtcp2::ngtcp2_static zstd::libzstd_static\n"
    "    ICU::uc ICU::i18n ICU::data unofficial::sqlite3::sqlite3\n"
    "    hdr_histogram::hdr_histogram_static unofficial::node::nghttp2 llhttp::llhttp_static\n"
    "    hwy::hwy \${_node_absl_links})\n")
if(VCPKG_TARGET_IS_WINDOWS OR VCPKG_TARGET_IS_OSX)
    string(APPEND _cfg
        "target_link_libraries(unofficial::node::node INTERFACE \${_node_archives_link} \${_node_deps_link})\n")
else()
    string(APPEND _cfg
        "if(CMAKE_VERSION VERSION_LESS 3.24)\n"
        "  message(FATAL_ERROR \"This port uses \$<LINK_GROUP:RESCAN> (CMake 3.24).\")\n"
        "endif()\n"
        "set(_node_group_items \${_node_archives_link} \${_node_deps_link})\n"
        "string(REPLACE \";\" \",\" _node_group_items \"\${_node_group_items}\")\n"
        "target_link_libraries(unofficial::node::node INTERFACE \"\$<LINK_GROUP:RESCAN,\${_node_group_items}>\")\n")
endif()
if(VCPKG_TARGET_IS_OSX)
    string(APPEND _cfg
        "target_link_libraries(unofficial::node::node INTERFACE"
        " \"-framework CoreFoundation\" \"-framework Security\")\n")
endif()

if(VCPKG_TARGET_IS_WINDOWS)
    # winmm: V8's timeGetTime. compiler-rt builtins: __cpu_model.
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
    # System libraries node.exe itself links. crypt32 is not optional decoration: OpenSSL's
    # CAPI and winstore providers need the Windows certificate APIs, and Node.js's own
    # GatherCertsForLocation needs them too. Depending on how OpenSSL was located (vcpkg's
    # config file hands multi-config consumers over to module mode), those dependencies do
    # not always arrive with OpenSSL::Crypto, so they are stated here.
    string(APPEND _cfg
        "endif()\n"
        "target_link_libraries(unofficial::node::node INTERFACE\n"
        "  winmm ntdll bcrypt crypt32 ws2_32 unofficial::node::clang_rt_builtins)\n")

    # Stack size: upstream node.gyp sets StackReserveSize 0x800000, but that only
    # applies to the executable gyp builds. A consumer's executable (built by
    # its own CMake) would otherwise get the linker default of 1 MiB, which is
    # too small for some V8/inspector paths. Read the value from node.gyp rather
    # than hard-coding it.
    file(READ "${SOURCE_PATH}/node.gyp" _node_gyp_text)
    string(REGEX MATCHALL "'StackReserveSize'[^0-9]*0x[0-9A-Fa-f]+" _node_stack_hits "${_node_gyp_text}")
    list(LENGTH _node_stack_hits _node_stack_count)
    if(NOT _node_stack_count EQUAL 1)
        message(FATAL_ERROR
            "node port: found ${_node_stack_count} 'StackReserveSize' entries in node.gyp "
            "(expected exactly 1); upstream reorganised this setting, update the exported "
            "stack-size requirement accordingly.")
    endif()
    string(REGEX MATCH "0x[0-9A-Fa-f]+" _node_stack_reserve "${_node_stack_hits}")
    unset(_node_gyp_text)
    unset(_node_stack_hits)
    unset(_node_stack_count)
    string(APPEND _cfg
        "target_link_options(unofficial::node::node INTERFACE \"/STACK:${_node_stack_reserve}\")\n")

    # Windows platform compatibility manifest and /INCREMENTAL:NO (the
    # incremental two-pass link appends a bare /MANIFEST that overrides embed
    # mode).
    string(APPEND _cfg
        "set(node_NODE_SOURCE_MANIFEST \"\${_node_prefix}/share/node/node.exe.extra.manifest\")\n"
        "if(DEFINED node_NODE_SOURCE_MANIFEST AND EXISTS \"\${node_NODE_SOURCE_MANIFEST}\")\n"
        "  target_link_options(unofficial::node::node INTERFACE\n"
        "    \"/MANIFEST:EMBED\"\n"
        "    \"/MANIFESTINPUT:\${node_NODE_SOURCE_MANIFEST}\"\n"
        "    \"/INCREMENTAL:NO\")\n"
        "endif()\n")
endif()

if("test-suite" IN_LIST FEATURES)
    string(APPEND _cfg
        "if(EXISTS \"\${CMAKE_CURRENT_LIST_DIR}/../node/test-suite/tools/test.py\")\n"
        "  set(node_TEST_SUITE_DIR \"\${CMAKE_CURRENT_LIST_DIR}/../node/test-suite\")\n"
        "endif()\n")
endif()

file(WRITE "${CURRENT_PACKAGES_DIR}/share/unofficial-node/unofficial-node-config.cmake" "${_cfg}")
file(WRITE "${CURRENT_PACKAGES_DIR}/share/unofficial-node/unofficial-node-config-version.cmake"
"set(PACKAGE_VERSION \"26.12.0\")\n"
"if(PACKAGE_VERSION VERSION_LESS PACKAGE_FIND_VERSION)\n"
"  set(PACKAGE_VERSION_COMPATIBLE FALSE)\n"
"else()\n"
"  set(PACKAGE_VERSION_COMPATIBLE TRUE)\n"
"  if(PACKAGE_FIND_VERSION STREQUAL PACKAGE_VERSION)\n"
"    set(PACKAGE_VERSION_EXACT TRUE)\n"
"  endif()\n"
"endif()\n")

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage"
    DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
