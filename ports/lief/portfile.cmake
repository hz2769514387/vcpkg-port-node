vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO lief-project/LIEF
    REF "${VERSION}"
    SHA512 35d86d23306be0d9713fe6feb4632d83945a3e81557d12c6bdc23164818981dea30483d9ed7fdd5f8ba91803ceec716244f43527221e407f4b8fae021743e6a3
    HEAD_REF main
)

# LIEF 1.0.0 can pull its third-party dependencies with FetchContent from zips
# that ship inside its own source tree, but that is exactly what must not
# happen here: a library compiled into our artifacts has to exist exactly once
# in a consumer's process, and an embedded copy would collide with the vcpkg
# port of the same library the moment a consumer links both. So every
# dependency is externalized through LIEF's own switches:
#
#   nlohmann-json 3.12.0 == what LIEF vendors    -> registry port as-is
#   spdlog        1.17.0 == what LIEF vendors    -> registry port as-is
#   tl-expected    1.3.1 == what LIEF vendors    -> registry port as-is
#   utfcpp         4.0.9 <  registry 4.1.1       -> registry port as-is (ahead)
#   frozen      61dce5a  >  registry 1.2.0       -> overlay pin (ports/frozen)
#   mbedtls   4.0.0 snapshot > registry 3.6.5    -> overlay pin (ports/mbedtls);
#       required, not just policy: LIEF's external branch does
#       find_package(MbedTLS 4.0.0) and links the tf-psa-crypto targets
#   tcb-span  b70b0ff = registry snapshot + the no-exceptions include fix that
#       LIEF's tree carries -> overlay (ports/tcb-span); LIEF builds with
#       exceptions disabled by default, which activates that branch
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
        -DLIEF_OPT_NLOHMANN_JSON_EXTERNAL=ON
        -DLIEF_OPT_EXTERNAL_EXPECTED=ON
        -DLIEF_OPT_UTFCPP_EXTERNAL=ON
        -DLIEF_OPT_FROZEN_EXTERNAL=ON
        -DLIEF_EXTERNAL_SPDLOG=ON
        -DLIEF_OPT_MBEDTLS_EXTERNAL=ON
        # tcb-span is header-only: point LIEF at the installed include dir.
        # Header-only deps install their headers only in the release tree,
        # which is the right dir for both configurations.
        -DLIEF_OPT_EXTERNAL_SPAN=ON
        "-DLIEF_EXTERNAL_SPAN_DIR=${CURRENT_INSTALLED_DIR}/include/tcb"
)

vcpkg_cmake_install()
vcpkg_cmake_config_fixup(CONFIG_PATH "lib/cmake/LIEF")
vcpkg_fixup_pkgconfig()

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
