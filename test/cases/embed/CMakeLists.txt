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
