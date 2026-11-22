# The command line a host hands to node::Start is still Node.js's command line.
#
# An embedder is free to reinterpret argv; this one does not, and a product that passes
# --max-old-space-size, preloads a module with --require, or evaluates a script with -e needs
# that to stay true. NODE_OPTIONS is a separate path again - it arrives through the environment,
# not argv - and is checked by running the same executable twice with two different values.
#
# NODE_OPTIONS is set explicitly in every one of these cases. A developer machine can carry a
# NODE_OPTIONS of its own (a language shim, a wrapper), and a test that silently inherits it
# would be testing that machine instead of the port.

set(_cli_clean "NODE_OPTIONS=")

add_test(NAME cli.flags
         COMMAND node_embedder --expose-gc --max-old-space-size=256
                 "${CMAKE_CURRENT_SOURCE_DIR}/flags.mjs")
set_tests_properties(cli.flags PROPERTIES
  ENVIRONMENT "${_cli_clean}"
  TIMEOUT 180
  LABELS "smoke")

# The four argument cases below go through check_cli.cmake rather than PASS_REGULAR_EXPRESSION:
# CMake ignores the exit code when a PASS regex matches, and the version in cli.print has to be a
# real regex rather than a dotted string that also matches "26x13x1".
string(REPLACE "." "\." _cli_version_regex "${unofficial-node_VERSION}")

add_test(NAME cli.eval_cjs
         COMMAND "${CMAKE_COMMAND}"
           "-DEXE=$<TARGET_FILE:node_embedder>"
           "-DEXPECT=cli-eval-cjs-ok"
           "-DARG1=-e"
           "-DARG2=console.log('cli-eval-cjs-ok')"
           -P "${CMAKE_CURRENT_SOURCE_DIR}/check_cli.cmake")
set_tests_properties(cli.eval_cjs PROPERTIES
  ENVIRONMENT "${_cli_clean}"
  TIMEOUT 120
  LABELS "smoke")

add_test(NAME cli.eval_module
         COMMAND "${CMAKE_COMMAND}"
           "-DEXE=$<TARGET_FILE:node_embedder>"
           "-DEXPECT=cli-eval-module-ok"
           "-DARG1=--input-type=module"
           "-DARG2=-e"
           "-DARG3=import assert from 'node:assert/strict'
assert.equal(1 + 1, 2)
console.log('cli-eval-module-ok')"
           -P "${CMAKE_CURRENT_SOURCE_DIR}/check_cli.cmake")
set_tests_properties(cli.eval_module PROPERTIES
  ENVIRONMENT "${_cli_clean}"
  TIMEOUT 120
  LABELS "smoke")

add_test(NAME cli.print
         COMMAND "${CMAKE_COMMAND}"
           "-DEXE=$<TARGET_FILE:node_embedder>"
           "-DEXPECT=${_cli_version_regex}"
           "-DARG1=-p"
           "-DARG2=process.versions.node"
           -P "${CMAKE_CURRENT_SOURCE_DIR}/check_cli.cmake")
set_tests_properties(cli.print PROPERTIES
  ENVIRONMENT "${_cli_clean}"
  TIMEOUT 120
  LABELS "smoke")

add_test(NAME cli.preload
         COMMAND "${CMAKE_COMMAND}"
           "-DEXE=$<TARGET_FILE:node_embedder>"
           "-DEXPECT=cli: preload ok"
           "-DARG1=--require"
           "-DARG2=${CMAKE_CURRENT_SOURCE_DIR}/preload.cjs"
           "-DARG3=${CMAKE_CURRENT_SOURCE_DIR}/preload_app.cjs"
           -P "${CMAKE_CURRENT_SOURCE_DIR}/check_cli.cmake")
set_tests_properties(cli.preload PROPERTIES
  ENVIRONMENT "${_cli_clean}"
  TIMEOUT 120
  LABELS "smoke")

# NODE_OPTIONS cannot be checked with one run: the absolute heap limit depends on the machine.
# Two runs of the same binary, with two different limits, say whether the environment flag
# reached V8 at all.
add_test(NAME cli.node_options
         COMMAND "${CMAKE_COMMAND}"
           -DEXE=$<TARGET_FILE:node_embedder>
           -DSCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/node_options.mjs
           -P "${CMAKE_CURRENT_SOURCE_DIR}/check_node_options.cmake")
set_tests_properties(cli.node_options PROPERTIES TIMEOUT 180 LABELS "smoke")
