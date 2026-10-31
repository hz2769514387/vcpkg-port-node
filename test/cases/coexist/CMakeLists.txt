# One process linking the port next to the very libraries the port externalized.
#
# Declared as ordinary vcpkg dependencies in test/vcpkg.json, next to node: the point is that they
# coexist with the port in one consumer, not that they are used in isolation. That is the question
# externalization raises and nothing else answers - abseil, highway, simdutf, OpenSSL and zlib each
# have symbols that would collide with a vendored copy, and a consumer that also uses them directly is
# the arrangement most likely to find out.
#
# The script it runs is the embedder's, from ../embed: what is under test here is the link, not the
# script.

find_package(absl CONFIG REQUIRED)
find_package(hwy CONFIG REQUIRED)
find_package(simdutf CONFIG REQUIRED)
find_package(OpenSSL REQUIRED)
# ZLIB::ZLIB is normalized in the project's top-level CMakeLists, for every consumer at once.

add_executable(coexist_consumer coexist_main.cpp)
target_link_libraries(coexist_consumer PRIVATE
  unofficial::node::node
  absl::strings
  hwy::hwy
  simdutf::simdutf
  OpenSSL::Crypto
  ZLIB::ZLIB)
target_compile_features(coexist_consumer PRIVATE cxx_std_20)

add_test(NAME coexist.same_process
  COMMAND coexist_consumer "${NODE_TEST_EMBED_DIR}/exit_ok.js")
set_tests_properties(coexist.same_process PROPERTIES TIMEOUT 180 LABELS "smoke")

# Its DLLs live next to the library, not next to this executable (Windows shared only).
node_test_runtime_libs(coexist_consumer)
