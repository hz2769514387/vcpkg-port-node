# NODE_OPTIONS from a developer's shell must not change what a test measures: this machine injects
# a language shim through it, and CI (where NODE_OPTIONS is empty) cannot reveal the difference.
#
# Included at the end of a case's CMakeLists so the test list is complete. Appending rather than
# replacing matters - abi, application, suite and others set their own environment variables.
# get_test_property and the TESTS directory property are both available in CMake 3.24, the
# project's declared minimum; set_tests_properties' DIRECTORY option is not (3.28), which is why
# this lives in each case instead of the top-level CMakeLists.
get_property(_node_options_tests DIRECTORY PROPERTY TESTS)
foreach(_node_options_test IN LISTS _node_options_tests)
  get_test_property("${_node_options_test}" ENVIRONMENT _node_options_existing)
  if(_node_options_existing)
    set_tests_properties("${_node_options_test}" PROPERTIES
      ENVIRONMENT "NODE_OPTIONS=;${_node_options_existing}")
  else()
    set_tests_properties("${_node_options_test}" PROPERTIES ENVIRONMENT "NODE_OPTIONS=")
  endif()
endforeach()
