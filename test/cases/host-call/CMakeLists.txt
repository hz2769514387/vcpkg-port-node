# The host calls into JavaScript after the environment is up, and the I/O that call starts has to
# reach the loop the host is pumping.
#
# A host does this for everything it runs on demand - one request handler, one plugin hook, one
# module reload - and that call does not pass through Node.js's own execution path the way a
# script does. nodejs/node#48760 reported that a fetch/net started from v8::Function::Call after
# LoadEnvironment never reached the loop (`uv_loop_alive` was immediately 0), which would make
# "call a JS function from C++" unusable for anything asynchronous. This case measures the
# current behaviour rather than trusting that report: one connection is started by the script
# itself and one from a v8::Function::Call made by the host afterwards, and both have to
# complete on the same loop.
#
# It asserts on the effect (both connections finished), not on uv_loop_alive or handle counts: a
# build that queues the work and never runs it fails here, so a regression of #48760 becomes a
# red case instead of a product that hangs. Measured on the pinned 26.13.x tree: all four events
# arrive; the issue does not reproduce.

add_executable(host_call main.cpp)
target_compile_features(host_call PRIVATE cxx_std_20)
target_link_libraries(host_call PRIVATE unofficial::node::node)

add_test(NAME host-call.io_from_a_host_call COMMAND host_call)
set_tests_properties(host-call.io_from_a_host_call PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  FAIL_REGULAR_EXPRESSION "host_call: missing|host_call: LoadEnvironment failed"
  TIMEOUT 120
  LABELS "smoke")

node_test_runtime_libs(host_call)
