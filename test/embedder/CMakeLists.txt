# The embedding executable.
#
# This is the target the rest of the project measures: everything else either runs this
# binary or compares against it. Keeping it a separate directory means a consumer reading
# the repository finds the "how do I embed Node.js" answer in one small file rather than
# inside a test harness.

add_executable(node_embedder main.cpp)
target_link_libraries(node_embedder PRIVATE unofficial::node::node)
# The port declares cxx_std_20 on the interface already; restating it here documents that
# any consumer of these headers needs it too.
target_compile_features(node_embedder PRIVATE cxx_std_20)
set_target_properties(node_embedder PROPERTIES OUTPUT_NAME node_embed)

# Node.js only ever exports symbols through its own DLL list when built shared; for the
# static library everything stays visible, which is what this binary needs.
install(TARGETS node_embedder RUNTIME DESTINATION bin)

# Its DLLs live next to the library, not next to this executable (Windows shared only).
node_test_runtime_libs(node_embedder)
