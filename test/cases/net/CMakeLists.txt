# Local-network paths through the externalized dependencies.
#
# A service that embeds Node.js almost always serves or calls something. HTTP/1.1 goes
# through llhttp, HTTP/2 through nghttp2, fetch through undici on top of http, URL parsing
# through ada, DNS through c-ares/libuv, and sockets through that same libuv loop. All of
# them are separate vcpkg ports in this install, so "it links" says very little about
# whether a request completes.
#
# Everything binds to 127.0.0.1 on an ephemeral port. No test here reaches a network
# outside the process, and every server is closed in a finally block so a failed assertion
# does not turn into a ctest timeout.

add_test(NAME net.loopback_stack
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/net.mjs")
set_tests_properties(net.loopback_stack PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  TIMEOUT 300
  LABELS "smoke")
