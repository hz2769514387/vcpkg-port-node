# How a Node.js process ends is part of what an embedder delivers.
#
# cases/embed checks three exit codes. This case checks the lifecycle around them: exit hooks
# seeing the right code, process.exit() stopping the script, beforeExit being allowed to add
# more work to the loop, an uncaughtException handler getting the throw, and the
# --unhandled-rejections switch changing a rejected promise from a warning into a fatal error.
# A host that shuts the runtime down by killing the process would still produce exit codes; it
# would fail every one of these.

function(node_port_exit_case _name _script _expect)
  set(_options "")
  set(_one MUST_PRINT MUST_NOT_PRINT)
  set(_multi FLAGS)
  cmake_parse_arguments(CASE "${_options}" "${_one}" "${_multi}" ${ARGN})
  add_test(NAME exit.${_name}
    COMMAND "${CMAKE_COMMAND}"
      -DEXE=$<TARGET_FILE:node_embedder>
      -DSCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/${_script}
      -DEXPECT=${_expect}
      -DFLAGS=${CASE_FLAGS}
      -DMUST_PRINT=${CASE_MUST_PRINT}
      -DMUST_NOT_PRINT=${CASE_MUST_NOT_PRINT}
      -P "${CMAKE_CURRENT_SOURCE_DIR}/check_exit.cmake")
  set_tests_properties(exit.${_name} PROPERTIES
    ENVIRONMENT "NODE_OPTIONS="
    TIMEOUT 120
    LABELS "smoke")
endfunction()

node_port_exit_case(exit_code exit_code.cjs 9 MUST_PRINT "exit-hook-9")
node_port_exit_case(process_exit process_exit.cjs 5
                    MUST_PRINT "exit-hook-5" MUST_NOT_PRINT "unreachable")
node_port_exit_case(before_exit before_exit.cjs 0 MUST_PRINT "before-exit-2")
node_port_exit_case(uncaught_handler uncaught_handler.cjs 3 MUST_PRINT "caught-boom")
node_port_exit_case(rejection_strict rejection.cjs 1 FLAGS --unhandled-rejections=strict)
node_port_exit_case(rejection_warn rejection.cjs 0 FLAGS --unhandled-rejections=warn)
