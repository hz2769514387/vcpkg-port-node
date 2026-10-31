# The mechanics every case shares: putting a shared libnode where a consumer would put it.
#
# Included from the top-level CMakeLists, and the functions it defines are called from the directory
# that creates each executable - add_custom_command(TARGET ...) may only name a target created in the
# same directory, and every executable in this project is created in a case directory. Measured on
# windows-shared, the first leg that got far enough to exercise it: six errors, "TARGET 'node_embedder'
# was not created in this directory", one per executable. The Unix branch of the same function is a
# property and would have been fine from the top level; the Windows branch is a build command and is
# not.

# A shared libnode has to be findable when the thing that links it runs, and
# that is the consumer's job rather than the port's - so this project does it
# the way a consumer has to, and the README says so.
#
# Windows: the DLL is copied next to the executable. $<TARGET_RUNTIME_DLLS> is
# used rather than a path built by hand because the location is per
# configuration (bin/ versus debug/bin/), and it also covers anything else in
# the graph that turns out to be a DLL.
# Unix: the library's directory goes into the build RPATH, which is what
# libnode's own install name asks for ($ORIGIN on Linux, @rpath on macOS).
function(node_test_runtime_libs _target)
  if(NOT DEFINED node_LIBRARY_LINKAGE OR NOT node_LIBRARY_LINKAGE STREQUAL "dynamic")
    return()
  endif()
  if(WIN32)
    # The exported config links libnode itself and nothing else, and the
    # Windows loader searches the *executable's* directory - never the
    # directory of the DLL whose import is being resolved. Copying only
    # libnode.dll next to the executable would therefore leave libnode's own
    # imports (uv.dll, libcrypto-3-x64.dll, icuuc.dll, ...) unfindable, and
    # the process would die at startup with a message that names neither the
    # missing DLL nor the reason. Measured rather than assumed: an executable
    # in one directory loading a DLL from another, with that DLL's dependency
    # sitting right beside it, fails with ERROR_MOD_NOT_FOUND (126) until the
    # dependency is either next to the executable or on PATH.
    #
    # $<TARGET_RUNTIME_DLLS> stays for anything else in the graph that turns
    # out to be a DLL; the directory sweep is what makes the set complete,
    # and it is per configuration because a Debug consumer links the debug
    # tree's DLLs. Every generator expression is quoted on purpose: a bare
    # one is written into a Visual Studio project as $<0:...> / $<1:...> and
    # reaches the command line as literal text (measured: "The system cannot
    # find the path specified"), while the quoted form is evaluated per
    # configuration and COMMAND_EXPAND_LISTS turns the semicolons into
    # separate arguments.
    get_filename_component(_node_bin_dir "${node_SHARED_LIBRARY}" DIRECTORY)
    get_filename_component(_node_prefix "${_node_bin_dir}" DIRECTORY)
    # `bin/` and `lib/`, both configurations: vcpkg's convention is bin/, but not every port
    # follows it - LIEF ships `lib/LIEF.dll` next to its import library, and libnode.dll imports
    # it. Measured on windows-shared: with only bin/ swept, the consumer executables started and
    # blocked on Windows' "DLL not found" message box - which nobody clicks in CI, so
    # zlib.cross_paths.runtime timed out at 120 s and both suite shards at 5400 s each, four
    # hours burned on a missing file.
    file(GLOB _node_dlls_release "${_node_bin_dir}/*.dll" "${_node_prefix}/lib/*.dll")
    file(GLOB _node_dlls_debug "${_node_prefix}/debug/bin/*.dll" "${_node_prefix}/debug/lib/*.dll")
    add_custom_command(TARGET ${_target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
              "$<TARGET_RUNTIME_DLLS:${_target}>"
              "$<$<CONFIG:Debug>:${_node_dlls_debug}>"
              "$<$<NOT:$<CONFIG:Debug>>:${_node_dlls_release}>"
              "$<TARGET_FILE_DIR:${_target}>"
      COMMAND_EXPAND_LISTS)
  else()
    get_filename_component(_node_shlib_dir "${node_SHARED_LIBRARY}" DIRECTORY)
    get_filename_component(_node_prefix "${_node_shlib_dir}" DIRECTORY)
    set_property(TARGET ${_target} PROPERTY BUILD_RPATH
                 "${_node_prefix}/lib;${_node_prefix}/debug/lib")
  endif()
endfunction()

# tools/node/node.exe is not a CMake target, so it cannot be handed its DLLs
# the way node_test_runtime_libs does it for the executables this project
# builds. On Windows the loader searches the executable's own directory and
# PATH, and the port keeps the DLLs in bin/ while node.exe lives in
# tools/node/ - measured, not assumed: an executable in one directory loading
# a DLL from another, with that DLL's dependency beside it, fails with
# ERROR_MOD_NOT_FOUND (126) until the dependency is either next to the
# executable or on PATH. So the DLLs are copied next to it, the same way the
# consumer executables get theirs, and every test that runs node.exe works
# without any per-test environment plumbing.
#
# Not an ENVIRONMENT PATH entry: ctest splits the ENVIRONMENT property on
# semicolons, so a PATH value with more than one directory is truncated at
# the first one and the inherited PATH is lost with it. Measured, and the
# truncation is silent.
if(WIN32 AND DEFINED node_LIBRARY_LINKAGE AND node_LIBRARY_LINKAGE STREQUAL "dynamic"
   AND DEFINED node_EXECUTABLE AND DEFINED node_TOOLS_DIR)
  get_filename_component(_node_bin_dir "${node_SHARED_LIBRARY}" DIRECTORY)
  get_filename_component(_node_prefix "${_node_bin_dir}" DIRECTORY)
  # bin/ *and* lib/, for the same reason the consumer executables sweep both: `lib/LIEF.dll` is
  # a dependency of libnode.dll that vcpkg does not install under bin/, and a Windows process
  # missing a DLL waits on a message box instead of failing. Measured on windows-shared: every
  # `smoke.*.tools` case timed out - 180 s each - because `tools/node/node.exe` could not start.
  file(GLOB _node_tool_dlls "${_node_bin_dir}/*.dll" "${_node_prefix}/lib/*.dll")
  if(_node_tool_dlls)
    add_custom_target(node_tools_dlls ALL
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
              ${_node_tool_dlls} "${node_TOOLS_DIR}/"
      COMMENT "node: DLLs next to tools/node/node.exe")
  endif()
  unset(_node_tool_dlls)
  unset(_node_bin_dir)
  unset(_node_prefix)
endif()

