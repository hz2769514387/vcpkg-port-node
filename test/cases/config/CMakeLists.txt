# What the exported CMake config promises, checked against the installed package.
#
# A consumer reads `unofficial::node::node` before writing a single line of their own build:
# its include directories, its C++ standard, the stack/manifest link options on Windows, the
# ABI numbers it publishes and the files it says are installed. cases/install checks the
# static/shared split; this case checks the contract itself, including that the config is
# relocatable (no path from the machine that built it leaked into the installed file).
#
# The target properties are read here, where imported targets exist, and handed to a script
# that asserts them: cmake -P has no targets of its own.

get_filename_component(_config_prefix "${unofficial-node_DIR}/../.." ABSOLUTE)
# NODE_PORT_SHARED is the config's own switch. Do not use if(TARGET unofficial::node::libnode)
# to infer the linkage: CMake reports a namespaced target as existing on a static install too,
# once find_package() has loaded a config that names it. Measured on CMake 3.31.

add_test(NAME config.exported_contract
  COMMAND "${CMAKE_COMMAND}"
    -DPREFIX=${_config_prefix}
    -DCONFIG_FILE=${unofficial-node_DIR}/unofficial-node-config.cmake
    -DSTD_FEATURES=$<TARGET_PROPERTY:unofficial::node::node,INTERFACE_COMPILE_FEATURES>
    -DINCLUDE_DIRS=$<TARGET_PROPERTY:unofficial::node::node,INTERFACE_INCLUDE_DIRECTORIES>
    -DLINK_OPTIONS=$<TARGET_PROPERTY:unofficial::node::node,INTERFACE_LINK_OPTIONS>
    -DMODULE_VERSION=${node_MODULE_VERSION}
    -DNAPI_VERSION=${node_NAPI_VERSION}
    -DNAPI_MAX=${node_NAPI_VERSION_MAX}
    -DLINKAGE=${node_LIBRARY_LINKAGE}
    "-DINSTALLED_LIBS=${node_INSTALLED_LIBRARIES}"
    -DON_WINDOWS=${WIN32}
    -DNODE_PORT_SHARED=${NODE_PORT_SHARED}
    -P "${CMAKE_CURRENT_SOURCE_DIR}/check_config.cmake")
set_tests_properties(config.exported_contract PROPERTIES TIMEOUT 60 LABELS "smoke")
