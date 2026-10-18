# The manifest says 1.2.0 - the last release tag. The pin is the post-1.2.0
# commit 61dce5a (2025-07-29) that LIEF 1.0.0 vendors; see vcpkg.json for why
# the tag alone is not enough.
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO serge-sans-paille/frozen
    REF 61dce5ae18ca59931e27675c468e64118aba8744
    SHA512 b8dfe741c82bc178dfc9749d4ab5a130cee718d9ee7b71d9b547cf5f7f23027ed0152ad250012a8546399fcc1e12187efc68d89d6731256c4d2df7d04eef8d5c
    HEAD_REF master
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
      -Dfrozen.benchmark=OFF
      -Dfrozen.coverage=OFF
      -Dfrozen.installation=ON
      -Dfrozen.tests=OFF
)
vcpkg_cmake_install()

vcpkg_cmake_config_fixup(CONFIG_PATH share/cmake/frozen)

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug")

file(INSTALL "${SOURCE_PATH}/LICENSE" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright)
