if(VCPKG_TARGET_IS_WINDOWS)
    vcpkg_check_linkage(ONLY_STATIC_LIBRARY)
endif()

vcpkg_download_distfile(ARCHIVE
    URLS "https://github.com/google/perfetto/releases/download/v${VERSION}/perfetto-cpp-sdk-src.zip"
    FILENAME "perfetto-cpp-sdk-src-v${VERSION}.zip"
    SHA512 e64de5b41c4ae84da3b71fd811bef15d19428327b320b53cdf80b32f5d456d52051cdd3862ff5c5bb03f9ad7a4e75c7f2140ae670a4f9825513fb28fb397e2c9
)

# The release asset is the amalgamated C++ SDK: the zip holds exactly two files,
# perfetto.h and perfetto.cc, at its root with no wrapping directory, so the
# default "unwrap one level" extraction has nothing to unwrap.
vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}" NO_REMOVE_ONE_LEVEL)

file(COPY "${CMAKE_CURRENT_LIST_DIR}/CMakeLists.txt" DESTINATION "${SOURCE_PATH}")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/LICENSE" DESTINATION "${SOURCE_PATH}")

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
)

vcpkg_cmake_install()
vcpkg_cmake_config_fixup(PACKAGE_NAME unofficial-${PORT})

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
