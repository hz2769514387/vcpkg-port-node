# The CRT the binary actually has, against the one the preset asked for.
#
# One claim: the runtime library a consumer ends up with is the one its triplet names. The presets set
# `CMAKE_MSVC_RUNTIME_LIBRARY` per triplet - `MultiThreaded(Debug)` for the static-CRT triplets,
# `...DLL` for `x64-windows-static-md` and `x64-windows` - and until this case existed nothing checked
# that the produced executable agreed. See check_crt.cmake for what the import table can and cannot say.
#
# Windows only: on Unix the C runtime is part of the system, there is no choice to verify.

if(NOT WIN32)
  return()
endif()
if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang|MSVC")
  return()
endif()

# llvm-readobj ships in the same directory as clang-cl, which is the compiler this project is built
# with; falling back to the Visual Studio toolset would mean guessing its layout.
get_filename_component(_crt_llvm_bin "${CMAKE_CXX_COMPILER}" DIRECTORY)
set(_crt_readobj "${_crt_llvm_bin}/llvm-readobj${CMAKE_EXECUTABLE_SUFFIX}")
if(NOT EXISTS "${_crt_readobj}")
  message(STATUS
    "llvm-readobj not beside ${CMAKE_CXX_COMPILER} - not registering the CRT case (it would have to "
    "guess which readobj to use, and a check that guesses is worse than a documented gap)")
  return()
endif()
if(NOT TARGET node_embedder)
  message(STATUS "node_embedder is not built - not registering the CRT case")
  return()
endif()

# `$<TARGET_PROPERTY:...>` gives the value for the configuration under test, which is what the binary
# was linked with; the cache variable alone would be the un-resolved generator expression.
add_test(NAME crt.matches_the_triplet
  COMMAND "${CMAKE_COMMAND}"
    -DEXE=$<TARGET_FILE:node_embedder>
    "-DRUNTIME=$<TARGET_PROPERTY:node_embedder,MSVC_RUNTIME_LIBRARY>"
    "-DREADOBJ=${_crt_readobj}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/check_crt.cmake")
set_tests_properties(crt.matches_the_triplet PROPERTIES TIMEOUT 120 LABELS "smoke")

# The archives the link consumed, not just what the link resolved to. `node_INSTALLED_LIBRARIES` is the
# list of files the port installs, as names; the directory is the package's lib/ (or lib/manual-link,
# which is where the port keeps the archives vcpkg does not export).
#
# This is the case that would have seen issue #56 for what it is: an archive built for one runtime
# library reaching a link built for the other shows up as mixed CRT directives inside one file, and the
# linker then either warns (LNK4098) or says nothing at all.
set(_crt_archives "")
if(DEFINED node_INSTALLED_LIBRARIES AND node_INSTALLED_LIBRARIES)
  get_filename_component(_crt_prefix "${unofficial-node_DIR}/../.." ABSOLUTE)
  foreach(_crt_name IN LISTS node_INSTALLED_LIBRARIES)
    foreach(_crt_dir IN ITEMS "${_crt_prefix}/lib" "${_crt_prefix}/lib/manual-link"
                            "${_crt_prefix}/debug/lib" "${_crt_prefix}/debug/lib/manual-link")
      if(EXISTS "${_crt_dir}/${_crt_name}")
        list(APPEND _crt_archives "${_crt_dir}/${_crt_name}")
        break()
      endif()
    endforeach()
  endforeach()
endif()

if(_crt_archives)
  string(FIND "${CMAKE_MSVC_RUNTIME_LIBRARY}" "DLL" _crt_dll_at)
  if(_crt_dll_at EQUAL -1)
    set(_crt_expect static)
  else()
    set(_crt_expect dynamic)
  endif()
  set(_crt_lib_args "")
  foreach(_crt_archive IN LISTS _crt_archives)
    list(APPEND _crt_lib_args --lib "${_crt_archive}")
  endforeach()
  add_test(NAME crt.archives_consistent
    COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/check_libnode_crt.mjs"
            --expect "${_crt_expect}" ${_crt_lib_args})
  set_tests_properties(crt.archives_consistent PROPERTIES TIMEOUT 600 LABELS "smoke")
else()
  message(STATUS "node_INSTALLED_LIBRARIES gave no resolvable archive - not registering crt.archives_consistent")
endif()
