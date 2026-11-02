# Assert that the installed package matches what its config tells a consumer to link.
#
# Run as `cmake -DPREFIX=<installed prefix> -DLINKAGE=static|dynamic -P assert-install.cmake`,
# from `install.what_the_linkage_ships`. Every failure names the file it expected and, where it
# helps, what the directory does hold - the point of this case is that the answer stops being a
# matter of reading a build log.

if(NOT DEFINED PREFIX AND DEFINED prefix)
  set(PREFIX "${prefix}")
endif()

# Windows passes -D values through the shell; the closing backslash of a path can be eaten.
foreach(_var PREFIX LINKAGE)
  if(NOT DEFINED ${_var})
    message(FATAL_ERROR "assert-install.cmake needs -D${_var}=... (got nothing)")
  endif()
  string(STRIP "${${_var}}" ${_var})
endforeach()

set(_config "${PREFIX}/share/unofficial-node/unofficial-node-config.cmake")
if(NOT EXISTS "${_config}")
  message(FATAL_ERROR
    "no package config at ${_config}. The port installs it unconditionally, so its absence means "
    "the install step did not run or the package was pruned afterwards.")
endif()

set(_headers "${PREFIX}/include/node/node.h")
if(NOT EXISTS "${_headers}")
  message(FATAL_ERROR
    "no ${_headers}. A consumer that includes <node.h> cannot, whatever the library holds.")
endif()

file(READ "${_config}" _config_text)

# The archive list, as the config spells it: set(NODE_PORT_ARCHIVES "libnode:libnode.lib;...")
string(REGEX MATCH "set\\(NODE_PORT_ARCHIVES[ \t]+\"([^\"]*)\"\\)" _archives_match "${_config_text}")
if(NOT _archives_match)
  message(FATAL_ERROR
    "the config has no NODE_PORT_ARCHIVES. Every install sets it - empty for a shared library - so "
    "this usually means the template and the port disagree about the variable's name.")
endif()
set(_archives_csv "${CMAKE_MATCH_1}")

# A short summary of a directory, for the failure messages.
function(_describe_directory _dir _out)
  if(NOT IS_DIRECTORY "${_dir}")
    set(${_out} "${_dir} does not exist" PARENT_SCOPE)
    return()
  endif()
  file(GLOB _files "${_dir}/*")
  list(LENGTH _files _count)
  if(_count EQUAL 0)
    set(${_out} "${_dir} is empty" PARENT_SCOPE)
  elseif(_count GREATER 12)
    list(SUBLIST _files 0 12 _head)
    list(TRANSFORM _head REPLACE "^.*/" "")
    string(REPLACE ";" ", " _head "${_head}")
    set(${_out} "${_dir} holds ${_count} entries, first: ${_head}" PARENT_SCOPE)
  else()
    list(TRANSFORM _files REPLACE "^.*/" "")
    string(REPLACE ";" ", " _files "${_files}")
    set(${_out} "${_dir} holds: ${_files}" PARENT_SCOPE)
  endif()
endfunction()

# Directories that have to agree with the config: Release always, Debug when the install is dual.
set(_lib_dirs "${PREFIX}/lib")
if(IS_DIRECTORY "${PREFIX}/debug/lib")
  list(APPEND _lib_dirs "${PREFIX}/debug/lib")
endif()

if(_archives_csv STREQUAL "")
  # Shared linkage: the config names no archive, and the package must hold none.
  if(NOT LINKAGE STREQUAL "dynamic")
    message(FATAL_ERROR
      "the install is ${LINKAGE} but its config names no archives. A static libnode is a set of "
      "archives and a consumer links all of them.")
  endif()
  foreach(_dir IN LISTS _lib_dirs)
    file(GLOB _strays
         "${_dir}/v8_*.lib" "${_dir}/v8_*.a"
         "${_dir}/node_base.*" "${_dir}/libnode_base.*"
         "${_dir}/node_crates.*" "${_dir}/libnode_crates.*")
    if(_strays)
      list(JOIN _strays ", " _strays_text)
      message(FATAL_ERROR
        "a shared install must ship no node archives, but ${_dir} holds: ${_strays_text}. A "
        "consumer that linked one of these would put a second copy of those symbols in the "
        "process - the failure this repository exists to prevent.")
    endif()
  endforeach()
  file(GLOB _shared_libs
       "${PREFIX}/bin/libnode.dll"
       "${PREFIX}/lib/libnode.so*"
       "${PREFIX}/lib/libnode*.dylib")
  if(NOT _shared_libs)
    _describe_directory("${PREFIX}/lib" _where)
    message(FATAL_ERROR
      "a shared install must ship the library itself, and no libnode.* was found. ${_where}")
  endif()
  message(STATUS
    "shared install: ${_shared_libs}; no archives, as the config says")
  return()
endif()

if(NOT LINKAGE STREQUAL "static")
  message(FATAL_ERROR
    "the install is ${LINKAGE} but its config names ${_archives_csv}. A shared libnode already "
    "contains these objects; naming them again is how a consumer ends up linking two copies.")
endif()

set(_missing "")
set(_checked 0)
foreach(_dir IN LISTS _lib_dirs)
  foreach(_entry IN LISTS _archives_csv)
    string(STRIP "${_entry}" _entry)
    if(_entry STREQUAL "")
      continue()
    endif()
    string(REGEX REPLACE "^[^:]*:" "" _file "${_entry}")
    if(NOT EXISTS "${_dir}/${_file}")
      list(APPEND _missing "${_dir}/${_file}")
    endif()
    math(EXPR _checked "${_checked} + 1")
  endforeach()
endforeach()

if(_missing)
  list(JOIN _missing "\n  " _missing_text)
  _describe_directory("${PREFIX}/lib" _release)
  message(FATAL_ERROR
    "the config tells a consumer to link archives that are not installed:\n  ${_missing_text}\n\n"
    "${_release}\n\n"
    "Either the install step stopped shipping something the config still names, or the file name "
    "changed per configuration.")
endif()

message(STATUS
  "static install: ${_checked} archive(s) checked across ${_lib_dirs}, every one present")
