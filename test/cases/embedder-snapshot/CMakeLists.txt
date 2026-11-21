# The embedder snapshot API, which no other case reaches.
#
# `cases/snapshot` asserts the *built-in* snapshot artefact (node_use_node_snapshot) through
# process.config. This case is the API half: CreateForSnapshotting -> LoadEnvironment ->
# CreateSnapshot -> ToBlob, then FromBlob -> CreateFromSnapshot, with a value the builder script
# assigned to a global. A product uses it to move its own bootstrap JavaScript out of startup.
#
# Two ctest cases because Node.js requires every setup in one process to use the same snapshot,
# so the build and the consume cannot share a process. Fixtures express both order and success:
# `DEPENDS` alone orders tests but ignores the setup test's result, which would let consume pass on
# an older blob left in a reused build tree. The build stage removes the old blob first, so a setup
# that did not run leaves consume with nothing to read. The blob lives in the build directory.

# Windows + shared has no coverage here, on purpose. `EmbedderSnapshotData` is declared without
# NODE_EXTERN (unlike `class NODE_EXTERN CommonEnvironmentSetup`), so node.exe does not export it;
# tools/gen_node_def.cc builds libnode.dll's export list from node.exe's export table, so
# FromBlob/ToBlob/DeleteSnapshotData do not exist in the DLL. Measured on windows-shared and
# windows-shared-arm64: lld-link "undefined symbol ... EmbedderSnapshotData::FromBlob". The static
# Windows cells and every POSIX shared cell still cover the API - POSIX shared objects export
# everything by default, which is why only the Windows DLL cells fail.
if(WIN32 AND NODE_PORT_SHARED)
  message(STATUS
    "Embedder snapshot API: not exported by libnode.dll on Windows (EmbedderSnapshotData has no "
    "NODE_EXTERN); not registering cases/embedder-snapshot on this cell")
  return()
endif()

add_executable(embedder_snapshot main.cpp)
target_compile_features(embedder_snapshot PRIVATE cxx_std_20)
target_link_libraries(embedder_snapshot PRIVATE unofficial::node::node)

set(_snapshot_blob "${CMAKE_CURRENT_BINARY_DIR}/embedder-snapshot.blob")

add_test(NAME embedder-snapshot.build
         COMMAND embedder_snapshot build "${_snapshot_blob}")
set_tests_properties(embedder-snapshot.build PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  FAIL_REGULAR_EXPRESSION "embedder_snapshot_error:"
  FIXTURES_SETUP embedder_snapshot_blob
  TIMEOUT 300
  LABELS "smoke")

add_test(NAME embedder-snapshot.consume
         COMMAND embedder_snapshot consume "${_snapshot_blob}")
set_tests_properties(embedder-snapshot.consume PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  FAIL_REGULAR_EXPRESSION "embedder_snapshot_error:"
  FIXTURES_REQUIRED embedder_snapshot_blob
  DEPENDS embedder-snapshot.build
  TIMEOUT 300
  LABELS "smoke")

node_test_runtime_libs(embedder_snapshot)
