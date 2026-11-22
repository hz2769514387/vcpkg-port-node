# Run the embedder with a command line and require BOTH a zero exit code and a marker in stdout.
#
# ctest's PASS_REGULAR_EXPRESSION ignores the process exit code, so "it printed the line" used to
# pass even if a shutdown hook failed afterwards. This driver keeps the two assertions separate:
# a nonzero result is a failure whatever was printed, and a missing marker is a failure even when
# the process exited cleanly (which is what catches an ignored -e or -p argument).

if(NOT DEFINED EXE OR NOT DEFINED EXPECT)
  message(FATAL_ERROR "check_cli: EXE and EXPECT are required")
endif()

set(_cli_args)
foreach(_index RANGE 1 4)
  if(DEFINED ARG${_index})
    list(APPEND _cli_args "${ARG${_index}}")
  endif()
endforeach()

execute_process(COMMAND "${EXE}" ${_cli_args}
                RESULT_VARIABLE _cli_result
                OUTPUT_VARIABLE _cli_output
                ERROR_VARIABLE _cli_errors)

if(NOT _cli_result EQUAL 0)
  message(FATAL_ERROR "check_cli: exit ${_cli_result}; stdout: ${_cli_output}; stderr: ${_cli_errors}")
endif()
if(NOT "${_cli_output}" MATCHES "${EXPECT}")
  message(FATAL_ERROR "check_cli: '${EXPECT}' missing from stdout: ${_cli_output}")
endif()
message(STATUS "check_cli: ok (${EXPECT})")
