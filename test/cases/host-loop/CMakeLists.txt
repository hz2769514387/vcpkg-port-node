# The host owns the loop and pumps it itself - the UI-toolkit arrangement.
#
# `node::SpinEventLoop` hands the loop to the runtime; a host with its own main loop drives
# `uv_run(UV_RUN_NOWAIT)` instead. The interesting assertion is that the script's timer fired *inside*
# one of the host's iterations, not before them or after them.
#
# libuv is linked explicitly here, and that is the honest form of the promise rather than a
# workaround: a consumer that *calls* one of node's dependencies has to link it, exactly as with any
# vcpkg package. With a static libnode the exported config already carries it (the archives cannot
# resolve each other on their own), so this is a no-op there; with a shared libnode the dependency is
# a separate .dylib/.so/DLL, and neither macOS's two-level namespace nor Windows resolves a symbol
# through a library's own dependency - the dylib only has to be findable at run time, which libnode's
# rpath already guarantees. Measured: without this line, the case failed on arm64-osx-dynamic with
# "Undefined symbols for architecture arm64: _uv_run, _uv_sleep".

find_package(libuv CONFIG REQUIRED)
find_package(Threads REQUIRED)

add_executable(host_loop main.cpp)
target_compile_features(host_loop PRIVATE cxx_std_20)
target_link_libraries(host_loop PRIVATE unofficial::node::node
  $<IF:$<TARGET_EXISTS:libuv::uv_a>,libuv::uv_a,libuv::uv>
  Threads::Threads)

add_test(NAME host-loop.pumped COMMAND host_loop "${CMAKE_CURRENT_SOURCE_DIR}/host_loop.js")
set_tests_properties(host-loop.pumped PROPERTIES
  PASS_REGULAR_EXPRESSION "host: timer fired in host iteration [0-9]+ of"
  FAIL_REGULAR_EXPRESSION "host_loop:|host: timer never fired|host: timer fired at iteration"
  TIMEOUT 180
  LABELS "smoke")

# Its DLLs live next to the library, not next to this executable (Windows shared only).
node_test_runtime_libs(host_loop)
