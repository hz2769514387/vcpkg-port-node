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
#   official_suite/  Node.js's own suite through its own driver. Minutes to an hour; labelled
#                    `node-suite` so a fast run can skip it with `ctest -LE node-suite`.
#   cmake/           shared CMake helpers: the suite driver and its skip lists.
#
# Each directory stands on its own - deleting any one of them leaves the others working.
# The dependency direction is exactly one way: this project consumes `../ports`.

cmake_minimum_required(VERSION 3.24)

project(node_port_test LANGUAGES CXX)

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
    CACHE STRING "Extra skips for one run. Long-lived ones belong in cmake/node-suite-skips.txt, which requires a written reason for every entry.")

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

add_subdirectory(embedder)
add_subdirectory(embedding)
add_subdirectory(smoke)
add_subdirectory(zlib)
add_subdirectory(official_suite)

message(STATUS "node consumer test project")
message(STATUS "  node version      : ${unofficial-node_VERSION} (from share/unofficial-node)")
message(STATUS "  CMake config dir  : ${unofficial-node_DIR}")
message(STATUS "  node executable   : ${node_EXECUTABLE}")
message(STATUS "  test suite dir    : ${node_TEST_SUITE_DIR}")
message(STATUS "  suites            : ${NODE_TEST_SUITES}")
message(STATUS "  python            : ${Python3_EXECUTABLE}")
