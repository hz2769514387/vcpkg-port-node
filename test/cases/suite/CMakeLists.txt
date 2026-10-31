# Node.js's own test suite, registered as ctest cases.
#
# This directory is the whole of the official-suite test: the registration below and the
# skip lists it reads (node-suite-skips.txt, node-suite-skips-symlink.txt) live together,
# because they are one decision - which upstream cases this build runs and which it is
# entitled to leave out - and splitting them across directories hid that.
#
# Why the official driver instead of `node --test`: every test directory carries a *.status
# file where upstream records its own SKIP and FLAKY verdicts, and only tools/test.py reads
# them. Ignoring them turns dozens of upstream-tagged cases into failures, and that noise is
# exactly what hides the one failure that is actually ours.
#
# Why one driver process per ctest case: test/common/tmpdir.js names its temporary directories
# .tmp.${TEST_SERIAL_ID}, and those ids restart at zero in every driver process. Two
# concurrent driver processes then share one .tmp.1 and delete each other's fixtures, which
# shows up as unrelated ENOENT failures. ctest runs tests sequentially unless it is given
# -j, which is why the default here is safe. Sharding is available when wall-clock time
# matters, and each shard gets its own --temp-dir (NODE_TEST_DIR) for exactly this reason.
#
# The shell is our own embedding executable, not the port's node.exe: an embedding runtime
# that can run Node.js's own tests is a much stronger claim than the reverse. If that target
# goes away, this falls back to the port's executable rather than disappearing silently.

if(NOT NODE_TEST_SUITE)
  message(STATUS "Node.js test suite: disabled (-DNODE_TEST_SUITE=OFF)")
  return()
endif()

if(NOT node_TEST_SUITE_DIR)
  message(WARNING
    "Node.js test suite directory not found. Enable the node port's test-suite feature "
    "(see test/vcpkg.json), or no official suite cases will be registered.")
  return()
endif()

if(NOT Python3_Interpreter_FOUND)
  message(WARNING
    "No Python 3 interpreter: Node.js's own driver is a Python program, so the official "
    "suite cannot be registered.")
  return()
endif()

set(_suite_runner "${node_TEST_SUITE_DIR}/tools/test.py")
set(_suite_root "${node_TEST_SUITE_DIR}/test")
if(NOT EXISTS "${_suite_runner}" OR NOT IS_DIRECTORY "${_suite_root}")
  message(WARNING "Node.js test suite is incomplete at ${node_TEST_SUITE_DIR}; skipping.")
  return()
endif()

# ---------------------------------------------------------------------------
# Red line, checked at configure time: fixture scripts that ship with the executable bit
# must still have it after installation.
#
# CMake's file(INSTALL) writes files as 0644 unless USE_SOURCE_PERMISSIONS is given (the
# "defaults to source permissions" sentence in the documentation is about file(COPY)), so
# the bits can be lost in the port without anyone noticing. The suite invokes
# test/fixtures/run-script/node_modules/.bin/* through `node --run <script>`, so a missing
# bit fails as an empty subprocess stdout with the real error buried in child.stderr - which
# reads as six unrelated failures in test-node-run. Windows is unaffected (it uses .bat), so
# this only bites on Unix.
# ---------------------------------------------------------------------------
if(UNIX)
  file(GLOB _fixture_bins "${_suite_root}/fixtures/run-script/node_modules/.bin/*")
  foreach(_fixture IN LISTS _fixture_bins)
    if(_fixture MATCHES "[.]bat$")
      continue()
    endif()
    execute_process(COMMAND test -x "${_fixture}" RESULT_VARIABLE _executable)
    if(NOT _executable EQUAL 0)
      message(FATAL_ERROR
        "Node.js test suite fixture lost its executable bit: ${_fixture}\n"
        "Add USE_SOURCE_PERMISSIONS to the file(INSTALL) calls that install the test-suite "
        "feature in ports/node/portfile.cmake.")
    endif()
  endforeach()
  unset(_fixture_bins)
  unset(_executable)
endif()

