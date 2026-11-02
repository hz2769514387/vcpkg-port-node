# What the package actually holds, against what its own config claims.
#
# One claim: the files a consumer is told to link are the files that were installed, and the ones
# that were deliberately not installed are absent. Issue #31 is the reason - a consumer reported
# that Temporal's Rust crate "was not built on Linux at all", because a *shared* install ships no
# archives of any kind and the report read that as a missing target. Nothing in the package
# asserted the difference, so the only way to know was to read a `-- Installing:` line.
#
# The archive list is not repeated here: it is read out of the installed package config, which is
# what a consumer links against. A test with its own copy of the list would pass while both copies
# were wrong together.

get_filename_component(_install_prefix "${unofficial-node_DIR}/../.." ABSOLUTE)

add_test(NAME install.what_the_linkage_ships
         COMMAND "${CMAKE_COMMAND}"
                 "-DPREFIX=${_install_prefix}"
                 "-DLINKAGE=${node_LIBRARY_LINKAGE}"
                 -P "${CMAKE_CURRENT_LIST_DIR}/assert-install.cmake")

set_tests_properties(install.what_the_linkage_ships PROPERTIES
  LABELS "smoke"
  TIMEOUT 60)
