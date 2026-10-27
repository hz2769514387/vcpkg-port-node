# Consumer config: unofficial-node.
#
# Owns: the facts the template substitutes (linkage, ABI versions, archive list, platform
# switches) and the two configure_package_config_file/write_basic_package_version_file calls.
# The description itself is cmake/unofficial-node-config.cmake.in.
#
# Expects from the portfile: _node_configs, _node_shared_build, _node_shlib_name,
# _node_installed_libs and the source tree.

# ---------------------------------------------------------------------------
# 6) Consumer config (unofficial-node).
#
#    The libraries are gyp artifacts, not CMake targets, so what a consumer receives is a set of
#    imported targets this port describes. That description lives in
#    cmake/unofficial-node-config.cmake.in as ordinary CMake, expanded by
#    configure_package_config_file(), with the build-time facts substituted as values.
#
#    It used to be CMake emitted from escaped string literals - ~550 lines of `"  set(\${...})\n"` -
#    which is how the package's version became a literal that then went stale against the source
#    tree it delivered, and how a typo here became an unreadable failure in a consumer's project.
# ---------------------------------------------------------------------------
include(CMakePackageConfigHelpers)
include("${NODE_PORT_DIR}/cmake/source-facts.cmake")

function(_node_archive_filename _target _out)
    if(VCPKG_TARGET_IS_WINDOWS)
        set(${_out} "${_target}.lib" PARENT_SCOPE)
    else()
        # gyp strips a leading "lib" from the target name before adding its own prefix, so
        # target `libnode` yields libnode.a, `node_base` yields libnode_base.a.
        string(REGEX REPLACE "^lib" "" _stripped "${_target}")
        set(${_out} "lib${_stripped}.a" PARENT_SCOPE)
    endif()
endfunction()

# --- the facts the template substitutes -------------------------------------------------------
set(NODE_PORT_SHARED       OFF)
set(NODE_PORT_HAS_DEBUG    OFF)
set(NODE_PORT_HAS_TOOLS    OFF)
set(NODE_PORT_HAS_SUITE    OFF)
set(NODE_PORT_IS_WINDOWS   OFF)
set(NODE_PORT_IS_APPLE     OFF)
set(NODE_PORT_CRT_STATIC   OFF)
set(NODE_PORT_LINK_GROUP   OFF)

if(_node_shared_build)
    set(NODE_PORT_SHARED ON)
endif()
if("Debug" IN_LIST _node_configs)
    set(NODE_PORT_HAS_DEBUG ON)
endif()
if("tools" IN_LIST FEATURES)
    set(NODE_PORT_HAS_TOOLS ON)
endif()
if("test-suite" IN_LIST FEATURES)
    set(NODE_PORT_HAS_SUITE ON)
endif()
if(VCPKG_TARGET_IS_WINDOWS)
    set(NODE_PORT_IS_WINDOWS ON)
endif()
if(VCPKG_TARGET_IS_OSX)
    set(NODE_PORT_IS_APPLE ON)
endif()
if(VCPKG_CRT_LINKAGE STREQUAL "static")
    set(NODE_PORT_CRT_STATIC ON)
endif()
# GNU linkers are the ones that get $<LINK_GROUP:RESCAN>: Windows' link.exe rescans the archive
# list itself and Apple's ld64 has no rescan construct at all.
if(NOT VCPKG_TARGET_IS_WINDOWS AND NOT VCPKG_TARGET_IS_OSX)
    set(NODE_PORT_LINK_GROUP ON)
endif()

# Which artifact the consumer gets, stated rather than inferred from the file names, because both
# linkages install a file called libnode*.
if(_node_shared_build)
    set(_node_linkage_str "dynamic")
else()
    set(_node_linkage_str "static")
endif()
set(NODE_PORT_LINKAGE             "${_node_linkage_str}")
set(NODE_PORT_MODULE_VERSION      "${node_module_version}")
set(NODE_PORT_NAPI_VERSION        "${node_napi_version}")
set(NODE_PORT_NAPI_VERSION_MAX    "${node_napi_version_max}")
set(NODE_PORT_INSTALLED_LIBRARIES "${_node_installed_libs}")
if(VCPKG_TARGET_IS_WINDOWS)
    set(NODE_PORT_EXE_NAME "node.exe")
    set(NODE_PORT_SHIM_EXT ".cmd")
    set(NODE_PORT_RT_ARCH  "${_node_rt_arch}")
else()
    set(NODE_PORT_EXE_NAME "node")
    set(NODE_PORT_SHIM_EXT "")
endif()

if(_node_shared_build)
    if(VCPKG_TARGET_IS_WINDOWS)
        set(NODE_PORT_SHLIB_FILE  "libnode.dll")
        # gyp names the import library "<dll>.lib"; see cmake/install.cmake.
        set(NODE_PORT_IMPLIB_FILE "libnode.dll.lib")
    else()
        # libnode.147.dylib / libnode.so.147 - globbed from the build tree, because the module
        # version is part of the name.
        set(NODE_PORT_SHLIB_FILE "${_node_shlib_name}")
    endif()
else()
    # Every archive gyp produced, as "<target>:<file>", so the template can build one imported
    # target per archive without repeating a block per name. abseil/highway/simdutf/zlib come from
    # vcpkg; v8_zlib remains (patched down to compression_utils_portable.cc, so it defines no zlib
    # core symbols); LIEF and libffi are vcpkg packages wired as their own targets.
    # Everything gyp produces for a Node.js build. abseil/highway/simdutf/zlib come from vcpkg;
    # v8_zlib remains (patched down to compression_utils_portable.cc, so it defines no zlib core
    # symbols). LIEF, libffi, nghttp2 and abseil are imported separately below.
    set(_node_all_archives
        libnode node_base
        v8_base_without_compiler v8_compiler v8_init v8_initializers
        v8_snapshot v8_libbase v8_libplatform v8_zlib
        ncrypto ncrypto_engine nbytes merve uvwasi crdtp node_crates)
    set(NODE_PORT_ARCHIVES "")
    foreach(_a IN LISTS _node_all_archives)
        _node_archive_filename("${_a}" _file)
        list(APPEND NODE_PORT_ARCHIVES "${_a}:${_file}")
    endforeach()
    unset(_a)
    unset(_file)
    _node_archive_filename("nghttp2" NODE_PORT_NGHTTP2_FILE)
    _node_archive_filename("ffi" NODE_PORT_FFI_FILE)
endif()

if(VCPKG_TARGET_IS_WINDOWS)
    set(NODE_PORT_STACK_RESERVE "${node_stack_reserve}")
endif()

configure_package_config_file(
    "${NODE_PORT_DIR}/cmake/unofficial-node-config.cmake.in"
    "${CURRENT_PACKAGES_DIR}/share/unofficial-node/unofficial-node-config.cmake"
    INSTALL_DESTINATION "share/unofficial-node"
    NO_SET_AND_CHECK_MACRO
    NO_CHECK_REQUIRED_COMPONENTS_MACRO)

# The version a consumer sees is the source tree's, compared against the manifest by
# cmake/source-facts.cmake:
# a package can no longer claim a version it does not deliver. AnyNewerVersion is the
# compatibility the hand-written file used to express.
write_basic_package_version_file(
    "${CURRENT_PACKAGES_DIR}/share/unofficial-node/unofficial-node-config-version.cmake"
    VERSION "${node_version_string}"
    COMPATIBILITY AnyNewerVersion)
