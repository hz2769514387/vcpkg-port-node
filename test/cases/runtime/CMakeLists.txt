# V8-level behaviour a host reaches from C++ and JavaScript alike.
#
# The embedder has to bring up V8's platform, its allocator and the startup snapshot, not
# just node::Start. These assertions cover the parts that "the script printed a line" cannot
# see: heap statistics and explicit GC, a second V8 context with a timeout, WebAssembly
# compilation, structured cloning, shared buffer memory and the microtask ordering a host's
# own callbacks rely on.

add_test(NAME runtime.v8_surface
         COMMAND node_embedder --expose-gc "${CMAKE_CURRENT_SOURCE_DIR}/runtime.mjs")
set_tests_properties(runtime.v8_surface PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  TIMEOUT 180
  LABELS "smoke")