if(TARGET node_embedder)
  set(_suite_shell "$<TARGET_FILE:node_embedder>")
  set(_suite_shell_kind "consumer embedding executable")
elseif(DEFINED node_EXECUTABLE AND EXISTS "${node_EXECUTABLE}")
  set(_suite_shell "${node_EXECUTABLE}")
  set(_suite_shell_kind "port tools feature")
else()
  message(WARNING
    "Neither the embedding target nor the port's node executable is available, so there is "
    "no shell for the official suite. Skipping registration.")
  return()
endif()

# ---------------------------------------------------------------------------
# Skip lists.
#
# Format: <test name> | <platform> | <reason>, one per line; '#' starts a comment.
# Platform is all / windows / linux / macos, optionally suffixed with -<arch> to narrow it to
# one target architecture. An entry with no reason is rejected outright: a skip nobody can
# explain is a bug waiting to be forgotten, so it must fail here rather than at runtime.
#
# Anything already marked SKIP or FLAKY in upstream's own *.status files must NOT be listed
# here - the driver handles those, and duplicating them hides changes upstream makes.
# ---------------------------------------------------------------------------
if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
  set(_suite_os "windows")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  set(_suite_os "macos")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  set(_suite_os "linux")
else()
  set(_suite_os "unknown")
endif()

# Target architecture is taken from the triplet, never from CMAKE_SYSTEM_PROCESSOR: x64-osx
# on an arm64 host runs through Rosetta and reports arm64, which would make the -x64 and
# -arm64 selectors mean the opposite of what they say.
set(_suite_arch "")
if(DEFINED VCPKG_TARGET_TRIPLET AND NOT VCPKG_TARGET_TRIPLET STREQUAL "")
  string(REGEX MATCH "^[^-]+" _suite_arch "${VCPKG_TARGET_TRIPLET}")
endif()

function(_node_suite_platform_matches _selector _out)
  set(_match FALSE)
  if(_selector STREQUAL "all")
    set(_match TRUE)
  elseif(_selector MATCHES "^([a-z]+)-([A-Za-z0-9_]+)$")
    if(CMAKE_MATCH_1 STREQUAL _suite_os AND CMAKE_MATCH_2 STREQUAL _suite_arch)
      set(_match TRUE)
    endif()
  elseif(_selector STREQUAL _suite_os)
    set(_match TRUE)
  endif()
  # Unknown platform or architecture names simply never match - that fails in the safe
  # direction: the test runs and reports instead of being quietly skipped.
  set(${_out} ${_match} PARENT_SCOPE)
endfunction()

function(_node_suite_read_skips _file _out)
  set(_collected "")
  if(NOT EXISTS "${_file}")
    message(WARNING "skip list not found: ${_file}")
    set(${_out} "" PARENT_SCOPE)
    return()
  endif()
  file(STRINGS "${_file}" _lines)
  foreach(_line IN LISTS _lines)
    if(_line MATCHES "^[ \t]*#")
      continue()
    endif()
    if(_line MATCHES "^[ \t]*$")
      continue()
    endif()
    string(REPLACE "|" ";" _fields "${_line}")
    list(LENGTH _fields _count)
    if(_count LESS 3)
      message(FATAL_ERROR
        "malformed line in ${_file}: '${_line}'\n"
        "Expected: <test name> | <platform> | <reason>")
    endif()
    list(GET _fields 0 _name)
    list(GET _fields 1 _selector)
    list(GET _fields 2 _reason)
    string(STRIP "${_name}" _name)
    string(STRIP "${_selector}" _selector)
    string(STRIP "${_reason}" _reason)
    if(_reason STREQUAL "")
      message(FATAL_ERROR
        "skip entry '${_name}' in ${_file} has no reason. Every skip needs one sentence "
        "about why it applies, or it becomes permanent without anyone knowing what it was "
        "supposed to cover.")
    endif()
    _node_suite_platform_matches("${_selector}" _applies)
    if(_applies)
      list(APPEND _collected "${_name}")
    endif()
  endforeach()
  set(${_out} "${_collected}" PARENT_SCOPE)
