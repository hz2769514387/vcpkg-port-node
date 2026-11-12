# The runtime can be started, stopped and started again inside one host process.
#
# A service that loads scripts on demand, or a plugin host that tears a sandbox down when a
# request ends, does this repeatedly. It is a different path from node::Start and from the
# thread-loop example: global state in V8, OpenSSL, ICU and libuv has to survive the second
# Initialize, and the environment's own cleanup and AtExit hooks have to run exactly once
# for the environment they belong to - not zero times, not once for the whole process.
#
# The host keeps the V8 platform up across all three environments, which is the arrangement
# Node.js's embedding documentation describes.

add_executable(lifecycle main.cpp)
target_compile_features(lifecycle PRIVATE cxx_std_20)
target_link_libraries(lifecycle PRIVATE unofficial::node::node)

add_test(NAME lifecycle.three_environments
         COMMAND lifecycle "${CMAKE_CURRENT_SOURCE_DIR}/round.cjs")
set_tests_properties(lifecycle.three_environments PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  PASS_REGULAR_EXPRESSION "lifecycle: 3 environments, 3 cleanup hooks, 3 at-exit hooks"
  FAIL_REGULAR_EXPRESSION "lifecycle_error:"
  TIMEOUT 300
  LABELS "smoke")

node_test_runtime_libs(lifecycle)
