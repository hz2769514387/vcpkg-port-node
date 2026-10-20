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

# ---------------------------------------------------------------------------
# Library linkage: static and dynamic are both supported (ADR 0007).
#
# Static was the only kind for a long time, and `vcpkg_check_linkage(
# ONLY_STATIC_LIBRARY)` used to say so - without any evidence that a shared
# libnode cannot be built, which is what it takes for a restriction to belong
# in the README's *Known limits* rather than in an issue. Read from the
# Node.js v26.12.0 tree: `--shared` is a first-class configure.py option; on
# Windows the DLL is linked once and then relinked against a module-definition
# file derived from its own export table, so the export set is whatever the
# DLL already exported (node.gyp, tools/gen_node_def.cc) and
# common.gypi marks V8's embedding API __declspec(dllexport); on Unix the
# obvious way to hide symbols is commented out in node.gyp. Nothing blocks it.
#
# The two forms do differ for a consumer, and the differences are written down
# rather than smoothed over:
#   * a shared libnode already contains the externalized dependencies, so a
#     consumer must NOT link them a second time;
#   * the library has to be found at run time;
#   * the definitions this port hands a consumer (/STACK, the manifest) are
#     properties of the executable that hosts Node.js, so they still apply.
# ---------------------------------------------------------------------------
vcpkg_check_linkage()
if(VCPKG_LIBRARY_LINKAGE STREQUAL "dynamic")
    set(_node_shared_build TRUE)
    message(STATUS "node port: VCPKG_LIBRARY_LINKAGE=dynamic -> building a shared libnode")
else()
    set(_node_shared_build FALSE)
    message(STATUS "node port: VCPKG_LIBRARY_LINKAGE=static -> building a static libnode")
endif()

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
        "${CMAKE_CURRENT_LIST_DIR}/patches/0020-crates-debug-rust-target.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0021-test-py-print-exit-code.patch"
        "${CMAKE_CURRENT_LIST_DIR}/patches/0022-uv-shared-define-only-when-libuv-is-bundled.patch"
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
# runs, which is inside configure.py, so setting them here is enough. The build
# loop below re-states them per configuration, because the shared-linkage rpath
# it adds differs between the release and the debug tree.
#
# VCPKG_TARGET_IS_OSX rather than APPLE: in port script mode a bare APPLE is
# ambiguous about target versus host, and vcpkg says so on every configure.
# ---------------------------------------------------------------------------
if(VCPKG_TARGET_IS_OSX)
    set(_node_ldflags_base "-framework CoreFoundation -framework Security")
