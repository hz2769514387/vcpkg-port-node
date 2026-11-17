# The embedder snapshot API, which no other case reaches.
#
# `cases/snapshot` asserts the *built-in* snapshot artefact (node_use_node_snapshot) through
# process.config. This case is the API half: CreateForSnapshotting -> LoadEnvironment ->
# CreateSnapshot -> ToBlob, then FromBlob -> CreateFromSnapshot, with a value the builder script
# assigned to a global. A product uses it to move its own bootstrap JavaScript out of startup.
#
# Two ctest cases because Node.js requires every setup in one process to use the same snapshot,
# so the build and the consume cannot share a process. `DEPENDS` keeps the order even under
# `ctest -j`. The blob is written into the build directory, not the source tree.

add_executable(embedder_snapshot main.cpp)
target_compile_features(embedder_snapshot PRIVATE cxx_std_20)
target_link_libraries(embedder_snapshot PRIVATE unofficial::node::node)

set(_snapshot_blob "${CMAKE_CURRENT_BINARY_DIR}/embedder-snapshot.blob")

add_test(NAME embedder-snapshot.build
         COMMAND embedder_snapshot build "${_snapshot_blob}")
set_tests_properties(embedder-snapshot.build PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  FAIL_REGULAR_EXPRESSION "embedder_snapshot_error:"
  TIMEOUT 300
  LABELS "smoke")

add_test(NAME embedder-snapshot.consume
         COMMAND embedder_snapshot consume "${_snapshot_blob}")
set_tests_properties(embedder-snapshot.consume PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  FAIL_REGULAR_EXPRESSION "embedder_snapshot_error:"
  DEPENDS embedder-snapshot.build
  TIMEOUT 300
  LABELS "smoke")

node_test_runtime_libs(embedder_snapshot)
