# The lower-level environment path, and the real effect of EnvironmentFlags::kNoBrowserGlobals.
#
# CommonEnvironmentSetup is what every other case in this project uses, but it takes neither
# IsolateSettings nor EnvironmentFlags. A host that owns crash handling or has its own globals has
# to call NewIsolate / CreateIsolateData / CreateEnvironment itself, and this case is the proof
# that the path works against this install rather than a paragraph claiming it does.
#
# It also pins what the flag actually removes. The header says "browser globals like setTimeout,
# console, etc."; measured, `console` and `setImmediate` survive while `fetch`, `setTimeout` and
# `queueMicrotask` do not. A product that trusts the comment gets a missing timer or a global it
# meant to suppress, so the table is a test rather than a sentence.
#
# Two ctest cases, one binary: the default is kNoBrowserGlobals, and the environment variable asks
# for kDefaultFlags so both sides of the table are measured on every cell.

add_executable(low_level main.cpp)
target_compile_features(low_level PRIVATE cxx_std_20)
target_link_libraries(low_level PRIVATE unofficial::node::node)

add_test(NAME low-level.no_browser_globals COMMAND low_level)
set_tests_properties(low-level.no_browser_globals PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  FAIL_REGULAR_EXPRESSION "low_level: "
  TIMEOUT 120
  LABELS "smoke")

add_test(NAME low-level.default_globals COMMAND low_level)
set_tests_properties(low-level.default_globals PROPERTIES
  ENVIRONMENT "NODE_OPTIONS=;NODE_PORT_TEST_DEFAULT_GLOBALS=1"
  FAIL_REGULAR_EXPRESSION "low_level: "
  TIMEOUT 120
  LABELS "smoke")

node_test_runtime_libs(low_level)