else()
    set(_node_ldflags_base "")
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
    # Filled while the options are built and reported once at the end, so one run
    # names every wrong library name instead of the first.
    set(_missing_report "")
    set(_present_txt "")
    if(VCPKG_TARGET_IS_WINDOWS)
        # This repository's zlib overlay installs the Chromium fork as `zs.lib`
        # when it is built statically and as `zlib.lib` when it is built as a
        # DLL (it renames the static output to keep it from colliding with the
        # registry port's file). configure.py needs the real file name, so the
        # name follows the linkage rather than being a constant - hard-coding
        # `zs` is what made a shared libnode fail with
        # `LINK : fatal error LNK1181: cannot open input file 'zs.lib'`.
        # The fork's own CMakeLists: shared is OUTPUT_NAME z, static is
        # z${zlib_static_suffix} (zs on Windows). gyp appends the debug `d`
        # itself, so what is handed over is always the release stem.
        if(_node_shared_build)
            set(_zlib_lib    "z")
        else()
            set(_zlib_lib    "zs")
        endif()
        set(_openssl_lib "libcrypto,libssl")
        # vcpkg's libuv names its Windows output after the linkage: the static
        # archive is target uv_a with OUTPUT_NAME "uv" and PREFIX "lib", which
        # is libuv.lib, while the dynamic build's import library is target uv
        # with OUTPUT_NAME "uv" and no prefix - plain uv.lib. Unix is uv in
        # both linkages. Hard-coding libuv for Windows is what made every
        # *-windows (dynamic) leg fail the up-front name check below with
        # "libuv ... not in .../lib".
        if(_node_shared_build)
            set(_libuv_lib   "uv")
        else()
            set(_libuv_lib   "libuv")
        endif()
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
        # bcrypt exists on Windows only - it is mbedtls's Windows entropy source
        # (BCryptGenRandom), and LIEF's own CMake links it under if(WIN32) for
        # the same reason. On Unix mbedtls reads /dev/urandom and needs nothing.
        set(_lief_libs "LIEF,${_spdlog_lib},${_fmt_lib},mbedx509,tfpsacrypto,bcrypt")
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
        set(_lief_libs "LIEF,${_spdlog_lib},${_fmt_lib},mbedx509,tfpsacrypto")
        set(_absl_prefix "libabsl_")
        set(_absl_suffix ".a")
        set(_hwy_lib     "hwy")
    endif()

    # abseil is split into ~90 archives; Node's own pkg-config list names only
    # part of them, so take every installed name. Two shapes that are not that one:
    #
    #   * Windows with a dynamic triplet. vcpkg's abseil port leaves
    #     ABSL_BUILD_MONOLITHIC_SHARED_LIBS at MSVC's default, which is ON, so the only
    #     library installed is abseil_dll.lib - there is no absl_mutex.lib and no absl_*.lib
    #     of any kind. The glob below therefore found nothing, the list went out empty, the
    #     precheck further down had no name to complain about, and the first host tool to
    #     link v8_libbase died with LNK2019 on absl::lts_*::Mutex. Measured on
    #     x64-windows-release.
    #   * POSIX. abseil there is static-only (vcpkg_check_linkage(ONLY_STATIC_LIBRARY) in its
    #     portfile), so the component archives are libabsl_*.a no matter what libnode's own
    #     linkage is.
    if(VCPKG_TARGET_IS_WINDOWS AND VCPKG_LIBRARY_LINKAGE STREQUAL "dynamic")
        set(_absl_libnames "abseil_dll")
    else()
        file(GLOB _absl_files RELATIVE "${_libdir}" "${_libdir}/${_absl_prefix}*${_absl_suffix}")
        set(_absl_libnames "")
        foreach(_f IN LISTS _absl_files)
            get_filename_component(_f "${_f}" NAME_WE)
            string(REGEX REPLACE "^lib" "" _f "${_f}")
            list(APPEND _absl_libnames "${_f}")
        endforeach()
        unset(_absl_files)
        unset(_f)
    endif()
    # An empty list is otherwise silent: the precheck only complains about names it was
    # given, and a build that never linked abseil fails much later and somewhere else.
    # abseil is not optional - --shared-abseil is always passed - so an empty list is a
    # defect in this file, not a consumer problem.
    if(NOT _absl_libnames)
        file(GLOB _present "${_libdir}/*")
        message(FATAL_ERROR
            "node port: no abseil libraries found under '${_libdir}' (looked for "
            "${_absl_prefix}*${_absl_suffix}). abseil is externalized unconditionally, so "
            "the build cannot proceed without it. What that directory holds:\n  ${_present}")
    endif()
    list(JOIN _absl_libnames "," _absl_libnames)

    # hdr-histogram's own CMake names the static library hdr_histogram_static and
    # the shared one hdr_histogram - the _static suffix is a linkage convention,
    # not part of the name. Which one exists depends on two separate decisions:
    #
    #   * Windows: the overlay forces a static library on every triplet (the
    #     upstream build's DLL is not used here), so it is always the suffixed
    #     name - and a dynamic triplet holding a shared libnode is exactly the
    #     case that made the precheck want hdr_histogram.lib;
    #   * everywhere else the overlay leaves the choice to the triplet, so a
    #     dynamic triplet installs libhdr_histogram.so with the version suffix
    #     and a static one installs libhdr_histogram_static.a.
    #
    # Keyed off the triplet, not off libnode's own linkage: the package's
    # linkage is the triplet's business.
    if(VCPKG_TARGET_IS_WINDOWS)
        set(_hdrhist_lib "hdr_histogram_static")
    elseif(VCPKG_LIBRARY_LINKAGE STREQUAL "dynamic")
        set(_hdrhist_lib "hdr_histogram")
    else()
        set(_hdrhist_lib "hdr_histogram_static")
    endif()
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
        # The exact chain is platform-dependent (bcrypt is Windows-only), see
        # _lief_libs above; LIEF, mbedtls and bcrypt keep their names in the
        # debug tree while spdlog/fmt carry the d postfix.
        "lief|${_lief_libs}")
        string(REPLACE "|" ";" _pair "${_spec}")
        list(GET _pair 0 _opt)
        list(GET _pair 1 _libnames)
        # A name that is wrong here surfaces as LNK1181 "cannot open input file"
        # several thousand lines later, once every dependency has been built and
        # the first host tool is linked - an hour into a leg, and the message
        # names neither the dependency nor what was expected. Checking the names
        # against the directory they came from costs nothing and fails in
        # seconds with the missing names and what is actually there.
        # _libnames is comma-separated because that is the separator
        # --shared-<dep>-libname takes; CMake needs semicolons to iterate it.
        #
        # Not every name on the link line is a vcpkg library: LIEF's list ends
        # with bcrypt, which is mbedtls's Windows entropy source and lives in
        # the SDK rather than in the install prefix. The first run with this
        # check proved it by demanding bcrypt from a directory that has never
        # held it.
        set(_node_sdk_libs
            bcrypt ntdll winmm ws2_32 crypt32 advapi32 user32 kernel32
            dbghelp iphlpapi ole32 shell32 secur32 cryptui)
        set(_missing "")
        string(REPLACE "," ";" _libnames_list "${_libnames}")
        foreach(_n IN LISTS _libnames_list)
            if(_n IN_LIST _node_sdk_libs)
                continue()
            endif()
            if(VCPKG_TARGET_IS_WINDOWS)
                set(_candidates "${_libdir}/${_n}.lib")
                # gyp appends the debug `d` itself, so the debug tree holds
                # zsd.lib for a name of zs. Accepting only the bare stem here
                # would reject the Debug build that already works.
                if(_is_debug)
                    list(APPEND _candidates "${_libdir}/${_n}d.lib")
                endif()
            else()
                set(_candidates "${_libdir}/lib${_n}.a"
                                "${_libdir}/lib${_n}.so"
                                "${_libdir}/lib${_n}.dylib")
            endif()
            file(GLOB _hit ${_candidates})
            if(NOT _hit)
                # Collected rather than reported here: this check has cost one CI
                # round per wrong name (zlib, then libuv, then hdr-histogram),
                # because each round reported only the first option it tripped over
                # and the next round then failed on the next one. One pass over every
                # option, one report.
                list(APPEND _missing "${_n}")
            endif()
            unset(_hit)
            unset(_candidates)
        endforeach()
        unset(_n)
        if(_missing)
            foreach(_m IN LISTS _missing)
                string(APPEND _missing_report "\n  --shared-${_opt}-libname ${_m}")
            endforeach()
            unset(_m)
            if(NOT _present_txt)
                file(GLOB _present "${_libdir}/*")
                list(TRANSFORM _present REPLACE "^.*/" "")
                list(LENGTH _present _present_count)
                if(_present_count GREATER 60)
                    list(SUBLIST _present 0 60 _present)
                    list(APPEND _present "...")
                endif()
                string(REPLACE ";" "\n  " _present_txt "${_present}")
                unset(_present)
                unset(_present_count)
            endif()
        endif()
        unset(_missing)
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
    if(_missing_report)
        message(FATAL_ERROR
            "node port: these --shared-*-libname entries name libraries that are not in "
            "${_libdir}:${_missing_report}\n\n"
            "A wrong name here used to reach the linker as LNK1181 an hour later. "
            "What that directory actually holds:\n  ${_present_txt}")
    endif()
    unset(_missing_report)
    unset(_present_txt)
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

    # -----------------------------------------------------------------------
    # Where the port's own host tools, and later the installed artifacts, find
    # the shared libraries they were linked against.
    #
    # A dynamic triplet makes every dependency a shared object, and two
    # consumers of them have nothing to help them:
    #
    # 1. The host tools (torque, mksnapshot, node_mksnapshot,
    #    bytecode_builtins_list_generator, ...) *run* during this build - they
    #    generate the sources everything else compiles - and they are linked
    #    against the dependencies. gyp puts them in the output root next to
    #    nothing that helps: the first one to run dies with "error while
    #    loading shared libraries: libada.so.4" (Linux) or "dyld: Library not
    #    loaded: @rpath/libz.1.3.2.1.dylib" (macOS), an hour into the leg and
    #    naming neither the tool nor the cause.
    # 2. The installed artifacts. The exported config links libnode itself and
    #    nothing else, so libnode.so has to find its dependencies on its own -
    #    they are installed next to it in <prefix>/lib - and the installed node
    #    executable has to find libnode, which sits in <prefix>/lib while the
    #    executable lives in <prefix>/tools/node.
    #
    # Both are answered with a *relative* rpath, never an absolute one: the
    # GitHub runner path shape (/home/runner/work/<repo>/<repo>/vcpkg/installed/
    # <triplet>/lib) is the same on every machine, so an absolute rpath would
    # not be inert on a consumer's machine - it would find whatever some other
    # build left at that path. A relative rpath names nothing and still works.
    #
    # The ninja generator writes LDFLAGS verbatim into build.ninja, and the
    # resulting command is run through sh. `$` is ninja's escape character and
    # sh would expand `$ORIGIN` to nothing, so a literal $ORIGIN only reaches
    # the linker if it is spelled `\$$ORIGIN` here (ninja: $$ -> $; sh: \$ ->
    # $). node.gyp spells its own rpath the same way. @loader_path has no `$`
    # and needs no such care.
    #
    # LDFLAGS_host is deliberately not used for the host tools: gyp's ninja
    # generator only honours a separate host toolset when cross-compiling
    # (gyp.common.CrossCompileRequested), and this port passes
    # --no-cross-compiling on every platform, so every link - host tools
    # included - is a target-toolset link that reads LDFLAGS.
    #
    # On Windows there is no rpath: the loader searches the executable's own
    # directory and then PATH, so the install tree's bin/ goes onto PATH for
    # the build. The host tools are never installed, and the consumer side
    # handles its own executables (node_test_runtime_libs in the test project).
    # -----------------------------------------------------------------------
    if(VCPKG_TARGET_IS_LINUX OR VCPKG_TARGET_IS_OSX)
        if(_node_shared_build)
            if(VCPKG_TARGET_IS_OSX)
                set(_node_ldflags_target
                    "${_node_ldflags_base} -Wl,-rpath,@loader_path -Wl,-rpath,@loader_path/../lib")
            else()
                set(_node_ldflags_target
                    "${_node_ldflags_base} -Wl,-rpath,\\$$ORIGIN -Wl,-rpath,\\$$ORIGIN/../lib")
            endif()
        else()
            set(_node_ldflags_target "${_node_ldflags_base}")
        endif()
        set(ENV{LDFLAGS} "${_node_ldflags_target}")
        set(ENV{LDFLAGS_host} "${_node_ldflags_base}")
    elseif(VCPKG_TARGET_IS_WINDOWS AND _node_shared_build)
        get_filename_component(_node_bin_dir "${_node_lib_dir}/../bin" ABSOLUTE)
        set(ENV{PATH} "${_node_bin_dir};$ENV{PATH}")
    endif()

    # --shared makes node.gyp build libnode as a shared_library and link the
    # node executable against it.
    if(_node_shared_build)
        set(_node_shared_build_arg "--shared")
    else()
        set(_node_shared_build_arg "")
    endif()

    vcpkg_execute_required_process(
        COMMAND "${PYTHON3}" configure.py
            --ninja
            ${_node_cfg_arg}
            ${_node_clang_cl_arg}
            ${_node_shared_build_arg}
            ${_node_dest_cpu_args}
            --with-intl=system-icu
            ${_node_shared_args}
            "-DVCPKG_SIMDUTF_INCLUDE=${CURRENT_INSTALLED_DIR}/include"
        WORKING_DIRECTORY "${SOURCE_PATH}"
        LOGNAME "configure-${_node_cfg}"
    )

    # -----------------------------------------------------------------------
    # Shared linkage, Unix: put the dependencies where the host tools can load
    # them from.
    #
    # gyp puts every executable it links in the output root (out/<config>/)
    # and, on Linux, shared libraries one level down in lib/. The host tools
    # run from the output root and carry the relative rpath added above, so a
    # symlink per dependency name in the output root is all the loader needs
    # to find them: $ORIGIN / @loader_path already points there. lib/ gets
    # them too, because that is where libnode.so lives on Linux and where its
    # own $ORIGIN resolves - nothing loads it during this build, but a future
    # build step that does would otherwise fail the same silent way.
    #
    # Symlinks rather than copies: the libraries are hundreds of megabytes and
    # the build tree is transient. COPY_ON_ERROR covers a filesystem without
    # symlink support by falling back to a real copy.
    # -----------------------------------------------------------------------
    if(_node_shared_build AND (VCPKG_TARGET_IS_LINUX OR VCPKG_TARGET_IS_OSX))
        if(VCPKG_TARGET_IS_OSX)
            file(GLOB _node_shared_deps "${_node_lib_dir}/*.dylib")
        else()
            file(GLOB _node_shared_deps "${_node_lib_dir}/lib*.so*")
        endif()
        foreach(_node_out_subdir IN ITEMS "" "lib")
            set(_node_out_dir "${SOURCE_PATH}/out/${_node_cfg}")
            if(NOT _node_out_subdir STREQUAL "")
                set(_node_out_dir "${_node_out_dir}/${_node_out_subdir}")
                file(MAKE_DIRECTORY "${_node_out_dir}")
            endif()
            foreach(_node_dep IN LISTS _node_shared_deps)
                get_filename_component(_node_dep_name "${_node_dep}" NAME)
                file(CREATE_LINK "${_node_dep}"
                     "${_node_out_dir}/${_node_dep_name}"
                     SYMBOLIC COPY_ON_ERROR)
            endforeach()
            unset(_node_dep)
            unset(_node_dep_name)
            unset(_node_out_dir)
        endforeach()
        unset(_node_out_subdir)
        unset(_node_shared_deps)
    endif()

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
    # Free this configuration's object files.
    #
    # Nothing after the link needs them: the archives the install step globs
    # are separate files in the same tree, the vendored-build check below
    # reads build.ninja and not the objects, and no step relinks. A
    # dual-configuration triplet builds both trees in one source directory,
    # so the second configuration starts with the first one's objects still
    # on disk - and a macOS x64 Debug leg ran out of space exactly there,
    # 1253 edges into the second build, with a message ("can't write to
    # output file (No space left on device)") that names neither the
    # configuration nor the cause. Deleting the objects costs nothing and is
    # what makes two trees fit on a runner that fits one.
    # -----------------------------------------------------------------------
    file(GLOB_RECURSE _node_config_objects
         "${SOURCE_PATH}/out/${_node_cfg}/obj/*.o"
         "${SOURCE_PATH}/out/${_node_cfg}/obj/*.obj")
    if(_node_config_objects)
        file(REMOVE ${_node_config_objects})
    endif()
    unset(_node_config_objects)

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

