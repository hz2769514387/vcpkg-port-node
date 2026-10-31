# The startup snapshot is a build artefact nothing else asserts.
#
# Losing it is silent: the runtime still works, it just compiles the builtins at every startup. Both
# hosts are checked because the snapshot is linked in differently for each - the library embeds it,
# node.exe is given it as a separate blob.
#
# The two ABI numbers live next door in ../abi: they are a different claim (which addon and which
# native API surface may be used), not part of the snapshot.

add_test(NAME snapshot.embedder COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/snapshot.mjs")
set_tests_properties(snapshot.embedder PROPERTIES
  TIMEOUT 180
  LABELS "smoke")

if(NOT DEFINED node_EXECUTABLE OR NOT EXISTS "${node_EXECUTABLE}")
  message(STATUS
    "no node executable installed (the node port's tools feature is off) - "
    "not registering the tools half of this case")
  return()
endif()

add_test(NAME snapshot.tools
         COMMAND "${node_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/snapshot.mjs")
set_tests_properties(snapshot.tools PROPERTIES
  TIMEOUT 180
  LABELS "smoke")
