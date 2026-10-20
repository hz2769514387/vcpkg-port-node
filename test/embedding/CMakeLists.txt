# What embedding has to support, beyond "it links".
#
# Every case here runs the embedding executable built in embedder/, so what is under test
# is the consumer-linked runtime, not the port's own node.exe. The scenarios are the
# questions consumers actually ask once the hello world works: does the host see Node.js's
# exit semantics, is worker_threads complete inside an embedded runtime, can the runtime
# spawn a child, and can one process link the port next to the very libraries the port
# externalized.

set(_embedding "${CMAKE_CURRENT_SOURCE_DIR}")

# --- exit code semantics ------------------------------------------------------
# ctest compares a test's exit code with zero, which cannot express "this program is
# supposed to exit with 7", so a small driver script does the comparing instead.
add_test(NAME embedding.exit.ok
  COMMAND "${CMAKE_COMMAND}"
    -DEXE=$<TARGET_FILE:node_embedder>
    -DSCRIPT=${_embedding}/exit_ok.js
    -DEXPECT=0
    -P "${_embedding}/check_exit.cmake")
add_test(NAME embedding.exit.code7
  COMMAND "${CMAKE_COMMAND}"
    -DEXE=$<TARGET_FILE:node_embedder>
    -DSCRIPT=${_embedding}/exit_code7.js
    -DEXPECT=7
    -P "${_embedding}/check_exit.cmake")
add_test(NAME embedding.exit.uncaught
  COMMAND "${CMAKE_COMMAND}"
    -DEXE=$<TARGET_FILE:node_embedder>
    -DSCRIPT=${_embedding}/exit_uncaught.js
    -DEXPECT=1
    -P "${_embedding}/check_exit.cmake")
set_tests_properties(
  embedding.exit.ok
  embedding.exit.code7
  embedding.exit.uncaught
  PROPERTIES TIMEOUT 120 LABELS "smoke")

# --- runtime features ---------------------------------------------------------
add_test(NAME embedding.workers COMMAND node_embedder "${_embedding}/workers.js")
set_tests_properties(embedding.workers PROPERTIES TIMEOUT 180 LABELS "smoke")

add_test(NAME embedding.spawn_child COMMAND node_embedder "${_embedding}/spawn_child.js")
set_tests_properties(embedding.spawn_child PROPERTIES TIMEOUT 180 LABELS "smoke")

# --- one process, both sides of the same libraries ----------------------------
# Declared as ordinary vcpkg dependencies in test/vcpkg.json, next to node: the point is
# that they coexist with the port in one consumer, not that they are used in isolation.
find_package(absl CONFIG REQUIRED)
find_package(hwy CONFIG REQUIRED)
find_package(simdutf CONFIG REQUIRED)
find_package(OpenSSL REQUIRED)
# ZLIB::ZLIB is normalized in the project's top-level CMakeLists, for every consumer at once.

add_executable(coexist_consumer coexist_main.cpp)
target_link_libraries(coexist_consumer PRIVATE
  unofficial::node::node
  absl::strings
  hwy::hwy
  simdutf::simdutf
  OpenSSL::Crypto
  ZLIB::ZLIB)
target_compile_features(coexist_consumer PRIVATE cxx_std_20)

add_test(NAME embedding.coexist
  COMMAND coexist_consumer "${_embedding}/exit_ok.js")
set_tests_properties(embedding.coexist PROPERTIES TIMEOUT 180 LABELS "smoke")

# --- a library that hides the port, and two applications on top of it -----------
add_subdirectory(layered)

add_test(NAME embedding.layered.app COMMAND layered_app "${_embedding}/exit_ok.js")
add_test(NAME embedding.layered.cli COMMAND layered_cli "${_embedding}/exit_ok.js")
set_tests_properties(
  embedding.layered.app
  embedding.layered.cli
  PROPERTIES TIMEOUT 180 LABELS "smoke")

# --- the runtime on a thread the host owns -------------------------------------
# The interesting assertion is not that the script ran - it is that the host's own loop kept
# running while it did, which is what the tick count in the output proves.
add_executable(thread_loop thread_loop/main.cpp)
target_compile_features(thread_loop PRIVATE cxx_std_20)
target_link_libraries(thread_loop PRIVATE unofficial::node::node)

find_package(Threads REQUIRED)
target_link_libraries(thread_loop PRIVATE Threads::Threads)

add_test(NAME embedding.thread_loop
  COMMAND thread_loop "${_embedding}/thread_loop/loop.js")
set_tests_properties(embedding.thread_loop PROPERTIES
  PASS_REGULAR_EXPRESSION "host: [1-9][0-9]* ticks"
  FAIL_REGULAR_EXPRESSION "thread_loop:"
  TIMEOUT 180
  LABELS "smoke")

# --- the host owns the loop and pumps it itself --------------------------------
# The UI-toolkit arrangement: node::SpinEventLoop hands the loop to the runtime, so a host
# with its own main loop drives uv_run(UV_RUN_NOWAIT) instead. The interesting assertion is
# that the script's timer fired *inside* one of the host's iterations.
#
# libuv is linked explicitly here, and that is the honest form of the promise rather than a
# workaround: a consumer that *calls* one of node's dependencies has to link it, exactly as
# with any vcpkg package. With a static libnode the exported config already carries it (the
# archives cannot resolve each other on their own), so this is a no-op there; with a shared
# libnode the dependency is a separate .dylib/.so/DLL, and neither macOS's two-level
# namespace nor Windows resolves a symbol through a library's own dependency - the dylib
# only has to be findable at run time, which libnode's rpath already guarantees. Measured:
# without this line, embedding.host_loop failed on arm64-osx-dynamic with
# "Undefined symbols for architecture arm64: _uv_run, _uv_sleep".
find_package(libuv CONFIG REQUIRED)
add_executable(host_loop host_loop/main.cpp)
target_compile_features(host_loop PRIVATE cxx_std_20)
target_link_libraries(host_loop PRIVATE unofficial::node::node
  $<IF:$<TARGET_EXISTS:libuv::uv_a>,libuv::uv_a,libuv::uv>
  Threads::Threads)

add_test(NAME embedding.host_loop
  COMMAND host_loop "${_embedding}/host_loop/host_loop.js")
set_tests_properties(embedding.host_loop PROPERTIES
  PASS_REGULAR_EXPRESSION "host: timer fired in host iteration [0-9]+ of"
  FAIL_REGULAR_EXPRESSION "host_loop:|host: timer never fired|host: timer fired at iteration"
  TIMEOUT 180
  LABELS "smoke")
