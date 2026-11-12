# Assertions about the package a consumer is told to use.
#
# Everything is read from the installed prefix and from the variables the config file set,
# never from this repository's source tree: the question is whether the delivered package
# describes itself truthfully.
foreach(required PREFIX CONFIG_FILE LINKAGE MODULE_VERSION NAPI_VERSION NAPI_MAX INSTALLED_LIBS)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "check_config.cmake needs ${required}")
  endif()
endforeach()

if(NOT IS_DIRECTORY "${PREFIX}")
  message(FATAL_ERROR "the install prefix does not exist: ${PREFIX}")
endif()
if(NOT EXISTS "${CONFIG_FILE}")
  message(FATAL_ERROR "the exported config does not exist: ${CONFIG_FILE}")
endif()

# --- the imported target ----------------------------------------------------
if(NOT "${STD_FEATURES}" MATCHES "cxx_std_20")
  message(FATAL_ERROR
    "unofficial::node::node does not declare C++20 on its interface: '${STD_FEATURES}'")
endif()

set(_saw_node FALSE)
set(_saw_v8 FALSE)
foreach(dir IN LISTS INCLUDE_DIRS)
  if(NOT IS_DIRECTORY "${dir}")
    message(FATAL_ERROR "an advertised include directory does not exist: ${dir}")
  endif()
  string(FIND "${dir}" "${PREFIX}" _at)
  if(NOT _at EQUAL 0)
    message(FATAL_ERROR "include directory ${dir} is outside the install prefix ${PREFIX}")
  endif()
  if("${dir}" MATCHES "/include/node$")
    set(_saw_node TRUE)
  endif()
  if("${dir}" MATCHES "/include/node-v8$")
    set(_saw_v8 TRUE)
  endif()
endforeach()
if(NOT _saw_node OR NOT _saw_v8)
  message(FATAL_ERROR
    "the Node.js and V8 public header directories are not both on the interface: ${INCLUDE_DIRS}")
endif()

# Windows hosts need the stack reserve Node.js declares; it is a property of the executable
# rather than of the library, so the port has to put it on the interface.
if(ON_WINDOWS AND NOT "${LINK_OPTIONS}" MATCHES "/STACK:")
  message(FATAL_ERROR
    "a Windows consumer got no /STACK link option: '${LINK_OPTIONS}'")
endif()

# --- the files a consumer includes and reads --------------------------------
foreach(relative
    "include/node/node.h"
    "include/node/node_api.h"
    "include/node/js_native_api.h"
    "include/node/node_version.h"
    "include/node/node_buffer.h"
    "include/node-v8/v8.h"
    "include/uv.h"
    "share/node/usage")
  if(NOT EXISTS "${PREFIX}/${relative}")
    message(FATAL_ERROR "the package is missing ${relative}, which the usage text advertises")
  endif()
endforeach()

# --- the numbers an addon author reads -------------------------------------
foreach(number MODULE_VERSION NAPI_VERSION NAPI_MAX)
  if(NOT "${${number}}" MATCHES "^[0-9]+$")
    message(FATAL_ERROR "${number} is not a number: '${${number}}'")
  endif()
endforeach()
if(NAPI_VERSION GREATER NAPI_MAX)
  message(FATAL_ERROR
    "the default N-API ${NAPI_VERSION} is above the maximum ${NAPI_MAX}")
endif()

# --- the linkage the config says it delivers -------------------------------
if(NOT LINKAGE STREQUAL "static" AND NOT LINKAGE STREQUAL "dynamic")
  message(FATAL_ERROR "node_LIBRARY_LINKAGE is '${LINKAGE}', neither static nor dynamic")
endif()
if(LINKAGE STREQUAL "dynamic" AND NOT NODE_PORT_SHARED)
  message(FATAL_ERROR
    "node_LIBRARY_LINKAGE says dynamic but NODE_PORT_SHARED is '${NODE_PORT_SHARED}'")
endif()
if(LINKAGE STREQUAL "static" AND NODE_PORT_SHARED)
  message(FATAL_ERROR
    "node_LIBRARY_LINKAGE says static but NODE_PORT_SHARED is '${NODE_PORT_SHARED}'")
endif()

set(_missing "")
foreach(name IN LISTS INSTALLED_LIBS)
  set(_found FALSE)
  foreach(dir "lib" "lib/manual-link" "debug/lib" "debug/lib/manual-link" "bin" "debug/bin")
    if(EXISTS "${PREFIX}/${dir}/${name}")
      set(_found TRUE)
      break()
    endif()
  endforeach()
  if(NOT _found)
    list(APPEND _missing "${name}")
  endif()
endforeach()
if(_missing)
  message(FATAL_ERROR
    "the config names libraries that were not installed: ${_missing}")
endif()

# --- relocatability ---------------------------------------------------------
# A path from the machine that built the package would make find_package() work only on
# that machine. configure_package_config_file() expresses every location relative to
# PACKAGE_PREFIX_DIR; scan for the shape of a leak rather than for one particular machine.
file(READ "${CONFIG_FILE}" _config_text)
foreach(leak "[A-Za-z]:[/\\\\]" "/buildtrees/" "/downloads/" "/packages/" "/home/" "/Users/")
  if("${_config_text}" MATCHES "${leak}")
    message(FATAL_ERROR
      "the exported config contains a path from the build machine (${leak}); it is not relocatable")
  endif()
endforeach()

message(STATUS "config: ${LINKAGE} install, C++20, ${MODULE_VERSION} ABI, "
               "N-API ${NAPI_VERSION}/${NAPI_MAX}, relocatable")
