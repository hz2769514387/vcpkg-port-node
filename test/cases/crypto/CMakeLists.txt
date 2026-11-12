# OpenSSL is externalized to vcpkg, so every crypto path a product uses is a path through
# that library rather than through Node.js's vendored copy.
#
# cases/externalization proves the build-time switch and one known-answer hash. This case
# exercises what an application actually does: authenticated encryption, key generation,
# signing and verification, WebCrypto, and the algorithms a TLS stack would ask for. A
# wrong OpenSSL version, a provider that failed to load, or an engine that is only half
# linked all show up here.

add_test(NAME crypto.application_paths
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/crypto.mjs")
set_tests_properties(crypto.application_paths PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  TIMEOUT 180
  LABELS "smoke")

# The same script through the port's own node.exe when the tools feature is installed: a
# different link of the same runtime, and the executable a consumer's build scripts run.
if(DEFINED node_EXECUTABLE AND EXISTS "${node_EXECUTABLE}")
  add_test(NAME crypto.application_paths_tools
           COMMAND "${node_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/crypto.mjs")
  set_tests_properties(crypto.application_paths_tools PROPERTIES
    ENVIRONMENT "NODE_OPTIONS="
    TIMEOUT 180
    LABELS "smoke")
endif()
