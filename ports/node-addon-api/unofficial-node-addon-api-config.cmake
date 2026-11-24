# The wrapper headers are this port's only artifacts. <node_api.h> is not installed here: it
# comes from unofficial::node::node, the runtime this overlay is paired with, so an addon
# compiles against the same Node.js the engine links. Do not add a second node_api.h to the
# include path (that is what the registry port's node-api-headers dependency does).
if(NOT TARGET unofficial::node-addon-api::node-addon-api)
  add_library(unofficial::node-addon-api::node-addon-api IMPORTED INTERFACE)
  set_target_properties(unofficial::node-addon-api::node-addon-api PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_LIST_DIR}/../../include/"
  )
endif()
