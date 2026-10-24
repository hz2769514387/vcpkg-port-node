# utf8cpp 4.1.1, because 4.2 removed the three-argument `internal::validate_next(it, end, cp)`
# that LIEF 1.0.0 calls - and LIEF 1.0.0 is the version Node.js v26.12.1 ships.
#
# 4.1.1 is what the 2026.07.29 baseline had; 2026.10.16 moved to 4.2.1. Same major, so the
# `utf8cpp::utf8cpp` target and the `share/utf8cpp/cmake` layout a consumer sees are unchanged
# - this portfile is the registry's, with REF and SHA512 moved - and one minor back.
# Measured: `source/utf8/core.h` at v4.2.0 has no three-argument overload, v4.1.1 has it.

set(VCPKG_BUILD_TYPE release) # header-only

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO nemtrif/utfcpp
    REF "v${VERSION}"
    SHA512 72061902812b3f5b27afb32c513fc337db4149b8a6e51cbfe497109f88145751484093990bb1b20b4eec2b9f621406690030401b2a51c9368eb481f00225cd24
    HEAD_REF master
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
)

vcpkg_cmake_install()
vcpkg_cmake_config_fixup(PACKAGE_NAME utf8cpp CONFIG_PATH share/utf8cpp/cmake)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
