vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO lief-project/LIEF
    REF "${VERSION}"
    SHA512 35d86d23306be0d9713fe6feb4632d83945a3e81557d12c6bdc23164818981dea30483d9ed7fdd5f8ba91803ceec716244f43527221e407f4b8fae021743e6a3
    HEAD_REF main
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DLIEF_INSTALL=ON
        -DLIEF_TESTS=OFF
        -DLIEF_EXAMPLES=OFF
        -DLIEF_COMPILE_DOC_EXAMPLES=OFF
        -DLIEF_USE_CCACHE=OFF
        -DLIEF_PROFILING=OFF
        -DLIEF_FUZZING=OFF
        -DLIEF_PRECOMPILED=OFF
)

vcpkg_cmake_install()
vcpkg_cmake_config_fixup(PACKAGE_NAME LIEF)
vcpkg_fixup_pkgconfig()

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
