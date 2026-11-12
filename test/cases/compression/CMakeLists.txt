# Four compression libraries reach Node.js through three different ports: zlib (the
# Chromium fork overlay), brotli and zstd. cases/zlib proves one copy of zlib is shared
# between the host and the runtime; this case proves the runtime's own APIs still work.
#
# Both the synchronous and the streaming forms are used, because they are different code
# paths inside Node.js and a port that only wired the C API up would pass one and not the
# other.

add_test(NAME compression.round_trips
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/compression.mjs")
set_tests_properties(compression.round_trips PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  TIMEOUT 180
  LABELS "smoke")
