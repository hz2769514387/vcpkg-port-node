vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO simdjson/simdjson
    REF "v${VERSION}"
    SHA512 9935d9bfa2a178e9bf46da03f39b6d06f1e76c0ad2e094fc755bc2c8542cb58c218c53e55333305208a4cf681cd4520099cac94beff0d229baf9010f834597d0
    HEAD_REF master
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DSIMDJSON_DEVELOPER_MODE=OFF
        -DSIMDJSON_BUILD_STATIC_LIB=OFF
        -DSIMDJSON_TESTS=OFF
        -DSIMDJSON_BENCHMARKS=OFF
)

vcpkg_cmake_install()
vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/${PORT})
vcpkg_fixup_pkgconfig()

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE" "${SOURCE_PATH}/LICENSE-MIT")
