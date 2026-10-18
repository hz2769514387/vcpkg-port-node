if(VCPKG_TARGET_IS_WINDOWS AND NOT VCPKG_TARGET_IS_MINGW)
    vcpkg_check_linkage(ONLY_STATIC_LIBRARY)
endif()

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO HdrHistogram/HdrHistogram_c
    REF ${VERSION}
    SHA512 d103a8a1951f79eb9964dbdcd566076a14527b1b1b688f2487e2a00facb09328a52dec8740df95b13d11894ad38450faafe8af90b26a9e2cc1f1c61008163aa7
    HEAD_REF main
    PATCHES
        001-fix-pkgconfig.patch
)

if("log" IN_LIST FEATURES)
    list(APPEND FEATURE_OPTIONS "-DHDR_LOG_REQUIRED=ON")
else()
    list(APPEND FEATURE_OPTIONS "-DHDR_LOG_REQUIRED=DISABLED")
endif()

if(VCPKG_LIBRARY_LINKAGE STREQUAL "dynamic")
    list(APPEND FEATURE_OPTIONS "-DHDR_HISTOGRAM_BUILD_STATIC:BOOL=OFF")
    list(APPEND FEATURE_OPTIONS "-DHDR_HISTOGRAM_INSTALL_STATIC:BOOL=OFF")
else()
    list(APPEND FEATURE_OPTIONS "-DHDR_HISTOGRAM_BUILD_SHARED:BOOL=OFF")
    list(APPEND FEATURE_OPTIONS "-DHDR_HISTOGRAM_INSTALL_SHARED:BOOL=OFF")
endif()

# Do not build tests and examples
list(APPEND FEATURE_OPTIONS "-DHDR_HISTOGRAM_BUILD_PROGRAMS:BOOL=OFF")

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        ${FEATURE_OPTIONS}
)

vcpkg_cmake_install()

vcpkg_cmake_config_fixup(
    PACKAGE_NAME hdr_histogram
    CONFIG_PATH lib/cmake/hdr_histogram
)

vcpkg_fixup_pkgconfig()

vcpkg_copy_pdbs()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE.txt" "${SOURCE_PATH}/COPYING.txt")

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
