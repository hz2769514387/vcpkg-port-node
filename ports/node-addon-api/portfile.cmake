# The C++ wrapper headers, for an engine that embeds the node port.
#
# The registry port is built around node.exe: it depends on node-api-headers for
# include/node_api.h and for lib/node.lib, the node executable's import library. An embedding
# engine has neither - it compiles the addon into its own link unit and the napi_* symbols
# come from the node port's libnode. This copy therefore installs only the three wrapper
# headers and leaves <node_api.h> to the node port (include/node/node_api.h), so the addon is
# compiled against the same Node.js the runtime links.
vcpkg_from_github(
  OUT_SOURCE_PATH SOURCE_PATH
  REPO nodejs/node-addon-api
  REF "v${VERSION}"
  SHA512 d7b30fc6263f40524285e702e7be9ed2dd578ee035fc0d08f902da67240073fd4dbac5b59261bef90b7f11b5d0b5ddc94dc4252dd286ea9f06deb4efe46f7796
  HEAD_REF main
)

file(COPY "${SOURCE_PATH}/napi.h" DESTINATION "${CURRENT_PACKAGES_DIR}/include")
file(COPY "${SOURCE_PATH}/napi-inl.h" DESTINATION "${CURRENT_PACKAGES_DIR}/include")
file(COPY "${SOURCE_PATH}/napi-inl.deprecated.h" DESTINATION "${CURRENT_PACKAGES_DIR}/include")

file(COPY "${CMAKE_CURRENT_LIST_DIR}/unofficial-node-addon-api-config.cmake"
     DESTINATION "${CURRENT_PACKAGES_DIR}/share/unofficial-${PORT}")

file(INSTALL "${SOURCE_PATH}/LICENSE.md" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright)
