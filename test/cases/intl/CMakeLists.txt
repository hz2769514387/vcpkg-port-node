# Full ICU comes from vcpkg, and Temporal comes from the Rust crate in deps/crates.
#
# These are the two pieces most likely to be quietly missing from a library build: ICU with
# small-icu data still formats an en-US date, and a build without node_crates still starts
# but has no Temporal. cases/externalization reads the build switches; this case asks for
# locale data that small-icu does not carry, calendars outside the default set, and a
# Temporal calculation that only exists when the crate was compiled and linked.

add_test(NAME intl.full_data_and_temporal
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/intl.mjs")
set_tests_properties(intl.full_data_and_temporal PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  TIMEOUT 180
  LABELS "smoke")

if(DEFINED node_EXECUTABLE AND EXISTS "${node_EXECUTABLE}")
  add_test(NAME intl.full_data_and_temporal_tools
           COMMAND "${node_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/intl.mjs")
  set_tests_properties(intl.full_data_and_temporal_tools PROPERTIES
    ENVIRONMENT "NODE_OPTIONS="
    TIMEOUT 180
    LABELS "smoke")
endif()