endfunction()

set(_skips "")
_node_suite_read_skips("${CMAKE_CURRENT_LIST_DIR}/node-suite-skips.txt" _from_file)
list(APPEND _skips ${_from_file})

# Symlinks are a machine capability, not a platform property: they work for developers with
# Developer Mode enabled and in most CI images, and fail with EPERM everywhere else. Probe
# it instead of guessing, so the 28 fs.$symlink cases are only skipped where they cannot run.
execute_process(
  COMMAND "${Python3_EXECUTABLE}" -c
          "import os, tempfile; d = tempfile.mkdtemp(); os.symlink(d, d + '/probe')"
  RESULT_VARIABLE _symlink_result
  OUTPUT_QUIET
  ERROR_QUIET)
if(_symlink_result EQUAL 0)
  message(STATUS "Node.js test suite: symlinks available, not applying deprecation skips")
else()
  _node_suite_read_skips("${CMAKE_CURRENT_LIST_DIR}/node-suite-skips-symlink.txt" _from_file)
  list(LENGTH _from_file _count)
  message(STATUS
    "Node.js test suite: symlink creation is unavailable here, skipping ${_count} cases that "
    "cannot pass without it (see cases/suite/node-suite-skips-symlink.txt)")
  list(APPEND _skips ${_from_file})
endif()

if(NODE_TEST_SKIP)
  string(REPLACE "," ";" _extra "${NODE_TEST_SKIP}")
  list(APPEND _skips ${_extra})
endif()

# A shared libnode changes what "the binary" means to a stack trace, and one case asserts
# exactly that. abort/test-abort-backtrace requires some frame of the native trace to name
# the executable, which holds when node's code is linked into the executable - a static
# libnode. With a shared one every node frame is attributed to libnode.<module>.dylib /
# .so, so the trace is complete and symbolised but the assertion cannot hold. Measured on
# arm64-osx-dynamic (run 39424273491). This is a property of the linkage, not of the
# platform, so it is decided here rather than in a per-platform skip list.
if(node_LIBRARY_LINKAGE STREQUAL "dynamic")
  message(STATUS
    "Node.js test suite: shared libnode, skipping test-abort-backtrace (the native trace "
    "attributes node frames to the library, and the case requires the executable name)")
  list(APPEND _skips "test-abort-backtrace")

  # Two cases copy the running executable somewhere else and run it there. That only works for a
  # self-contained binary: this project's shell needs libnode next to it, exactly as any consumer
  # of a shared libnode does, and no copy of one file carries those. Measured on windows-shared
  # (run 39954561931), where both fail for that reason and pass on every static cell.
  message(STATUS
    "Node.js test suite: shared libnode, skipping test-child-process-fork-exec-path and "
    "test-module-loading-globalpaths (both copy the executable elsewhere and run it; a shared "
    "libnode is not relocatable as a single file)")
  list(APPEND _skips "test-child-process-fork-exec-path")
  list(APPEND _skips "test-module-loading-globalpaths")
endif()

# sequential/test-watch-mode.mjs is intermittent on the x64-osx **shared** cell and passes on the
# same architecture's static cell and on every other cell: runs 40025248617, 40063985432 and
# 40130285788 failed it, and re-running 40063985432's leg passed it. File-system events, a shared
# libnode and an x64 binary under Rosetta is the environment rather than this port; issue #28 holds
# the data and the criterion ("two failures in five rounds") this skip is standing on. Linkage and
# architecture are both part of the reason, which the per-platform list cannot express.
if(node_LIBRARY_LINKAGE STREQUAL "dynamic" AND APPLE AND
   CMAKE_OSX_ARCHITECTURES MATCHES "x86_64")
  message(STATUS
    "Node.js test suite: shared libnode on x64 macOS, skipping test-watch-mode (intermittent; "
    "issue #28)")
  list(APPEND _skips "test-watch-mode")
endif()

list(REMOVE_DUPLICATES _skips)
list(JOIN _skips "," _skips_csv)

