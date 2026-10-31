# The runtime on a thread the host owns.
#
# The interesting assertion is not that the script ran - it is that the host's own loop kept running
# while it did, which is what the tick count in the output proves. A library build that quietly owned
# the main thread would still pass "the script ran".

add_executable(thread_loop main.cpp)
target_compile_features(thread_loop PRIVATE cxx_std_20)
target_link_libraries(thread_loop PRIVATE unofficial::node::node)

find_package(Threads REQUIRED)
target_link_libraries(thread_loop PRIVATE Threads::Threads)

add_test(NAME thread-loop.ticks COMMAND thread_loop "${CMAKE_CURRENT_SOURCE_DIR}/loop.js")
set_tests_properties(thread-loop.ticks PROPERTIES
  PASS_REGULAR_EXPRESSION "host: [1-9][0-9]* ticks"
  FAIL_REGULAR_EXPRESSION "thread_loop:"
  TIMEOUT 180
  LABELS "smoke")

# Its DLLs live next to the library, not next to this executable (Windows shared only).
node_test_runtime_libs(thread_loop)
