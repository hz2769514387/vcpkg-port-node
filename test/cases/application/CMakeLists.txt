# A shipping application, not a snippet.
#
# The embedder is handed a directory that looks like a product's source tree: a package.json that
# declares "type": "module", an ESM entry point, a CommonJS module it still depends on, a bare
# specifier out of node_modules, a JSON module, a dynamic import and a top-level await. All of those
# have to resolve through Node.js's own loader with the process argv, cwd and module paths a real
# host supplies - none of which a "it printed hello" case would exercise.
#
# The node_modules fixture is checked in on purpose: it is the one shape that proves bare specifier
# resolution rather than a relative path this project happens to know.

add_test(NAME application.module_graph
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/app/main.mjs")
set_tests_properties(application.module_graph PROPERTIES TIMEOUT 180 LABELS "smoke")

# The process object a host application reads before it does anything else: its own executable,
# the script it was handed, its working directory, the environment it was launched with and the
# ABI numbers it will use to choose a native addon. The version and module version come from the
# exported config, so a package that advertises one runtime and delivers another fails here.
add_test(NAME application.process_shape
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/process_shape.mjs")
set_tests_properties(application.process_shape PROPERTIES
  ENVIRONMENT "NODE_PORT_SENTINEL=from-ctest;NODE_PORT_EXPECTED_VERSION=${unofficial-node_VERSION};NODE_PORT_EXPECTED_MODULES=${node_MODULE_VERSION}"
  TIMEOUT 180
  LABELS "smoke")
