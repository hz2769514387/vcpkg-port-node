# Runs the embedding executable against a script and asserts the exit code.
#
# ctest compares a test's exit code against zero, which cannot express "this program is
# supposed to exit with 7". A driver script can: it runs the program, prints what it saw,
# and fails when the code differs from the expected one.
#
# Variables, all required:
#   EXE     the executable to run
#   SCRIPT  the JavaScript file to hand it
#   EXPECT  the exit code it must produce

if(NOT DEFINED EXE OR NOT DEFINED SCRIPT OR NOT DEFINED EXPECT)
  message(FATAL_ERROR "check_exit.cmake needs EXE, SCRIPT and EXPECT")
endif()

execute_process(
  COMMAND "${EXE}" "${SCRIPT}"
  RESULT_VARIABLE _code
  OUTPUT_VARIABLE _stdout
  ERROR_VARIABLE _stderr
)

string(STRIP "${_stdout}" _stdout)
string(STRIP "${_stderr}" _stderr)
message(STATUS "stdout: ${_stdout}")
if(NOT _stderr STREQUAL "")
  message(STATUS "stderr: ${_stderr}")
endif()

if(NOT _code EQUAL EXPECT)
  message(FATAL_ERROR "expected exit code ${EXPECT}, got ${_code}")
endif()

message(STATUS "exit code ${_code}, as expected")
