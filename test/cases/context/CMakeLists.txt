# Request-scoped state and instrumentation, carried across asynchronous boundaries.
#
# A server that embeds Node.js almost always needs to know which request the code running
# "right now" belongs to: a log line, a database hint, a permission check. AsyncLocalStorage
# is what carries that through await, timers, promises, emitters and microtasks, and it is
# implemented with async_hooks, whose per-isolate bookkeeping a library build can break
# without any visible symptom until two requests start sharing a tenant.
#
# diagnostics_channel is the other half: the hooks a product's observability layer subscribes
# to. Neither is visible in the official suite's default run, and neither is exercised by
# "the script printed a line".
#
# The worker case checks the same thing across a second isolate: two workers under one process
# each keep their own store, which is what a worker pool per request depends on.

add_test(NAME context.async_local_storage
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/context.mjs")
set_tests_properties(context.async_local_storage PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  PASS_REGULAR_EXPRESSION "context: async local storage and diagnostics ok"
  FAIL_REGULAR_EXPRESSION "context_error:"
  TIMEOUT 180
  LABELS "smoke")

add_test(NAME context.in_workers
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/worker_context_main.mjs")
set_tests_properties(context.in_workers PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  PASS_REGULAR_EXPRESSION "context: per-worker stores ok"
  FAIL_REGULAR_EXPRESSION "context_error:"
  TIMEOUT 300
  LABELS "smoke")