# A shared libnode's file name carries the NODE_MODULE_VERSION on Unix. node.gyp
# sets `product_extension` to <(shlib_suffix) for a shared library off Windows,
# and configure.py fills that in with the module version: `libnode.147.dylib` on
# macOS, `libnode.so.147` on Linux. "libnode.dylib" and "libnode.so" are names
# the build never produces, which is what the first shared leg to reach the
# install step found out. The name is read out of the built tree once, from the
# Release configuration, and reused by the install step, the tools/ copy and the
# exported config, so nothing here has to track the module version itself.
if(_node_shared_build AND NOT VCPKG_TARGET_IS_WINDOWS)
    if(VCPKG_TARGET_IS_OSX)
        file(GLOB _node_shlib_candidates "${SOURCE_PATH}/out/Release/libnode*.dylib")
    else()
        file(GLOB _node_shlib_candidates "${SOURCE_PATH}/out/Release/lib/libnode.so*")
    endif()
    if(NOT _node_shlib_candidates)
        message(FATAL_ERROR
            "node port: the Release build produced no shared libnode under "
            "${SOURCE_PATH}/out/Release")
    endif()
    list(GET _node_shlib_candidates 0 _node_shlib_path)
    get_filename_component(_node_shlib_name "${_node_shlib_path}" NAME)
    unset(_node_shlib_candidates)
    unset(_node_shlib_path)

    # ---------------------------------------------------------------------------------
    # A shared libnode has to carry abseil, and this is the only place that is checkable.
    #
    # Off Windows, vcpkg's abseil is static-only, so there is no libabsl_*.so for the loader
    # to find: the archives must end up inside libnode. When they do not, the link still
    # *succeeds* - a shared library is allowed to leave symbols undefined - and the failure
    # appears at the consumer's link, two and a half hours into a leg, reading
    # "libnode.so.147: undefined reference to absl::lts_*::..." and pointing at the consumer
    # rather than at this port. That is exactly what the x64-linux-dynamic leg reported, and
    # nothing in the log above it named abseil once.
    #
    # Any undefined abseil symbol here is a defect by construction, so it is checked next to
    # the library. The refusal also reports whether the -labsl_* flags reached the gyp link
    # line at all, which is the first question the failure raises and the one the log cannot
    # answer: gyp's rsp file is only visible in build.ninja.
    # ---------------------------------------------------------------------------------
    find_program(_node_nm NAMES llvm-nm nm)
    if(NOT _node_nm)
        message(WARNING "node port: no nm found; cannot verify that abseil is inside libnode")
    else()
        foreach(_node_cfg IN LISTS _node_configs)
            if(_node_cfg STREQUAL "Debug")
                set(_node_cfg_out_dir "${SOURCE_PATH}/out/Debug")
            else()
                set(_node_cfg_out_dir "${SOURCE_PATH}/out/Release")
            endif()
            if(VCPKG_TARGET_IS_OSX)
                set(_node_cfg_shlib "${_node_cfg_out_dir}/${_node_shlib_name}")
                # Apple's nm has no -D; -u already means "undefined only", and a dylib's
                # undefined symbols are the external references either way.
                set(_node_nm_args -u)
            else()
                set(_node_cfg_shlib "${_node_cfg_out_dir}/lib/${_node_shlib_name}")
                # -D reads the dynamic symbol table, which survives stripping; a plain nm on
                # a stripped .so reports nothing at all and the check would pass by accident.
                set(_node_nm_args -D -u)
            endif()
            execute_process(
                COMMAND "${_node_nm}" ${_node_nm_args} "${_node_cfg_shlib}"
                OUTPUT_VARIABLE _node_undef
                ERROR_VARIABLE _node_undef_err
                RESULT_VARIABLE _node_undef_rc)
            if(NOT _node_undef_rc EQUAL 0)
                message(FATAL_ERROR
                    "node port: '${_node_nm} ${_node_nm_args}' failed on ${_node_cfg_shlib} "
                    "(${_node_undef_rc}), so the abseil check could not run: ${_node_undef_err}")
            endif()
            string(REGEX MATCHALL "[^\n]*(_ZN4absl|AbslInternal)[^\n]*" _node_absl_undef "${_node_undef}")
            if(_node_absl_undef)
                list(LENGTH _node_absl_undef _node_absl_undef_count)
                list(SUBLIST _node_absl_undef 0 5 _node_absl_undef_head)
                string(REPLACE ";" "\n  " _node_absl_undef_head "${_node_absl_undef_head}")
                # Two questions, asked separately because they have different answers.
                # 1) Did configure.py receive the names? config.gypi is what it wrote from
                #    --shared-abseil-libname, so this is the honest record of the handover.
                set(_node_absl_in_gypi "file-missing")
                if(EXISTS "${_node_cfg_out_dir}/config.gypi")
                    file(READ "${_node_cfg_out_dir}/config.gypi" _node_gypi_txt)
                    if(_node_gypi_txt MATCHES "-labsl_")
                        set(_node_absl_in_gypi "yes")
                    else()
                        set(_node_absl_in_gypi "no")
                    endif()
                    unset(_node_gypi_txt)
                endif()
                # 2) Did gyp put them on any link line, and in which file? Every ninja file,
                #    not just build.ninja: a target's edges can live in its own obj/*.ninja,
                #    and looking in one file would report a confident "no" for a link line
                #    that is simply somewhere else.
                set(_node_absl_in_ninja "no")
                file(GLOB_RECURSE _node_ninja_files "${_node_cfg_out_dir}/*.ninja")
                foreach(_nf IN LISTS _node_ninja_files)
                    file(READ "${_nf}" _node_ninja_txt)
                    if(_node_ninja_txt MATCHES "-labsl_")
                        file(RELATIVE_PATH _node_ninja_hit "${_node_cfg_out_dir}" "${_nf}")
                        set(_node_absl_in_ninja "yes, in ${_node_ninja_hit}")
                        break()
                    endif()
                endforeach()
                unset(_node_ninja_files)
                unset(_node_ninja_txt)
                message(FATAL_ERROR
                    "node port: ${_node_cfg} libnode has ${_node_absl_undef_count} undefined "
                    "abseil symbols, so nothing provides them at run time - abseil is "
                    "static-only off Windows and has to be inside libnode.\n"
                    "First few:\n  ${_node_absl_undef_head}\n\n"
                    "abseil names in config.gypi (so configure.py did get them): "
                    "${_node_absl_in_gypi}\n"
                    "-labsl_* anywhere in ${_node_cfg_out_dir}: ${_node_absl_in_ninja}\n\n"
                    "If config.gypi has them and no ninja file does, gyp dropped them; if "
                    "neither has them, --shared-abseil-libname arrived empty; if a ninja "
                    "file has them, they were on the link line and the archives were not "
                    "pulled in (look at the order relative to the objects, and at the "
                    "solink rule's -Wl,--whole-archive, which wraps only the inputs).")
            endif()
            unset(_node_absl_undef)
            unset(_node_absl_undef_count)
            unset(_node_absl_undef_head)
            unset(_node_undef)
            unset(_node_undef_err)
            unset(_node_cfg_shlib)
            unset(_node_nm_args)
        endforeach()
        unset(_node_cfg_out_dir)
        unset(_node_absl_in_gypi)
        unset(_node_absl_in_ninja)
        unset(_node_ninja_hit)
    endif()
    unset(_node_nm)
