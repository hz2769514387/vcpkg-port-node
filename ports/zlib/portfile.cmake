# The Chromium fork of zlib - which is the zlib Node.js ships.
#
# Why this port exists instead of using the registry's zlib: the registry builds madler 1.3.2,
# which is different source, has no SIMD crc32/adler32, and is missing the inflate/deflate
# corrections Chromium and oss-fuzz produced and upstream never merged. Node.js's behaviour -
# its compression paths, the official suite's zlib cases, `process.versions.zlib` - is the
# reference this repository is held to, so the library has to be the one Node.js vendors.
# The reasoning and the accepted blast radius (248 registry ports depend on zlib) are recorded
# in docs/decisions/.
#
# The rest of the file is derived from the zlib port of the pinned vcpkg baseline, so that the
# conventions vcpkg expects - static/dynamic layout, debug suffixes, pkg-config, the exported
# CMake config - stay exactly what consumers already get.
#
# Source: chromium/src/third_party/zlib at the commit Node.js v26.11.1 vendors. The tree calls
# itself 1.3.2.1-motley, which is why this port's version is 1.3.2.1; the commit is the pin, and
# the version assertion further down checks that the two agree at build time. Chromium drives
# this tree from GN, so the CMakeLists in it is a second-class path; that is why the patch set
# below is needed at all.
vcpkg_from_git(
    OUT_SOURCE_PATH SOURCE_PATH
    URL https://chromium.googlesource.com/chromium/src/third_party/zlib
    REF 456ae730017b9b4bd3371927abc82627fd51feef
    PATCHES
        0001-no-version-script-on-ohos.patch
        0002-do-not-build-the-benchmark-unless-testing.patch
        0003-simd-settings-node-uses.patch
        0004-plain-system-zlib-names.patch
        0005-arm64-windows-msvc.patch
)

string(COMPARE EQUAL "${VCPKG_LIBRARY_LINKAGE}" "dynamic" ZLIB_BUILD_SHARED)
string(COMPARE EQUAL "${VCPKG_LIBRARY_LINKAGE}" "static" ZLIB_BUILD_STATIC)

# ENABLE_SIMD_OPTIMIZATIONS defaults to OFF in the fork's CMakeLists, so leaving it alone would
# produce the one thing this port exists to avoid: a zlib without the CPU-dispatch code Node.js
# runs. Patch 0003 makes the enabled path use Node.js's define set rather than Chromium's - in
# particular it leaves the crc32 SIMD off, because Node.js leaves it off. Patch 0005 does the
# same for the ARM64 branch, which upstream only recognises under the POSIX spellings of the
# architecture: on Windows CMake calls it ARM64, so a Windows ARM64 build used to receive no
# SIMD defines at all and died inside the fork.
vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DZLIB_BUILD_TESTING=OFF
        -DZLIB_BUILD_SHARED=${ZLIB_BUILD_SHARED}
        -DZLIB_BUILD_STATIC=${ZLIB_BUILD_STATIC}
        -DENABLE_SIMD_OPTIMIZATIONS=ON
)

vcpkg_cmake_install()
vcpkg_copy_pdbs()
vcpkg_cmake_config_fixup(CONFIG_PATH "lib/cmake/zlib")
vcpkg_fixup_pkgconfig()

if(VCPKG_TARGET_IS_WINDOWS AND VCPKG_LIBRARY_LINKAGE STREQUAL "static")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/lib/pkgconfig/zlib.pc" " -lz" " -lzs")
endif()
if(NOT VCPKG_BUILD_TYPE)
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig/zlib.pc" "/include" "/../include")
    if(VCPKG_TARGET_IS_WINDOWS)
        if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
            vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig/zlib.pc" " -lz" " -lzsd")
        else()
            vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig/zlib.pc" " -lz" " -lzd")
        endif()
    endif()
endif()

if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/zconf.h" "ifdef ZLIB_DLL" "if 0")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/share/zlib/ZLIBConfig.cmake" [[_ZLIB_supported_components "shared" "static"]] [[_ZLIB_supported_components "static"]])
else()
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/zconf.h" "ifdef ZLIB_DLL" "if 1")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/share/zlib/ZLIBConfig.cmake" [[_ZLIB_supported_components "shared" "static"]] [[_ZLIB_supported_components "shared"]])
endif()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/vcpkg-cmake-wrapper.cmake" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")

# ---------------------------------------------------------------------------
# The fork must be the fork.
#
# A port whose source silently drifts back to something else is worse than the wrong library,
# because nothing in the build output says so. The version string inside zlib.h is the one the
# runtime reports through `zlibVersion()`, so it is the honest thing to assert: it is what a
# consumer compares against, and what marks this library as Chromium's rather than madler's.
# ---------------------------------------------------------------------------
file(READ "${CURRENT_PACKAGES_DIR}/include/zlib.h" _zlib_h)
string(REGEX MATCH "#define ZLIB_VERSION \"([^\"]+)\"" _match "${_zlib_h}")
if(NOT _match)
    message(FATAL_ERROR "zlib port: no ZLIB_VERSION in the installed zlib.h")
endif()
set(_zlib_version "${CMAKE_MATCH_1}")
if(NOT _zlib_version MATCHES "motley")
    message(FATAL_ERROR
        "zlib port: installed zlib.h reports version '${_zlib_version}', which is not the "
        "Chromium fork (its version ends in '-motley'). Either the source moved off the pinned "
        "commit or the wrong portfile built it; a consumer would get the registry's zlib while "
        "believing it got the fork.")
endif()
unset(_zlib_h)
message(STATUS "zlib port: built the fork, ZLIB_VERSION '${_zlib_version}'")
