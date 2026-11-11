# Two Node.js environments alive at the same time in one process.
#
# A multi-tenant plugin host or a server that gives each request its own isolate needs this,
# and it is not the same claim as cases/lifecycle (environments one after another) or
# cases/host-loop (one environment pumped by the host). Here the host owns both loops and
# alternates between them; a build whose isolates share a global, or whose second loop is
# never serviced, fails.
#
# libuv is linked explicitly for the same reason as cases/host-loop: a consumer that calls
# uv_run() links the library it calls, and with a shared libnode the exported config does
# not put it on the consumer's link line.

find_package(libuv CONFIG REQUIRED)
find_package(Threads REQUIRED)

add_executable(multi_isolate main.cpp)
target_compile_features(multi_isolate PRIVATE cxx_std_20)
target_link_libraries(multi_isolate PRIVATE unofficial::node::node
  $<IF:$<TARGET_EXISTS:libuv::uv_a>,libuv::uv_a,libuv::uv>
  Threads::Threads)

add_test(NAME multi-isolate.two_contexts_pumped_by_the_host
         COMMAND multi_isolate "${CMAKE_CURRENT_SOURCE_DIR}/isolate.cjs")
set_tests_properties(multi-isolate.two_contexts_pumped_by_the_host PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  PASS_REGULAR_EXPRESSION "multi-isolate: 2 isolates, 2 loops, both pumped"
  FAIL_REGULAR_EXPRESSION "multi_isolate_error:"
  TIMEOUT 300
  LABELS "smoke")

node_test_runtime_libs(multi_isolate)
