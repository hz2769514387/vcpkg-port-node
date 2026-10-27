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

# Where this port lives. The modules under cmake/ are include()d, and CMAKE_CURRENT_LIST_DIR inside
# an included file is that file's directory - so one explicit name for the port's own directory,
# set before anything else runs, and used everywhere a path into the port is needed. The consumer
# config template is the one exception: inside it, CMAKE_CURRENT_LIST_DIR is the *installed* place,
# which is what it should be.
set(NODE_PORT_DIR "${CMAKE_CURRENT_LIST_DIR}")

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

# The URL and the file name come from the manifest version rather than repeating it: the two
# drifted apart once already (the portfile kept 26.12.0 in the file name while the manifest said
# something else), and a mismatch between them is a build that fails with "file not found" a week
# after the bump looked fine.
vcpkg_download_distfile(NODE_ARCHIVE
    URLS "https://nodejs.org/dist/v${VERSION}/node-v${VERSION}.tar.xz"
    SHA512 f6f76e258af33f7f877c65a2141d281ea307aae017a90bb8a75a7d4df271ad9d17c7d0edfd5751a977edd6bdb03c704d727628c4c7215c878d421787a35240f2
    FILENAME node-v${VERSION}.tar.xz
)

# The patch set fixes defects in gyp's ninja/MSVC emulation that upstream never
# sees (its Windows build goes through MSBuild, its Unix builds through Make),
# plus the v26 crates target and the externalization of simdutf/zlib.
# The patch set fixes defects in gyp's ninja/MSVC emulation that upstream never sees (its Windows
# build goes through the MSBuild generator, its Unix builds through Make), plus the v26 crates
# target and the externalization of simdutf/zlib.
#
# The list is the directory, sorted: adding a patch is adding a file. It used to be 25 lines of
# "${NODE_PORT_DIR}/patches/NNNN-..." kept in step with the directory by hand, where a
# patch could sit unapplied while the portfile still looked complete. The numbering is asserted so
# a gap or a duplicate is a build error rather than a silent reordering.
file(GLOB _node_patch_files "${NODE_PORT_DIR}/patches/*.patch")
list(SORT _node_patch_files)
set(_node_patch_expected 1)
foreach(_patch IN LISTS _node_patch_files)
    get_filename_component(_patch_name "${_patch}" NAME)
    if(NOT _patch_name MATCHES "^([0-9][0-9][0-9][0-9])-")
        message(FATAL_ERROR
            "patch '${_patch_name}' does not start with a four-digit number; the name order is "
            "what defines the order they apply in.")
    endif()
    set(_patch_number "${CMAKE_MATCH_1}")
    math(EXPR _patch_number_dec "${_patch_number}" OUTPUT_FORMAT DECIMAL)
    if(NOT _patch_number_dec EQUAL _node_patch_expected)
        message(FATAL_ERROR
            "patch numbering has a gap at ${_node_patch_expected}: found '${_patch_name}'. "
            "Patches apply in name order, so a gap means a renumbering went wrong.")
    endif()
    math(EXPR _node_patch_expected "${_node_patch_expected} + 1")
endforeach()
list(LENGTH _node_patch_files _node_patch_count)
message(STATUS "node port: ${_node_patch_count} patches, numbered 0001-${_patch_number}")
unset(_patch)
unset(_patch_name)
unset(_patch_number)
unset(_patch_number_dec)

vcpkg_extract_source_archive(SOURCE_PATH
    ARCHIVE "${NODE_ARCHIVE}"
    SOURCE_BASE node-v${VERSION}
    PATCHES
        ${_node_patch_files}
)

# Build-time tools from vcpkg's tool cache, so nothing has to be preinstalled.
vcpkg_find_acquire_program(PYTHON3)
vcpkg_find_acquire_program(NINJA)

#
# Everything below this point is one include per concern. The order matters - toolchain decides
# the compiler the rest of the file talks about, configure decides what it is told, externalize
# what it is linked against, build runs it, install moves the result, features add the optional
# halves, and config describes all of it to a consumer - and it is the order the sections were
# always in. Nothing below shares a scope boundary with the portfile: an include is one scope, so
# a variable set in toolchain is visible to build.
#

include("${NODE_PORT_DIR}/cmake/toolchain.cmake")
include("${NODE_PORT_DIR}/cmake/configure.cmake")
include("${NODE_PORT_DIR}/cmake/externalize.cmake")
include("${NODE_PORT_DIR}/cmake/build.cmake")
include("${NODE_PORT_DIR}/cmake/install.cmake")
include("${NODE_PORT_DIR}/cmake/features.cmake")
include("${NODE_PORT_DIR}/cmake/config.cmake")

file(INSTALL "${NODE_PORT_DIR}/usage"
    DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")

# Node.js's own LICENSE is already the aggregate: it is ~2900 lines carrying the
# licence texts of everything in the source tree (V8, npm, and the rest of
# deps/), which is what Node.js ships as the licence of its binaries. The
# libraries this port externalizes are separate vcpkg packages and each one
# installs its own share/<port>/copyright into the consumer's tree, so nothing
# is missing here - listing them again would duplicate other packages' notices.
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
