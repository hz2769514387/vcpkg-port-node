# The two ways a product scales beyond one JavaScript thread.
#
# worker_threads needs a second isolate, a second event loop and the startup snapshot in a
# thread the host did not create; child_process needs process.execPath to name the embedding
# executable and an IPC channel that survives a fork. cases/embed runs one worker and one
# spawn; this case runs a pool, shares memory across it, and round-trips messages through
# both mechanisms.
#
# These are the paths that silently break when a library build loses a host tool, changes
# how argv is passed, or links a second copy of libuv.

add_test(NAME workers.pool
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/workers.mjs")
set_tests_properties(workers.pool PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  TIMEOUT 300
  LABELS "smoke")

add_test(NAME workers.child_process_ipc
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/ipc.mjs")
set_tests_properties(workers.child_process_ipc PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  TIMEOUT 300
  LABELS "smoke")