# ---------------------------------------------------------------------------
# Registration: one ctest case per suite (times NODE_TEST_SHARDS).
# ---------------------------------------------------------------------------
string(REPLACE "," ";" _suites "${NODE_TEST_SUITES}")
if(NODE_TEST_SUITES_EXTRA)
  string(REPLACE "," ";" _extra_suites "${NODE_TEST_SUITES_EXTRA}")
  list(APPEND _suites ${_extra_suites})
endif()
list(REMOVE_DUPLICATES _suites)

if(NOT NODE_TEST_SHARDS MATCHES "^[1-9][0-9]*$")
  message(FATAL_ERROR
    "NODE_TEST_SHARDS must be a positive integer, got '${NODE_TEST_SHARDS}'. Zero would "
    "silently register no tests at all, which looks identical to everything passing.")
endif()

set(_suite_args_base
    "${_suite_runner}"
    "--shell=${_suite_shell}"
    "--test-root=${_suite_root}"
    "--time"
    # Examples upstream marks as flaky still run, and no failure of theirs turns this red:
    # we are not Node.js CI and cannot tell an upstream flake from our own build.
    "--flaky-tests=dontcare")
if(NODE_TEST_JOBS)
  list(APPEND _suite_args_base "-j" "${NODE_TEST_JOBS}")
endif()
if(_skips_csv)
  list(APPEND _suite_args_base "--skip-tests=${_skips_csv}")
endif()

foreach(_suite IN LISTS _suites)
  string(STRIP "${_suite}" _suite)
  if(_suite STREQUAL "")
    continue()
  endif()
  if(NOT IS_DIRECTORY "${_suite_root}/${_suite}")
    # Failing loudly is deliberate: a suite name that upstream renamed would otherwise
    # silently mean "nothing was run", which is indistinguishable from "everything passed".
    message(FATAL_ERROR
      "requested Node.js test suite '${_suite}' does not exist under ${_suite_root}. "
      "Either it was renamed upstream or the name in NODE_TEST_SUITES is wrong.")
  endif()

  math(EXPR _shard_count "${NODE_TEST_SHARDS}")
  foreach(_index RANGE 1 ${_shard_count})
    if(_shard_count GREATER 1)
      set(_test_name "node-suite.${_suite}.${_index}of${_shard_count}")
      set(_shard_args "--run=${_index},${_shard_count}"
                      "--temp-dir=${CMAKE_BINARY_DIR}/node-suite-tmp/${_suite}-${_index}")
    else()
      set(_test_name "node-suite.${_suite}")
      set(_shard_args "")
    endif()

    add_test(NAME "${_test_name}"
             COMMAND "${Python3_EXECUTABLE}" ${_suite_args_base} ${_shard_args} "${_suite}")
    set_tests_properties("${_test_name}" PROPERTIES
      TIMEOUT "${NODE_TEST_SUITE_TIMEOUT}"
      LABELS "node-suite"
      ENVIRONMENT "NODE_TEST_KNOWN_SHELL=${_suite_shell_kind}"
      # The working directory has to be the suite root, not ctest's default of
      # this binary directory. The driver hands the shell
      # `--test-reporter=./test/common/test-error-reporter.js`, which is
      # relative, so it is resolved against whatever the process was started
      # in: left alone, every case that uses the reporter dies with
      # ERR_MODULE_NOT_FOUND pointing at <build dir>/cases/suite/test/...,
      # a path that exists nowhere. The suite's own files are found through
      # --test-root either way, which is why only some cases failed and the
      # rest passed - the misleading half of the symptom.
      WORKING_DIRECTORY "${node_TEST_SUITE_DIR}")
  endforeach()
endforeach()

message(STATUS "Node.js test suite: ${_suite_shell_kind}")
message(STATUS "  platform label    : ${_suite_os}-${_suite_arch}")
message(STATUS "  suites            : ${_suites}")
message(STATUS "  shards            : ${NODE_TEST_SHARDS}")
message(STATUS "  skip count        : ${_skips_csv}")