endif()

foreach(_node_cfg IN LISTS _node_configs)
    if(_node_cfg STREQUAL "Debug")
        set(_node_out_dir "${SOURCE_PATH}/out/Debug")
        set(_node_pkg_lib_dir "${CURRENT_PACKAGES_DIR}/debug/lib")
        set(_node_pkg_bin_dir "${CURRENT_PACKAGES_DIR}/debug/bin")
    else()
        set(_node_out_dir "${SOURCE_PATH}/out/Release")
        set(_node_pkg_lib_dir "${CURRENT_PACKAGES_DIR}/lib")
        set(_node_pkg_bin_dir "${CURRENT_PACKAGES_DIR}/bin")
    endif()

    if(_node_shared_build)
        # Where gyp's ninja generator puts a shared_library, read out of
        # ComputeOutput (tools/gyp/pylib/gyp/generator/ninja.py): the output
        # root on Windows and macOS, lib/ on Linux. gyp names the Windows
        # import library "<dll>.lib", which is not a name anyone would guess.
        if(VCPKG_TARGET_IS_WINDOWS)
            set(_node_shlib "${_node_out_dir}/libnode.dll")
            set(_node_implib "${_node_shlib}.lib")
            file(INSTALL "${_node_shlib}" DESTINATION "${_node_pkg_bin_dir}")
            file(INSTALL "${_node_implib}" DESTINATION "${_node_pkg_lib_dir}")
        elseif(VCPKG_TARGET_IS_OSX)
            file(INSTALL "${_node_out_dir}/${_node_shlib_name}" DESTINATION "${_node_pkg_lib_dir}")
        else()
            file(INSTALL "${_node_out_dir}/lib/${_node_shlib_name}" DESTINATION "${_node_pkg_lib_dir}")
        endif()
        # Nothing else is a deliverable: the component archives are inputs the
        # shared library already absorbed, and linking them again from a
        # consumer would put a second copy of every symbol into the process.
        unset(_node_shlib)
        unset(_node_implib)
        unset(_node_out_dir)
        unset(_node_pkg_lib_dir)
        unset(_node_pkg_bin_dir)
        continue()
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
unset(_node_pkg_bin_dir)

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
    # A shared build needs its library beside the executable. node.gyp gives
    # the Linux binary `-rpath $ORIGIN/../lib` and the macOS one
    # `@rpath/libnode.dylib` with `@loader_path` and `@loader_path/../lib`,
    # so both spellings are covered: next to the binary, and one level up
    # under lib/. Windows looks next to the binary and nowhere else.
    if(_node_shared_build)
        if(VCPKG_TARGET_IS_WINDOWS)
            set(_node_tool_shlib "${SOURCE_PATH}/out/Release/libnode.dll")
        elseif(VCPKG_TARGET_IS_OSX)
            set(_node_tool_shlib "${SOURCE_PATH}/out/Release/${_node_shlib_name}")
        else()
            set(_node_tool_shlib "${SOURCE_PATH}/out/Release/lib/${_node_shlib_name}")
        endif()
        file(INSTALL "${_node_tool_shlib}" DESTINATION "${_node_tools}")
        file(INSTALL "${_node_tool_shlib}" DESTINATION "${CURRENT_PACKAGES_DIR}/tools/lib")
        unset(_node_tool_shlib)
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
             "hdr_histogram CONFIG" "hwy CONFIG"
             # LIEF's own config pulls its dependency chain in turn
             # (MbedTLS, spdlog, nlohmann_json, frozen, tl-expected, utf8cpp).
             "LIEF")
    string(APPEND _cfg "find_dependency(${_dep})\n")
