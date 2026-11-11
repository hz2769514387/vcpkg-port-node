# Did NODE_OPTIONS reach V8? Run the same embedder twice with two --max-old-space-size
# values supplied only through the environment, and compare the heap limits it reports.
#
# One run is not enough: the absolute heap limit depends on the machine's memory and on
# V8's own defaults, so there is no portable constant to assert. A larger requested limit
# producing a larger reported limit is portable, and a NODE_OPTIONS that was dropped
# entirely would make the two numbers identical.
if(NOT DEFINED EXE OR NOT DEFINED SCRIPT)
  message(FATAL_ERROR "check_node_options.cmake needs EXE and SCRIPT")
endif()

function(_node_port_heap_limit _flag _out_var)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env "NODE_OPTIONS=${_flag}" "${EXE}" "${SCRIPT}"
    RESULT_VARIABLE _code
    OUTPUT_VARIABLE _text
    ERROR_VARIABLE _err)
  if(NOT _code EQUAL 0)
    message(FATAL_ERROR
      "NODE_OPTIONS='${_flag}' run failed with ${_code}. stdout: ${_text} stderr: ${_err}")
  endif()
  string(REGEX MATCH "[0-9]+" _value "${_text}")
  if(NOT _value)
    message(FATAL_ERROR "no heap limit in the output: '${_text}'")
  endif()
  set(${_out_var} "${_value}" PARENT_SCOPE)
endfunction()

_node_port_heap_limit("--max-old-space-size=192" _small)
_node_port_heap_limit("--max-old-space-size=512" _large)

message(STATUS "NODE_OPTIONS 192 MB -> ${_small} bytes; 512 MB -> ${_large} bytes")
if(NOT _large GREATER _small)
  message(FATAL_ERROR
    "NODE_OPTIONS did not reach the runtime: a larger --max-old-space-size produced "
    "${_large} bytes, not more than ${_small} bytes")
endif()
