# A native thread outside the runtime has to be able to wake Node.js's event loop.
#
# This is the arrangement a device driver, a telemetry thread or a host's own I/O uses: it
# cannot call into JavaScript from its thread, so it signals a uv_async_t that lives on the
# loop Node.js created. It only works if the libuv the consumer links is the same libuv as
# the one inside the runtime - which is the reason this port externalizes dependencies in
# the first place. cases/host-loop proves the host can pump that loop; this case proves the
# host can cross into it from another thread.

find_package(libuv CONFIG REQUIRED)
find_package(Threads REQUIRED)

add_executable(loop_wakeup main.cpp)
target_compile_features(loop_wakeup PRIVATE cxx_std_20)
target_link_libraries(loop_wakeup PRIVATE unofficial::node::node
  $<IF:$<TARGET_EXISTS:libuv::uv_a>,libuv::uv_a,libuv::uv>
  Threads::Threads)

add_test(NAME loop-wakeup.native_thread_signals_node_loop
         COMMAND loop_wakeup "${CMAKE_CURRENT_SOURCE_DIR}/wakeup.cjs")
set_tests_properties(loop-wakeup.native_thread_signals_node_loop PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  PASS_REGULAR_EXPRESSION "loop-wakeup: native wakeup and JS timer both ran on node's loop"
  FAIL_REGULAR_EXPRESSION "loop_wakeup_error:"
  TIMEOUT 300
  LABELS "smoke")

node_test_runtime_libs(loop_wakeup)
