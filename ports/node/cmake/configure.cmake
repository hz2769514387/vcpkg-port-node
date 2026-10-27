# What this port tells configure.py, before any dependency is wired in.
#
# Owns: the /WHOLEARCHIVE rewrites node.gyp needs under the ninja generator, the MSBuild
# platform spelling for arm64, and the flags configure.py is called with (--dest-cpu,
# --clang-cl, --with-intl, --shared, and the rest).
#
# Expects from the portfile: SOURCE_PATH, _node_cc / _node_cxx, VCPKG_TARGET_IS_*.

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

    # CRT channel (see cmake/toolchain.cmake): configure.py reads
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
