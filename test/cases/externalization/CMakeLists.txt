# Is this build the version the port claims?
#
# Provenance, not behaviour: a vendored dependency compiled back in after a patch stopped applying, or
# a version bump that took only one of the two places it is pinned, both show up here and nowhere else
# that runs in seconds.
#
# One claim per file, and each runs on both hosts - the embedding executable and the port's own
# node.exe - because they are two different links of the same runtime and a build can get one right
# and the other wrong.

# Did every externalized dependency come from the vcpkg tree, and is this the version the port says?
add_test(NAME externalization.embedder
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/externalization.mjs")
set_tests_properties(externalization.embedder PROPERTIES
  ENVIRONMENT "NODE_PORT_EXPECTED_VERSION=${unofficial-node_VERSION}"
  TIMEOUT 180
  LABELS "smoke")

if(NOT DEFINED node_EXECUTABLE OR NOT EXISTS "${node_EXECUTABLE}")
  message(STATUS
    "no node executable installed (the node port's tools feature is off) - "
    "not registering the tools half of this case")
  return()
endif()

add_test(NAME externalization.tools
         COMMAND "${node_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/externalization.mjs")
set_tests_properties(externalization.tools PROPERTIES
  ENVIRONMENT "NODE_PORT_EXPECTED_VERSION=${unofficial-node_VERSION}"
  TIMEOUT 180
  LABELS "smoke")
