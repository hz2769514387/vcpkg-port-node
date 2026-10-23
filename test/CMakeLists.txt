# Consumer-side validation project for the node port.
#
# This project answers two questions, and only those two:
#   1) Can the port be *consumed*? Everything here goes through the public path - overlay
#      ports, a manifest, a stock vcpkg triplet, `find_package(unofficial-node CONFIG)`.
#      Nothing reaches past the installed prefix.
#   2) Is what came out still Node.js? The official Node.js test suite runs against the
#      executable this project links from libnode, which is a stricter claim than it running
#      against anything else.
#
# Layout, by prefix:
#
#   embedder/        the embedding executable: it links unofficial::node::node and behaves
#                    like upstream node.exe, which is what lets Node.js's own tools/test.py
#                    use it as a shell. It is also the example a consumer would copy.
#   smoke/           fast assertions about the *installed* port: Node.js identity, and which
#                    dependencies actually came from vcpkg rather than out of the vendored
#                    source tree. Seconds, so they run on every push.
#   official_suite/  Node.js's own suite through its own driver, plus its skip lists. Minutes
#                    to an hour; labelled `node-suite` so a fast run can skip it with
#                    `ctest -LE node-suite`.
#   symbols/         the symbol audit: no strong symbol defined twice in one process.
#                    Seconds; labelled `symbols` so a fast run can skip it with
#                    `ctest -LE symbols`.
#
# Each directory stands on its own - deleting any one of them leaves the others working.
# The dependency direction is exactly one way: this project consumes `../ports`.

cmake_minimum_required(VERSION 3.24)

project(node_port_test LANGUAGES CXX)

# ---------------------------------------------------------------------------
# A Debug link against a static libnode does not fit in a runner's memory with GNU ld.
#
# Measured 2026-10-22 on ubuntu-latest (7 GB), twice, at the same edge:
#
#   [11/16] Linking CXX executable embedding/coexist_consumer
#   collect2: fatal error: ld terminated with signal 9 [Killed]
#
# Signal 9 is the OOM killer, and the job then reports "the runner has received a shutdown
# signal", which reads like infrastructure and is why the first two looks at this were wrong.
# A Debug libnode.a carries gigabytes of debug information and bfd's symbol table for it is
# several times the size of the archive. lld builds the same binary in a fraction of the memory,
# and `--no-keep-memory` is bfd's own answer when lld is not installed.
#
# Debug only: a Release consumer links against a much smaller library and does not need this.
# ---------------------------------------------------------------------------
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  find_program(_node_port_lld NAMES ld.lld)
  if(_node_port_lld)
    message(STATUS
      "Debug links will use lld (${_node_port_lld}): bfd runs out of memory linking against a "
      "Debug libnode.a on a 7 GB runner")
    string(APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG " -fuse-ld=lld")
  else()
    message(STATUS
      "lld not found; Debug links get -Wl,--no-keep-memory so bfd can link against a Debug libnode.a")
    string(APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG " -Wl,--no-keep-memory")
  endif()
  unset(_node_port_lld)
endif()

# ---------------------------------------------------------------------------
# Knobs (CI overrides these with -D)
#
# Careful with docstrings: an unescaped double quote inside a set(... CACHE STRING "...")
# argument silently truncates the value into a list fragment - the CMake code stays
# perfectly valid, only the value changes, and the failure shows up far away as Node.js's
# test.py rejecting some nonsense argument. None of these legitimately contain the words
# CACHE or STRING, so check for them and fail here where it is still obvious.
# ---------------------------------------------------------------------------
option(NODE_TEST_SUITE
       "Register Node.js's own test suite as ctest cases (needs the node port's test-suite feature)"
       ON)

set(NODE_TEST_SUITES
    "parallel,sequential,message,abort,async-hooks,known_issues,module-hooks,es-module,report"
    CACHE STRING "Suites to run, comma separated, as tools/test.py names its directories")

set(NODE_TEST_SUITES_EXTRA
    ""
    CACHE STRING "Additional suites, appended to NODE_TEST_SUITES (addons, node-api, benchmarks ...)")

set(NODE_TEST_SKIP
    ""
    CACHE STRING "Extra skips for one run. Long-lived ones belong in official_suite/node-suite-skips.txt, which requires a written reason for every entry.")

