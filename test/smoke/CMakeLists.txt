# Fast assertions about the installed port, runnable on every push.
#
# These are deliberately not Node.js tests - the official suite does that. Each one here is
# about provenance or identity: is this build the version the port claims, and did each
# externalized dependency really come from the vcpkg tree? Those are cheap questions that
# catch expensive problems (a vendored library being compiled in again after a patch stops
# applying, a version bump that took only one of the two places it is pinned).

set(_externalization "${CMAKE_CURRENT_SOURCE_DIR}/externalization.mjs")

add_test(NAME smoke.externalization.embedder COMMAND node_embedder "${_externalization}")
set_tests_properties(smoke.externalization.embedder PROPERTIES
  ENVIRONMENT "NODE_PORT_EXPECTED_VERSION=${unofficial-node_VERSION}"
  TIMEOUT 180
  LABELS "smoke")

# The two ABI numbers a consumer reads without linking anything: NODE_MODULE_VERSION decides which
# prebuilt addon may be loaded, NAPI_VERSION which native API surface may be called. The config
# publishes both; nothing compared them with the runtime until this case. A wrong number fails in
# the consumer's addon load, with a message that names neither this port nor this file.
add_test(NAME smoke.abi COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/abi.mjs")
set_tests_properties(smoke.abi PROPERTIES
  ENVIRONMENT "NODE_PORT_MODULE_VERSION=${node_MODULE_VERSION};NODE_PORT_NAPI_VERSION=${node_NAPI_VERSION}"
  TIMEOUT 180
  LABELS "smoke")

# The startup snapshot is a build artefact nothing else asserts, and losing it is silent: the
# runtime still works, it just compiles the builtins at every startup.
add_test(NAME smoke.snapshot.embedder
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/snapshot.mjs")
set_tests_properties(smoke.snapshot.embedder PROPERTIES
  TIMEOUT 180
  LABELS "smoke")

if(NOT DEFINED node_EXECUTABLE OR NOT EXISTS "${node_EXECUTABLE}")
  message(STATUS
    "no node executable installed (the node port's tools feature is off) - "
    "skipping the tools-feature smoke tests")
  return()
endif()

add_test(NAME smoke.externalization.tools COMMAND "${node_EXECUTABLE}" "${_externalization}")
set_tests_properties(smoke.externalization.tools PROPERTIES
  ENVIRONMENT "NODE_PORT_EXPECTED_VERSION=${unofficial-node_VERSION}"
  TIMEOUT 180
  LABELS "smoke")

add_test(NAME smoke.snapshot.tools
         COMMAND "${node_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/snapshot.mjs")
set_tests_properties(smoke.snapshot.tools PROPERTIES
  TIMEOUT 180
  LABELS "smoke")

add_test(NAME smoke.tools.version COMMAND "${node_EXECUTABLE}" -p "process.versions.node")
set_tests_properties(smoke.tools.version PROPERTIES
  PASS_REGULAR_EXPRESSION "${unofficial-node_VERSION}"
  TIMEOUT 180
  LABELS "smoke")

# npm and npx through their JS entry points rather than their shims: on Windows the shims are
# .cmd files, which ctest cannot execute directly, and the goal is to prove npm is installed
# and runs, not to test our own six-line wrapper.
if(DEFINED node_TOOLS_DIR AND EXISTS "${node_TOOLS_DIR}/node_modules/npm/bin/npm-cli.js")
  add_test(NAME smoke.tools.npm
           COMMAND "${node_EXECUTABLE}" "${node_TOOLS_DIR}/node_modules/npm/bin/npm-cli.js" --version)
  set_tests_properties(smoke.tools.npm PROPERTIES
    PASS_REGULAR_EXPRESSION "[0-9]+[.][0-9]+[.][0-9]+"
    TIMEOUT 300
    LABELS "smoke")
endif()

if(DEFINED node_TOOLS_DIR AND EXISTS "${node_TOOLS_DIR}/node_modules/npm/bin/npx-cli.js")
  add_test(NAME smoke.tools.npx
           COMMAND "${node_EXECUTABLE}" "${node_TOOLS_DIR}/node_modules/npm/bin/npx-cli.js" --version)
  set_tests_properties(smoke.tools.npx PROPERTIES
    PASS_REGULAR_EXPRESSION "[0-9]+[.][0-9]+[.][0-9]+"
    TIMEOUT 300
    LABELS "smoke")
endif()
