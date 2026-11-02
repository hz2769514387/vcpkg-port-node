# OpenSSL, as the pinned vcpkg baseline builds it - with one deliberate difference.
#
# Why an overlay exists: the library's C code has to be compiled by the same
# compiler as Node.js, and on Windows that is clang-cl - `vcbuild.bat` forces it
# for every Node.js >= 24 ("ClangCL is required because the Node.js version being
# compiled is >= 24"). vcpkg builds its ports with cl.exe, so OpenSSL arrived as
# the one library in the process compiled by something else, and for arm64 the
# two do not agree: with cl.exe-built OpenSSL the arm64 Windows suite crashed in
# 250 silent TLS cases while the official Node.js binary was clean on the same
# runner, and with OpenSSL's C code built by clang-cl - every other option left
# exactly as the baseline has it - the same suite passes completely (issue #22).
# windows/portfile.cmake therefore points the build at clang-cl.
#
# The assembly is deliberately left as the baseline ships it. Building with
# `no-asm` first was a hypothesis about that difference, and it was wrong: the
# crash set came back byte-identical, 250 cases and the same 254 failing tests.
# The assembler was already clang in the baseline, so holding it constant is also
# what made the result above about the C compiler rather than about both.
#
# Everything below this point is derived from the openssl port of the pinned
# vcpkg baseline (2026.10.16), so the conventions vcpkg expects - the install
# layout, the debug suffixes, the pkg-config files, the exported CMake config -
# stay exactly what consumers already get. There is exactly one other edit:
# unix/portfile.cmake sets the executable bit on the configure wrapper at build
# time, because this repository's git cannot record one (core.fileMode is false)
# and the wrapper is invoked as `./vcpkg/configure`, directly. Re-diff against
# the baseline when the pin moves - this file was last re-derived at 2026.10.16.
if(EXISTS "${CURRENT_INSTALLED_DIR}/share/libressl/copyright"
    OR EXISTS "${CURRENT_INSTALLED_DIR}/share/boringssl/copyright")
    message(FATAL_ERROR "Can't build openssl if libressl/boringssl is installed. Please remove libressl/boringssl, and try install openssl again if you need it.")
endif()

if(VCPKG_TARGET_IS_EMSCRIPTEN)
    vcpkg_check_linkage(ONLY_STATIC_LIBRARY)
endif()

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO openssl/openssl
    REF "openssl-${VERSION}"
    SHA512 40f0b346a9a5cf4cb37f1ecebdc74750c39a95783710061bfac58964883b0831543ecee0aee9f747ea093781b13c58a543b0b935d222519e3cb19648d77a0276
    PATCHES
        cmake-config.patch
        command-line-length.patch
        script-prefix.patch
        windows/install-layout.patch
        windows/install-pdbs.patch
        windows/install-programs.diff # https://github.com/openssl/openssl/issues/28744
        unix/android-cc.patch
        unix/move-openssldir.patch
        unix/no-empty-dirs.patch
        unix/no-static-libs-for-shared.patch
)

vcpkg_list(SET CONFIGURE_OPTIONS
    enable-static-engine
    enable-capieng
    no-tests
    no-docs
)

# https://github.com/openssl/openssl/blob/master/INSTALL.md#enable-ec_nistp_64_gcc_128
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")
if(VCPKG_DETECTED_CMAKE_C_COMPILER_ID MATCHES "^(GNU|Clang|AppleClang)$"
   AND VCPKG_TARGET_ARCHITECTURE MATCHES "^(x64|arm64|riscv64|ppc64le)$")
    vcpkg_list(APPEND CONFIGURE_OPTIONS enable-ec_nistp_64_gcc_128)
endif()

set(INSTALL_FIPS "")
if("fips" IN_LIST FEATURES)
    vcpkg_list(APPEND INSTALL_FIPS install_fips)
    vcpkg_list(APPEND CONFIGURE_OPTIONS enable-fips)
endif()

if(VCPKG_LIBRARY_LINKAGE STREQUAL "dynamic")
    vcpkg_list(APPEND CONFIGURE_OPTIONS shared)
else()
    vcpkg_list(APPEND CONFIGURE_OPTIONS no-shared no-module)
endif()

if(NOT "tools" IN_LIST FEATURES)
    vcpkg_list(APPEND CONFIGURE_OPTIONS no-apps)
endif()

if("weak-ssl-ciphers" IN_LIST FEATURES)
    vcpkg_list(APPEND CONFIGURE_OPTIONS enable-weak-ssl-ciphers)
endif()

if("ssl3" IN_LIST FEATURES)
    vcpkg_list(APPEND CONFIGURE_OPTIONS enable-ssl3)
    vcpkg_list(APPEND CONFIGURE_OPTIONS enable-ssl3-method)
endif()

if(DEFINED OPENSSL_USE_NOPINSHARED)
    vcpkg_list(APPEND CONFIGURE_OPTIONS no-pinshared)
endif()

if(OPENSSL_NO_AUTOLOAD_CONFIG)
    vcpkg_list(APPEND CONFIGURE_OPTIONS no-autoload-config)
endif()

if(VCPKG_TARGET_IS_WINDOWS AND NOT VCPKG_TARGET_IS_MINGW)
    include("${CMAKE_CURRENT_LIST_DIR}/windows/portfile.cmake")
    include("${CMAKE_CURRENT_LIST_DIR}/install-pc-files.cmake")
else()
    include("${CMAKE_CURRENT_LIST_DIR}/unix/portfile.cmake")
endif()

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")

if (NOT "${VERSION}" MATCHES [[^([0-9]+)\.([0-9]+)\.([0-9]+)$]])
    message(FATAL_ERROR "Version regex did not match.")
endif()
set(OPENSSL_VERSION_MAJOR "${CMAKE_MATCH_1}")
set(OPENSSL_VERSION_MINOR "${CMAKE_MATCH_2}")
set(OPENSSL_VERSION_FIX "${CMAKE_MATCH_3}")
configure_file("${CMAKE_CURRENT_LIST_DIR}/vcpkg-cmake-wrapper.cmake.in" "${CURRENT_PACKAGES_DIR}/share/${PORT}/vcpkg-cmake-wrapper.cmake" @ONLY)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE.txt")
