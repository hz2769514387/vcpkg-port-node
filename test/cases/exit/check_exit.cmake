# Runs the embedder with optional flags, asserts its exit code, and checks the output.
#
# ctest compares a test's exit code with zero, which cannot express "this program is supposed
# to exit with 9". A driver can. MUST_PRINT / MUST_NOT_PRINT are what make the exit hooks and
# the shutdown order observable: an exit code alone cannot tell that `beforeExit` ran twice,
# or that process.exit() really stopped the script.
#
# Variables: EXE, SCRIPT, EXPECT (required); FLAGS, MUST_PRINT, MUST_NOT_PRINT (optional).
if(NOT DEFINED EXE OR NOT DEFINED SCRIPT OR NOT DEFINED EXPECT)
  message(FATAL_ERROR "check_exit.cmake needs EXE, SCRIPT and EXPECT")
endif()

set(_command "${EXE}")
if(FLAGS)
  list(APPEND _command ${FLAGS})
endif()
list(APPEND _command "${SCRIPT}")

execute_process(
  COMMAND ${_command}
  RESULT_VARIABLE _code
  OUTPUT_VARIABLE _stdout
  ERROR_VARIABLE _stderr)

string(STRIP "${_stdout}" _stdout)
string(STRIP "${_stderr}" _stderr)
message(STATUS "stdout: ${_stdout}")
if(NOT _stderr STREQUAL "")
  message(STATUS "stderr: ${_stderr}")
endif()

if(NOT _code EQUAL EXPECT)
  message(FATAL_ERROR "expected exit code ${EXPECT}, got ${_code}")
endif()
if(MUST_PRINT AND NOT "${_stdout}" MATCHES "${MUST_PRINT}")
  message(FATAL_ERROR "expected stdout to contain '${MUST_PRINT}', got '${_stdout}'")
endif()
if(MUST_NOT_PRINT AND "${_stdout}" MATCHES "${MUST_NOT_PRINT}")
  message(FATAL_ERROR "stdout unexpectedly contains '${MUST_NOT_PRINT}': '${_stdout}'")
endif()

message(STATUS "exit code ${_code}, as expected")
