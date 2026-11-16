vcpkg_check_linkage(ONLY_STATIC_LIBRARY)

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO nodejs/llhttp
    REF refs/tags/release/v${VERSION}
    SHA512 4037a9222938215b16c0e837709d7ac77f4828d33cbcf6dd828f6620ca90020870cac92d4f794a0c6995b291be1b9c7783627c433216bf7e94661e1613b2d2e3
    PATCHES
)
string(COMPARE EQUAL "${VCPKG_LIBRARY_LINKAGE}" "static" LLHTTP_BUILD_STATIC)
string(COMPARE EQUAL "${VCPKG_LIBRARY_LINKAGE}" "dynamic" LLHTTP_BUILD_SHARED)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    DISABLE_PARALLEL_CONFIGURE
    OPTIONS
      -DLLHTTP_BUILD_SHARED_LIBS=${LLHTTP_BUILD_SHARED}
      -DLLHTTP_BUILD_STATIC_LIBS=${LLHTTP_BUILD_STATIC}
)

vcpkg_cmake_install()
vcpkg_copy_pdbs()

vcpkg_cmake_config_fixup(
    CONFIG_PATH "/lib/cmake/${PORT}"
)
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE-MIT")

vcpkg_fixup_pkgconfig()