endforeach()
unset(_dep)

# The module and napi ABI versions a consumer compares its prebuilt addons against.
# NODE_MODULE_VERSION can be overridden by an embedder at compile time
# (NODE_EMBEDDER_MODULE_VERSION in the consuming build), so what is exported here is the
# default this library was built with.
file(STRINGS "${SOURCE_PATH}/src/node_version.h" _node_module_version_line
     REGEX "^#define NODE_MODULE_VERSION [0-9]+$")
string(REGEX MATCH "[0-9]+" _node_module_version "${_node_module_version_line}")
file(STRINGS "${SOURCE_PATH}/src/js_native_api_types.h" _node_napi_version_line
     REGEX "^#define NAPI_VERSION [0-9]+$")
string(REGEX MATCH "[0-9]+" _node_napi_version "${_node_napi_version_line}")
if(NOT _node_module_version OR NOT _node_napi_version)
    message(FATAL_ERROR
        "could not read NODE_MODULE_VERSION / NAPI_VERSION from the Node.js source tree "
        "(module='${_node_module_version}', napi='${_node_napi_version}'); update the "
        "regexes in ports/node/portfile.cmake to match the new headers.")
endif()

string(APPEND _cfg
    "get_filename_component(_node_prefix \"\${CMAKE_CURRENT_LIST_DIR}/../..\" ABSOLUTE)\n"
    "set(_node_lib \"\${_node_prefix}/lib\")\n"
    "set(node_INSTALLED_LIBRARIES \"${_node_installed_libs}\")\n"
    "set(node_MODULE_VERSION \"${_node_module_version}\")\n"
    "set(node_NAPI_VERSION \"${_node_napi_version}\")\n")

