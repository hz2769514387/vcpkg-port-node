# What embedding has to support, beyond "it links".
#
# Every case here runs the embedding executable built in embedder/, so what is under test
# is the consumer-linked runtime, not the port's own node.exe. The scenarios are the
# questions consumers actually ask once the hello world works: does the host see Node.js's
# exit semantics, is worker_threads complete inside an embedded runtime, can the runtime
# spawn a child, and can one process link the port next to the very libraries the port
# externalized.

set(_embedding "${CMAKE_CURRENT_SOURCE_DIR}")

# --- exit code semantics ------------------------------------------------------
# ctest compares a test's exit code with zero, which cannot express "this program is
# supposed to exit with 7", so a small driver script does the comparing instead.
add_test(NAME embedding.exit.ok
  COMMAND "${CMAKE_COMMAND}"
    -DEXE=$<TARGET_FILE:node_embedder>
    -DSCRIPT=${_embedding}/exit_ok.js
    -DEXPECT=0
    -P "${_embedding}/check_exit.cmake")
add_test(NAME embedding.exit.code7
  COMMAND "${CMAKE_COMMAND}"
    -DEXE=$<TARGET_FILE:node_embedder>
    -DSCRIPT=${_embedding}/exit_code7.js
    -DEXPECT=7
    -P "${_embedding}/check_exit.cmake")
add_test(NAME embedding.exit.uncaught
  COMMAND "${CMAKE_COMMAND}"
    -DEXE=$<TARGET_FILE:node_embedder>
    -DSCRIPT=${_embedding}/exit_uncaught.js
    -DEXPECT=1
    -P "${_embedding}/check_exit.cmake")
set_tests_properties(
  embedding.exit.ok
  embedding.exit.code7
  embedding.exit.uncaught
  PROPERTIES TIMEOUT 120 LABELS "smoke")

# --- runtime features ---------------------------------------------------------
add_test(NAME embedding.workers COMMAND node_embedder "${_embedding}/workers.js")
set_tests_properties(embedding.workers PROPERTIES TIMEOUT 180 LABELS "smoke")

add_test(NAME embedding.spawn_child COMMAND node_embedder "${_embedding}/spawn_child.js")
set_tests_properties(embedding.spawn_child PROPERTIES TIMEOUT 180 LABELS "smoke")

# --- one process, both sides of the same libraries ----------------------------
# Declared as ordinary vcpkg dependencies in test/vcpkg.json, next to node: the point is
# that they coexist with the port in one consumer, not that they are used in isolation.
find_package(absl CONFIG REQUIRED)
find_package(hwy CONFIG REQUIRED)
find_package(simdutf CONFIG REQUIRED)
find_package(OpenSSL REQUIRED)
find_package(ZLIB CONFIG REQUIRED)

# Same normalization the port's own consumer config performs: vcpkg's zlib exports
# ZLIB::ZLIBSTATIC, and ZLIB::ZLIB only exists when the vcpkg toolchain's wrapper answers
# the lookup. Pick whichever is there.
if(NOT TARGET ZLIB::ZLIB AND TARGET ZLIB::ZLIBSTATIC)
  add_library(ZLIB::ZLIB INTERFACE IMPORTED)
  set_target_properties(ZLIB::ZLIB PROPERTIES INTERFACE_LINK_LIBRARIES ZLIB::ZLIBSTATIC)
endif()

add_executable(coexist_consumer coexist_main.cpp)
target_link_libraries(coexist_consumer PRIVATE
  unofficial::node::node
  absl::strings
  hwy::hwy
  simdutf::simdutf
  OpenSSL::Crypto
  ZLIB::ZLIB)
target_compile_features(coexist_consumer PRIVATE cxx_std_20)

add_test(NAME embedding.coexist
  COMMAND coexist_consumer "${_embedding}/exit_ok.js")
set_tests_properties(embedding.coexist PROPERTIES TIMEOUT 180 LABELS "smoke")
