# A library that hides Node.js, and two applications on top of it.
#
# The point is the PRIVATE link on the static library: the applications must build without
# naming the port themselves, which only works if the exported config states everything a
# consumer needs on its INTERFACE - archives, shared dependencies, system libraries, the C++
# standard, the stack size.

add_library(embedding_engine STATIC engine.cpp)
target_include_directories(embedding_engine PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_features(embedding_engine PRIVATE cxx_std_20)
target_link_libraries(embedding_engine PRIVATE unofficial::node::node)

add_executable(layered_app app.cpp)
target_compile_features(layered_app PRIVATE cxx_std_20)
target_link_libraries(layered_app PRIVATE embedding_engine)

add_executable(layered_cli cli.cpp)
target_compile_features(layered_cli PRIVATE cxx_std_20)
target_link_libraries(layered_cli PRIVATE embedding_engine unofficial::node::node)

# Its DLLs live next to the library, not next to this executable (Windows shared only).
node_test_runtime_libs(layered_app)
node_test_runtime_libs(layered_cli)
