# Mbed TLS pinned to the 4.0.0 development snapshot that LIEF 1.0.0 vendors
# (commit ec4044008d, 2025-10-13, plus the framework and TF-PSA-Crypto
# submodules it references).
#
# Why an overlay: the vcpkg baseline ships 3.6.5, which predates the
# tf-psa-crypto / mbedx509 library split. LIEF 1.0.0 requires
# find_package(MbedTLS 4.0.0) and links MbedTLS::tfpsacrypto and
# MbedTLS::mbedx509, neither of which exists in 3.6.x.
#
# The snapshot is a development commit, so its git tree lacks the files
# mbedtls's own release process generates (error.c, version_features.c,
# ssl_debug_helpers_generated.c, the driver wrappers and the config-check
# headers - see generated/). Regenerating them at build time would need perl,
# python with jsonschema+jinja2, and would run the generators inside the
# consumer's build; instead the generated/ directory carries the output of
# those exact generators against this exact commit and the stock config, and
# the portfile lays them over the source tree. If the pin moves, regenerate
# with GEN_FILES=ON (a one-off: configure with -DGEN_FILES=ON and collect the
# files the build tree gains under tf-psa-crypto/core/ and library/).
if(VCPKG_TARGET_IS_WINDOWS)
    vcpkg_check_linkage(ONLY_STATIC_LIBRARY) # same dllimport limitation as the registry port
endif()

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO Mbed-TLS/mbedtls
    REF ec4044008d2d069da38288bc76b0fee34ec78646
    SHA512 9c9cdcbeb91aade94928097813f1e96206eeb17a11bc165d6f6366d64c1c5ec363ee645f187e1260c9de3581b044d2fa935cc62852a2db2c69f980e6e2d57a5a
    HEAD_REF development
)

# framework and tf-psa-crypto are git submodules of mbedtls, and vcpkg's
# download helpers cannot fetch submodules. The top-level CMakeLists adds both
# as subdirectories unconditionally, so both are pinned here at the commits the
# mbedtls commit references in its .gitmodules (resolved through the Git tree
# of ec4044008d, where both paths are gitlinks). tf-psa-crypto in turn carries
# its own nested framework submodule - at the same commit - so the framework
# tree is placed twice.
#
# The submodules are fetched as plain downloads rather than through
# vcpkg_from_github because tf-psa-crypto needs a patch applied while it is
# still a standalone tree (see below), which PATCHES on the main download
# cannot do: the file only exists once the submodule has been moved in.
vcpkg_from_github(
    OUT_SOURCE_PATH FRAMEWORK_PATH
    REPO Mbed-TLS/mbedtls-framework
    REF 457996474728cb8e968ed21953b72f74d2f536b2
    SHA512 765b1674e4b3e0c4e42bf84e72bd58098872102656f5d8de02aac9a5f6229874fffaa3299be67c4a7821cd8944ca6fdf484018e8750b58c2e5c2db6fae3e2a2b
    HEAD_REF main
)

vcpkg_download_distfile(ARCHIVE_TF_PSA_CRYPTO
    URLS "https://github.com/Mbed-TLS/TF-PSA-Crypto/archive/76920edddcad00ac41b248e12d937b845df7bedb.tar.gz"
    FILENAME "Mbed-TLS-TF-PSA-Crypto-76920edddcad00ac41b248e12d937b845df7bedb.tar.gz"
    SHA512 c6ce0b3a9740f3acfb04352bdc87d5850280823d6d30a3729f6999e864da3a8192432d03ab9a1377179287fa74e525f7f3db1b3b05a465fe146c9ba54310196d
)
vcpkg_extract_source_archive(
    TF_PSA_CRYPTO_PATH
    ARCHIVE "${ARCHIVE_TF_PSA_CRYPTO}"
    PATCHES
        0001-no-doxygen-version-files.patch
)

file(REMOVE_RECURSE
    "${SOURCE_PATH}/framework"
    "${SOURCE_PATH}/tf-psa-crypto"
)
file(RENAME "${FRAMEWORK_PATH}" "${SOURCE_PATH}/framework")
file(RENAME "${TF_PSA_CRYPTO_PATH}" "${SOURCE_PATH}/tf-psa-crypto")
file(COPY "${SOURCE_PATH}/framework" DESTINATION "${SOURCE_PATH}/tf-psa-crypto")

# The generated files a release tree carries (see the header comment). They are
# laid over the source tree so the build needs neither perl nor python.
file(COPY "${CMAKE_CURRENT_LIST_DIR}/generated/" DESTINATION "${SOURCE_PATH}")

string(COMPARE EQUAL "${VCPKG_LIBRARY_LINKAGE}" "dynamic" USE_SHARED_MBEDTLS_LIBRARY)
string(COMPARE EQUAL "${VCPKG_LIBRARY_LINKAGE}" "static" USE_STATIC_MBEDTLS_LIBRARY)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DENABLE_TESTING=OFF
        -DENABLE_PROGRAMS=OFF
        -DMBEDTLS_FATAL_WARNINGS=OFF
        -DUSE_SHARED_MBEDTLS_LIBRARY=${USE_SHARED_MBEDTLS_LIBRARY}
        -DUSE_STATIC_MBEDTLS_LIBRARY=${USE_STATIC_MBEDTLS_LIBRARY}
)

vcpkg_cmake_install()
vcpkg_copy_pdbs()
vcpkg_fixup_pkgconfig()
vcpkg_cmake_config_fixup(CONFIG_PATH "lib/cmake/MbedTLS")

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
)

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
