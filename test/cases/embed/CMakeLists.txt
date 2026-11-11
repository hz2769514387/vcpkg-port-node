# The embedding executable, and the two questions it answers about Node.js's own semantics.
#
# This is the target the rest of the project measures: every other case either runs this binary or
# compares against it, so it is also the "how do I embed Node.js" answer a consumer reads first - one
# small main.cpp rather than a test harness. `main()` is a faithful transcription of Node.js's own
# node_main.cc, which is why the cases below can talk about exit codes and worker threads as Node.js
# defines them rather than as this project happens to implement them.

add_executable(node_embedder main.cpp)
target_link_libraries(node_embedder PRIVATE unofficial::node::node)
# The port declares cxx_std_20 on the interface already; restating it here documents that any
# consumer of these headers needs it too.
target_compile_features(node_embedder PRIVATE cxx_std_20)
set_target_properties(node_embedder PROPERTIES OUTPUT_NAME node_embed)

# An embedding executable that loads native addons has to export the napi_* symbols it
# linked from the static libraries. CMake's ENABLE_EXPORTS generates the export table (and
# an import library on Windows) from the objects in the link; without it a consumer-built
# .node module fails to load with "The specified procedure could not be found" while the
# embedder itself works perfectly. cases/addon builds exactly that module and links it to
# this target on a static Windows install. With a shared libnode the symbols come from the
# DLL instead, so the addon links that on those cells; the property is harmless there.
set_target_properties(node_embedder PROPERTIES ENABLE_EXPORTS ON)

# Node.js only ever exports symbols through its own DLL list when built shared; for the static
# library everything stays visible, which is what this binary needs.
install(TARGETS node_embedder RUNTIME DESTINATION bin)

# Its DLLs live next to the library, not next to this executable (Windows shared only).
node_test_runtime_libs(node_embedder)

# --- exit code semantics ------------------------------------------------------
# ctest compares a test's exit code with zero, which cannot express "this program is supposed to exit
# with 7", so a small driver script does the comparing instead.
add_test(NAME embed.exit.ok
  COMMAND "${CMAKE_COMMAND}"
    -DEXE=$<TARGET_FILE:node_embedder>
    -DSCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/exit_ok.js
    -DEXPECT=0
    -P "${CMAKE_CURRENT_SOURCE_DIR}/check_exit.cmake")
add_test(NAME embed.exit.code7
  COMMAND "${CMAKE_COMMAND}"
    -DEXE=$<TARGET_FILE:node_embedder>
    -DSCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/exit_code7.js
    -DEXPECT=7
    -P "${CMAKE_CURRENT_SOURCE_DIR}/check_exit.cmake")
add_test(NAME embed.exit.uncaught
  COMMAND "${CMAKE_COMMAND}"
    -DEXE=$<TARGET_FILE:node_embedder>
    -DSCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/exit_uncaught.js
    -DEXPECT=1
    -P "${CMAKE_CURRENT_SOURCE_DIR}/check_exit.cmake")
set_tests_properties(
  embed.exit.ok
  embed.exit.code7
  embed.exit.uncaught
  PROPERTIES TIMEOUT 120 LABELS "smoke")

# --- runtime features ---------------------------------------------------------
# worker_threads is the part of the runtime most likely to be incomplete in a library build: it needs
# an isolate per worker, started from a thread the host did not create.
add_test(NAME embed.workers COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/workers.js")
set_tests_properties(embed.workers PROPERTIES TIMEOUT 180 LABELS "smoke")

# The runtime spawning another copy of itself: the child is node_embedder, found through
# process.execPath, which only resolves if the embedding sets it.
add_test(NAME embed.spawn_child COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/spawn_child.js")
set_tests_properties(embed.spawn_child PROPERTIES TIMEOUT 180 LABELS "smoke")

# --- the name the official suite expects ---------------------------------------
# Node.js builds several diagnostics from the executable's own name - the
# `--trace-warnings` hint says "Use `node --trace-warnings ...`", and it says
# "Use `node_embed --trace-warnings ...`" when the binary is called node_embed.
# Upstream's suite asserts that literal text (parallel/test-snapshot-warning), so a
# correctly built embedder fails it for no other reason than its file name.
#
# The suite runs against a copy called `node`, which is what upstream's own tests
# assume throughout. The copy sits next to the embedder, so a shared build finds
# libnode exactly as the embedder does, and cases/embed keeps testing the artifact
# under the name a consumer would actually ship.
add_custom_command(TARGET node_embedder POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
          "$<TARGET_FILE:node_embedder>"
          "$<TARGET_FILE_DIR:node_embedder>/node${CMAKE_EXECUTABLE_SUFFIX}"
  COMMENT "Suite shell: copying the embedder to node${CMAKE_EXECUTABLE_SUFFIX}")
