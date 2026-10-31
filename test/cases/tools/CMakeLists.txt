# The tools feature: is there a node.exe, and do npm and npx run through it?
#
# Separate from the other cases because it asks about a *feature* of the port rather than about the
# library - the whole file is conditional on the port having installed an executable.

if(NOT DEFINED node_EXECUTABLE OR NOT EXISTS "${node_EXECUTABLE}")
  message(STATUS
    "no node executable installed (the node port's tools feature is off) - skipping the tools cases")
  return()
endif()

add_test(NAME tools.version COMMAND "${node_EXECUTABLE}" -p "process.versions.node")
set_tests_properties(tools.version PROPERTIES
  PASS_REGULAR_EXPRESSION "${unofficial-node_VERSION}"
  TIMEOUT 180
  LABELS "smoke")

# npm and npx through their JS entry points rather than their shims: on Windows the shims are .cmd
# files, which ctest cannot execute directly, and the goal is to prove npm is installed and runs, not
# to test our own six-line wrapper.
if(DEFINED node_TOOLS_DIR AND EXISTS "${node_TOOLS_DIR}/node_modules/npm/bin/npm-cli.js")
  add_test(NAME tools.npm
           COMMAND "${node_EXECUTABLE}" "${node_TOOLS_DIR}/node_modules/npm/bin/npm-cli.js" --version)
  set_tests_properties(tools.npm PROPERTIES
    PASS_REGULAR_EXPRESSION "[0-9]+[.][0-9]+[.][0-9]+"
    TIMEOUT 300
    LABELS "smoke")
endif()

if(DEFINED node_TOOLS_DIR AND EXISTS "${node_TOOLS_DIR}/node_modules/npm/bin/npx-cli.js")
  add_test(NAME tools.npx
           COMMAND "${node_EXECUTABLE}" "${node_TOOLS_DIR}/node_modules/npm/bin/npx-cli.js" --version)
  set_tests_properties(tools.npx PROPERTIES
    PASS_REGULAR_EXPRESSION "[0-9]+[.][0-9]+[.][0-9]+"
    TIMEOUT 300
    LABELS "smoke")
endif()