# release-only install + a Debug consumer: fail at configure time rather than
# link time (LNK2038 RuntimeLibrary).
if(VCPKG_TARGET_IS_WINDOWS)
    # A release-only install cannot serve a Debug consumer: MSVC's Debug
    # configuration is the debug CRT (/MTd or /MDd) plus _ITERATOR_DEBUG_LEVEL=2,
    # and a Release static library carries the release values, so the link ends
    # in LNK2038. Measured 2026-10-18 (ADR 0007).
    #
    # Two ways a consumer can ask for Debug, and they are not the same:
    #   * a single-config generator states it in CMAKE_BUILD_TYPE, and that is a
    #     fact about this build - refuse it;
    #   * a multi-config generator (Visual Studio) always lists Debug among its
    #     CMAKE_CONFIGURATION_TYPES, whether or not it is ever built, and
    #     CMAKE_BUILD_TYPE is empty there. A test against CMAKE_BUILD_TYPE
    #     therefore never fires on the generator most Windows consumers use -
    #     which is exactly what the previous version of this guard did. Warn
    #     instead of failing: refusing to configure because a configuration
    #     *exists* would break everyone who only builds Release.
    string(APPEND _cfg
        "if(NOT EXISTS \"\${_node_prefix}/debug/lib\")\n"
        "  if(CMAKE_BUILD_TYPE STREQUAL \"Debug\")\n"
        "    message(FATAL_ERROR\n"
        "      \"This node install is release-only (VCPKG_BUILD_TYPE=release); there is no debug library.\\n\"\n"
        "      \"On Windows a Debug consumer (/MTd or /MDd) cannot link a Release (/MT or /MD) node.\\n\"\n"
        "      \"Use a dual triplet (e.g. x64-windows-static) or build the consumer as Release\\n\"\n"
        "      \"or RelWithDebInfo - RelWithDebInfo is the release ABI with debug information,\\n\"\n"
        "      \"which is what you want when the need is to debug your own code.\")\n"
        "  elseif(CMAKE_CONFIGURATION_TYPES)\n"
        "    message(WARNING\n"
        "      \"This node install is release-only (VCPKG_BUILD_TYPE=release); there is no debug library,\\n\"\n"
        "      \"so building this project's Debug configuration will fail with LNK2038 RuntimeLibrary\\n\"\n"
        "      \"mismatches. Release and RelWithDebInfo are fine. Use a dual triplet (e.g.\\n\"\n"
        "      \"x64-windows-static) if you need Debug.\")\n"
        "  endif()\n"
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

if(_node_shared_build)
    if(VCPKG_TARGET_IS_WINDOWS)
        set(_node_shlib_file "libnode.dll")
        # gyp names the import library "<dll>.lib"; see the install step above.
        set(_node_implib_file "libnode.dll.lib")
    else()
        # libnode.147.dylib / libnode.so.147 - globbed from the build tree above,
        # because the module version is part of the name.
        set(_node_shlib_file "${_node_shlib_name}")
    endif()
endif()

# Everything gyp produces for a Node.js build. abseil/highway/simdutf/zlib come
# from vcpkg; v8_zlib remains (patched down to compression_utils_portable.cc, so
# it defines no zlib core symbols). LIEF and libffi are vcpkg packages now and
# are wired below as their own imported targets (LIEF::LIEF, unofficial::node::ffi).
#
# A shared build has none of this to import: the shared library already contains
# every one of these archives, and a consumer linking them again would put a
# second copy of each symbol into the process.
if(NOT _node_shared_build)
set(_node_all_archives
    libnode node_base
    v8_base_without_compiler v8_compiler v8_init v8_initializers
    v8_snapshot v8_libbase v8_libplatform v8_zlib
    ncrypto ncrypto_engine nbytes merve uvwasi crdtp node_crates)
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
endif()  # NOT _node_shared_build (archives)

if(NOT _node_shared_build)
# abseil ships one archive per component and its vcpkg config exposes them as
# individual absl::<component> targets with no aggregate, so import them by file
# name here. That stays correct across abseil versions without tracking target
# names, and the archives always sit in the same prefix as this port. An empty
# glob is a configure error rather than a link error far away.
string(APPEND _cfg
    "file(GLOB _node_absl_libs \"\${_node_lib}/absl_*.lib\" \"\${_node_lib}/libabsl_*.a\")\n"
    "if(NOT _node_absl_libs)\n"
    "  message(FATAL_ERROR\n"
    "    \"no abseil archives found under '\${_node_lib}' (looked for absl_*.lib and libabsl_*.a).\\n\"\n"
    "    \"This config imports abseil's component archives by filename because vcpkg's abseil\\n\"\n"
    "    \"exposes no aggregate target; if abseil renamed or re-split its libraries, update\\n\"\n"
    "    \"the glob in ports/node/portfile.cmake.\")\n"
    "endif()\n")
if("Debug" IN_LIST _node_configs)
    string(APPEND _cfg
        "file(GLOB _node_absl_debug_libs \"\${_node_prefix}/debug/lib/absl_*.lib\" \"\${_node_prefix}/debug/lib/libabsl_*.a\")\n")
endif()
string(APPEND _cfg
    "foreach(_l IN LISTS _node_absl_libs)\n"
    "  get_filename_component(_n \"\${_l}\" NAME_WE)\n"
    "  string(REGEX REPLACE \"^lib\" \"\" _n \"\${_n}\")\n"
    "  if(NOT TARGET unofficial::node::\${_n})\n"
    "    add_library(unofficial::node::\${_n} STATIC IMPORTED)\n"
    "    set_target_properties(unofficial::node::\${_n} PROPERTIES IMPORTED_LOCATION \"\${_l}\")\n")
if("Debug" IN_LIST _node_configs)
    # Derive the debug location from the debug directory itself instead of guessing a
    # filename: the archives were enumerated above, so match on the same stem.
    string(APPEND _cfg
        "    foreach(_d IN LISTS _node_absl_debug_libs)\n"
        "      get_filename_component(_dn \"\${_d}\" NAME_WE)\n"
        "      string(REGEX REPLACE \"^lib\" \"\" _dn \"\${_dn}\")\n"
        "      if(_dn STREQUAL _n)\n"
        "        set_target_properties(unofficial::node::\${_n} PROPERTIES IMPORTED_LOCATION_DEBUG \"\${_d}\")\n"
        "      endif()\n"
        "    endforeach()\n")
endif()
string(APPEND _cfg
    "  endif()\n"
    "  list(APPEND _node_absl_links unofficial::node::\${_n})\n"
    "endforeach()\n"
    "unset(_node_absl_libs)\n"
    "unset(_node_absl_debug_libs)\n")
endif()  # NOT _node_shared_build (abseil)

string(APPEND _cfg
    "add_library(unofficial::node::node INTERFACE IMPORTED)\n"
    "set_target_properties(unofficial::node::node PROPERTIES"
    " INTERFACE_INCLUDE_DIRECTORIES"
    " \"\${_node_prefix}/include;\${_node_prefix}/include/node;\${_node_prefix}/include/node-v8\")\n"
    "set_property(TARGET unofficial::node::node PROPERTY INTERFACE_COMPILE_FEATURES cxx_std_20)\n")

# V8 compares four of its own build-time switches against the embedder's at
# InitializePlatform startup (deps/v8/src/api/api.cc, "Embedder-vs-V8 build
# configuration mismatch") and refuses to run if they disagree. Three of them -
# pointer compression, the sandbox, the target OS - are the same for both
# configurations of this port. The fourth is not: configure.py sets
# v8_enable_v8_checks to 1 for Debug and 0 for Release, so a consumer whose code
# is compiled Debug has to define V8_ENABLE_CHECKS to match the Debug library,
# and must not define it against the Release one. The generator expression says
# exactly that, which is what keeps a multi-config consumer building both
# configurations out of one project correct.
#
# Measured as the failure of embedding.thread_loop and embedding.host_loop in
# the first Debug leg: "On embedder side V8_ENABLE_CHECKS is DISABLED while on
# V8 side it's ENABLED", with 28 of 30 cases - the official suite included -
# passing around it.
if("Debug" IN_LIST _node_configs)
    string(APPEND _cfg
        "set_property(TARGET unofficial::node::node APPEND PROPERTY\n"
        "  INTERFACE_COMPILE_DEFINITIONS \"\$<\$<CONFIG:Debug>:V8_ENABLE_CHECKS>\")\n")
endif()
if(VCPKG_TARGET_IS_WINDOWS)
    string(APPEND _cfg
        "if(MSVC AND NOT CMAKE_CXX_COMPILER_ID MATCHES \"Clang\")\n"
        "  target_compile_options(unofficial::node::node INTERFACE \"/Zc:__cplusplus\")\n"
        "endif()\n")
endif()

if(_node_shared_build)
    # A shared libnode: one imported SHARED target, and nothing else on the
    # consumer's link line. Every externalized dependency is already inside the
    # library, and linking it again would put a second copy of each symbol into
    # the process; the system libraries the library needs are the library's own
    # business, not the consumer's.
    string(APPEND _cfg
        "set(node_LIBRARY_KIND \"shared\")\n"
        "if(NOT TARGET unofficial::node::libnode)\n"
        "  add_library(unofficial::node::libnode SHARED IMPORTED)\n")
    if(VCPKG_TARGET_IS_WINDOWS)
        string(APPEND _cfg
            "  set_target_properties(unofficial::node::libnode PROPERTIES\n"
            "    IMPORTED_IMPLIB \"\${_node_lib}/${_node_implib_file}\"\n"
            "    IMPORTED_LOCATION \"\${_node_prefix}/bin/${_node_shlib_file}\")\n"
            "  set(node_SHARED_LIBRARY \"\${_node_prefix}/bin/${_node_shlib_file}\")\n")
    else()
        string(APPEND _cfg
            "  set_target_properties(unofficial::node::libnode PROPERTIES\n"
            "    IMPORTED_LOCATION \"\${_node_lib}/${_node_shlib_file}\")\n"
            "  set(node_SHARED_LIBRARY \"\${_node_lib}/${_node_shlib_file}\")\n")
    endif()
    if("Debug" IN_LIST _node_configs)
        if(VCPKG_TARGET_IS_WINDOWS)
            string(APPEND _cfg
                "  set_target_properties(unofficial::node::libnode PROPERTIES\n"
                "    IMPORTED_IMPLIB_DEBUG \"\${_node_prefix}/debug/lib/${_node_implib_file}\"\n"
                "    IMPORTED_LOCATION_DEBUG \"\${_node_prefix}/debug/bin/${_node_shlib_file}\")\n")
        else()
            string(APPEND _cfg
                "  set_target_properties(unofficial::node::libnode PROPERTIES\n"
                "    IMPORTED_LOCATION_DEBUG \"\${_node_prefix}/debug/lib/${_node_shlib_file}\")\n")
        endif()
    endif()
    string(APPEND _cfg
        "endif()\n"
        "target_link_libraries(unofficial::node::node INTERFACE unofficial::node::libnode)\n")
else()
    string(APPEND _cfg "set(node_LIBRARY_KIND \"static\")\n")
endif()

if(NOT _node_shared_build)
# nghttp2 ships no CMake config; build an imported target for it. find_library can fall
# back to a system copy, which would be built with a different CRT - refuse to.
string(APPEND _cfg
    "find_library(_nghttp2_lib nghttp2 HINTS \${_node_lib} REQUIRED)\n"
    "string(FIND \"\${_nghttp2_lib}\" \"\${_node_prefix}\" _nghttp2_pos)\n"
    "if(NOT _nghttp2_pos EQUAL 0)\n"
    "  message(FATAL_ERROR\n"
    "    \"nghttp2 resolved to '\${_nghttp2_lib}', which is outside this install prefix\\n\"\n"
    "    \"('\${_node_prefix}'). A system copy would be built with a different CRT.\")\n"
    "endif()\n"
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

# libffi ships no CMake config either (autotools), so import its archive the
# same way. vcpkg names it ffi.lib / libffi.a on Windows / Unix. The prefix check
# keeps find_library from silently picking up a system libffi.
string(APPEND _cfg
    "find_library(_node_ffi_lib ffi HINTS \${_node_lib} REQUIRED)\n"
    "string(FIND \"\${_node_ffi_lib}\" \"\${_node_prefix}\" _node_ffi_pos)\n"
    "if(NOT _node_ffi_pos EQUAL 0)\n"
    "  message(FATAL_ERROR\n"
    "    \"libffi resolved to '\${_node_ffi_lib}', which is outside this install prefix\\n\"\n"
    "    \"('\${_node_prefix}'). A system copy would be built with a different CRT.\")\n"
    "endif()\n"
    "if(NOT TARGET unofficial::node::ffi)\n"
    "  add_library(unofficial::node::ffi STATIC IMPORTED)\n"
    "  set_target_properties(unofficial::node::ffi PROPERTIES IMPORTED_LOCATION \"\${_node_ffi_lib}\")\n")
if("Debug" IN_LIST _node_configs)
    _node_archive_filename("ffi" _ffi_file)
    string(APPEND _cfg
        "  set_target_properties(unofficial::node::ffi PROPERTIES IMPORTED_LOCATION_DEBUG"
        " \"\${_node_prefix}/debug/lib/${_ffi_file}\")\n")
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
    "    hwy::hwy \${_node_absl_links}\n"
    "    LIEF::LIEF unofficial::node::ffi)\n")
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
endif()  # VCPKG_TARGET_IS_WINDOWS (the static link line's own extras)
endif()  # NOT _node_shared_build (the static link line)

# The stack reserve and the Windows manifest are properties of the executable
# that hosts Node.js, not of the library, so a shared build needs them too -
# which is why they are outside the block above.
#
# They are also MSVC linker options, and passing /STACK to g++ or to Apple's
# ld is a hard error. Getting the guard wrong here is what put "/STACK:0x800000"
# on a Linux link line.
if(VCPKG_TARGET_IS_WINDOWS)
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

# Node.js's own LICENSE is already the aggregate: it is ~2900 lines carrying the
# licence texts of everything in the source tree (V8, npm, and the rest of
# deps/), which is what Node.js ships as the licence of its binaries. The
# libraries this port externalizes are separate vcpkg packages and each one
# installs its own share/<port>/copyright into the consumer's tree, so nothing
# is missing here - listing them again would duplicate other packages' notices.
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