set(NODE_TEST_SHARDS
    "1"
    CACHE STRING "Split each suite into N shards (test.py --run=i,N). Each shard is one ctest case with its own temporary directory.")

set(NODE_TEST_JOBS
    ""
    CACHE STRING "test.py -j. Empty lets the driver use the core count.")

set(NODE_TEST_SUITE_TIMEOUT
    "5400"
    CACHE STRING "ctest timeout per suite or shard, in seconds")

foreach(_node_var
    NODE_TEST_SUITES
    NODE_TEST_SUITES_EXTRA
    NODE_TEST_SKIP
    NODE_TEST_SHARDS
    NODE_TEST_JOBS
    NODE_TEST_SUITE_TIMEOUT)
  if("${${_node_var}}" MATCHES "CACHE|STRING")
    message(FATAL_ERROR
      "${_node_var} has the corrupted value '${${_node_var}}' - a docstring argument most "
      "likely lost its quoting. Fix the set() in test/CMakeLists.txt and clear the stale "
      "cache entry: cmake --preset <name> -D${_node_var}=<correct value>")
  endif()
endforeach()
unset(_node_var)

# Provided by the node port, together with the imported target unofficial::node::node.
find_package(unofficial-node CONFIG REQUIRED)

# Node.js's own driver is a Python program.
find_package(Python3 COMPONENTS Interpreter)

enable_testing()

# zlib, once, for every consumer in this project.
#
# vcpkg's zlib exports ZLIB::ZLIBSTATIC, and ZLIB::ZLIB only exists when the vcpkg toolchain's
# wrapper answers the lookup - so a test project that asks for the built-in name has to normalize
# it, exactly as the port's own consumer config does. Done here rather than in each
# subdirectory: imported targets are directory-scoped, so a subdirectory that did it for itself
# would not be visible to the next one.
find_package(ZLIB CONFIG REQUIRED)
if(NOT TARGET ZLIB::ZLIB AND TARGET ZLIB::ZLIBSTATIC)
  add_library(ZLIB::ZLIB INTERFACE IMPORTED)
  set_target_properties(ZLIB::ZLIB PROPERTIES INTERFACE_LINK_LIBRARIES ZLIB::ZLIBSTATIC)
endif()

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
  if(NOT DEFINED node_LIBRARY_KIND OR NOT node_LIBRARY_KIND STREQUAL "shared")
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
if(WIN32 AND DEFINED node_LIBRARY_KIND AND node_LIBRARY_KIND STREQUAL "shared"
   AND DEFINED node_EXECUTABLE AND DEFINED node_TOOLS_DIR)
  get_filename_component(_node_bin_dir "${node_SHARED_LIBRARY}" DIRECTORY)
  file(GLOB _node_tool_dlls "${_node_bin_dir}/*.dll")
  if(_node_tool_dlls)
    add_custom_target(node_tools_dlls ALL
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
              ${_node_tool_dlls} "${node_TOOLS_DIR}/"
      COMMENT "node: DLLs next to tools/node/node.exe")
  endif()
  unset(_node_tool_dlls)
  unset(_node_bin_dir)
endif()

add_subdirectory(embedder)
add_subdirectory(embedding)
add_subdirectory(smoke)
add_subdirectory(zlib)
add_subdirectory(symbols)
add_subdirectory(official_suite)

# node_test_runtime_libs is called from the directory that creates each executable, not from
# here: add_custom_command(TARGET ...) may only name a target created in the *same* directory,
# and every one of these is created in a subdirectory. Measured on windows-shared, the first leg
# that got far enough to exercise this: six errors, "TARGET 'node_embedder' was not created in
# this directory", one per executable. The Unix branch of the same function is a property and
# would have been fine from here; the Windows branch is a build command and is not.

message(STATUS "node consumer test project")
message(STATUS "  node version      : ${unofficial-node_VERSION} (from share/unofficial-node)")
message(STATUS "  CMake config dir  : ${unofficial-node_DIR}")
message(STATUS "  node executable   : ${node_EXECUTABLE}")
message(STATUS "  test suite dir    : ${node_TEST_SUITE_DIR}")
message(STATUS "  suites            : ${NODE_TEST_SUITES}")
message(STATUS "  python            : ${Python3_EXECUTABLE}")
