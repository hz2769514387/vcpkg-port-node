# A C++ addon written with node-addon-api's headers, loaded into the runtime the consumer
# linked. It proves the wrapper path end to end: napi.h from this repository's overlay port,
# <node_api.h> from the node port's include/node, and the napi_* symbols from the same runtime
# (an exported symbol in the executable for a static install, libnode for a shared one).
#
# The case is deliberately small - a class and two members - because test/cases/addon already
# covers the C API's wider surface; what this one adds is the C++ wrapper and the headers it
# needs to resolve.

find_package(unofficial-node-addon-api CONFIG REQUIRED)

add_library(node_port_addon_cpp MODULE addon_cpp.cpp)
set_target_properties(node_port_addon_cpp PROPERTIES
  PREFIX "" SUFFIX ".node" OUTPUT_NAME "node_port_addon_cpp")
target_compile_features(node_port_addon_cpp PRIVATE cxx_std_20)
target_link_libraries(node_port_addon_cpp PRIVATE
  unofficial::node-addon-api::node-addon-api)
target_include_directories(node_port_addon_cpp PRIVATE
  "$<TARGET_PROPERTY:unofficial::node::node,INTERFACE_INCLUDE_DIRECTORIES>")

if(APPLE)
  # A Mach-O bundle resolves napi_* from the process that loads it.
  target_link_options(node_port_addon_cpp PRIVATE "-Wl,-undefined,dynamic_lookup")
endif()

if(WIN32)
  # An addon imports napi_*; BUILDING_NODE_EXTENSION selects dllimport in node_api.h.
  target_compile_definitions(node_port_addon_cpp PRIVATE BUILDING_NODE_EXTENSION)
  if(NODE_PORT_SHARED)
    target_link_libraries(node_port_addon_cpp PRIVATE unofficial::node::libnode)
  else()
    target_link_libraries(node_port_addon_cpp PRIVATE node_embedder)
  endif()
endif()

add_test(NAME addon_cpp.napi_module
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/addon_cpp.mjs"
                 "$<TARGET_FILE:node_port_addon_cpp>")
set_tests_properties(addon_cpp.napi_module PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  PASS_REGULAR_EXPRESSION "addon-cpp: node-addon-api wrapper ok"
  FAIL_REGULAR_EXPRESSION "addon_error:"
  TIMEOUT 300
  LABELS "smoke")
