# The zlib decision, checked from the consumer's side.
#
# Node.js links vcpkg's zlib through `--shared-zlib`, so a consumer process holds exactly one
# zlib - and this is where that stops being a claim. The same input goes through zlib's C API
# and through Node.js's own compression, and both directions of the round trip are checked, in
# both processes.
#
# Three ctest cases rather than one, because the two halves cannot live in one process: an
# embedded runtime ends the process when its script ends. Fixtures express the order, and each
# stage reads what the previous one wrote. The files live in the build tree, and `prepare`
# deletes the runtime's outputs so that a stage that did not run makes `verify` fail on a missing
# file instead of passing on last run's evidence.

set(_zlib_workdir "${CMAKE_CURRENT_BINARY_DIR}/cross-path")

add_executable(zlib_paths zlib_paths.cpp)
target_compile_features(zlib_paths PRIVATE cxx_std_20)
target_link_libraries(zlib_paths PRIVATE ZLIB::ZLIB)

add_test(NAME zlib.cross_paths.prepare
  COMMAND zlib_paths prepare "${_zlib_workdir}")
set_tests_properties(zlib.cross_paths.prepare PROPERTIES
  FIXTURES_SETUP zlib_cross_paths TIMEOUT 120 LABELS "smoke")

# The runtime half runs on the embedder - the consumer-linked runtime - not on the port's own
# node.exe, so the javascript below exercises the same runtime a host application would link.
add_test(NAME zlib.cross_paths.runtime
  COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/zlib_paths.js" "${_zlib_workdir}")
set_tests_properties(zlib.cross_paths.runtime PROPERTIES
  FIXTURES_REQUIRED zlib_cross_paths TIMEOUT 120 LABELS "smoke")

add_test(NAME zlib.cross_paths.verify
  COMMAND zlib_paths verify "${_zlib_workdir}")
set_tests_properties(zlib.cross_paths.verify PROPERTIES
  FIXTURES_REQUIRED zlib_cross_paths DEPENDS zlib.cross_paths.runtime
  TIMEOUT 120 LABELS "smoke")
