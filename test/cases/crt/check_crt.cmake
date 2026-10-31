# Does the executable use the CRT we told CMake to use?
#
# `CMAKE_MSVC_RUNTIME_LIBRARY` is a promise in a preset. Whether the binary honours it is a property of
# the binary, and nothing else in this project looks: a link against the static libnode *succeeds* with
# the wrong CRT sometimes, and the failure - a missing redistributable on a consumer's machine, or two
# heaps in one process - happens somewhere else entirely.
#
# The check reads the import table, which is the only place the answer is written down:
#
#   /MT, /MTd  -> no VCRUNTIME140*.dll, no MSVCP140*.dll, no ucrtbase*.dll: the CRT is inside the binary
#   /MD, /MDd  -> those three are imports, and the binary needs the redistributable at run time
#
# Driven by ctest with -DEXE, -DRUNTIME (the target's resolved MSVC_RUNTIME_LIBRARY) and -DREADOBJ.

if(NOT DEFINED EXE OR NOT DEFINED RUNTIME OR NOT DEFINED READOBJ)
  message(FATAL_ERROR "check_crt: EXE, RUNTIME and READOBJ are required")
endif()
if(NOT EXISTS "${EXE}")
  message(FATAL_ERROR "check_crt: ${EXE} does not exist")
endif()

# "MultiThreaded", "MultiThreadedDebug", "MultiThreadedDLL", "MultiThreadedDebugDLL".
string(FIND "${RUNTIME}" "DLL" _dll_at)
if(_dll_at EQUAL -1)
  set(_expect dynamic_crt_absent)
  set(_expect_text "a static CRT (no VCRUNTIME140/MSVCP140/ucrtbase imports)")
else()
  set(_expect dynamic_crt_present)
  set(_expect_text "a dynamic CRT (VCRUNTIME140 and ucrtbase imported)")
endif()

# llvm-readobj ships beside clang-cl, which is why the path is passed in rather than searched for.
execute_process(
  COMMAND "${READOBJ}" --coff-imports "${EXE}"
  OUTPUT_VARIABLE _imports
  ERROR_VARIABLE _err
  RESULT_VARIABLE _rc)
if(NOT _rc EQUAL 0)
  message(FATAL_ERROR "check_crt: ${READOBJ} failed (${_rc}):\n${_err}")
endif()

# Import {
#   Name: KERNEL32.dll
#   ...
# }
string(REGEX MATCHALL "Name: [A-Za-z0-9_.+-]+" _names "${_imports}")
set(_crt_dlls "")
foreach(_n IN LISTS _names)
  string(REGEX REPLACE "^Name: " "" _dll "${_n}")
  if(_dll MATCHES "^(VCRUNTIME140|MSVCP140|ucrtbase)")
    list(APPEND _crt_dlls "${_dll}")
  endif()
endforeach()

if(_dll_at EQUAL -1)
  if(_crt_dlls)
    message(FATAL_ERROR
      "check_crt: ${RUNTIME} says the CRT is static, but ${EXE} imports ${_crt_dlls}.\n"
      "  The binary would need the Visual C++ redistributable on every machine that runs it - the "
      "opposite of what the triplet and the preset promise.")
  endif()
  message(STATUS "check_crt: ${EXE} has a static CRT, as ${RUNTIME} says")
else()
  if(NOT _crt_dlls)
    message(FATAL_ERROR
      "check_crt: ${RUNTIME} says the CRT is dynamic, but ${EXE} imports none of "
      "VCRUNTIME140/MSVCP140/ucrtbase.\n"
      "  Either the property never reached the target, or something replaced the runtime library "
      "underneath it.")
  endif()
  message(STATUS "check_crt: ${EXE} imports ${_crt_dlls}, as ${RUNTIME} says")
endif()
