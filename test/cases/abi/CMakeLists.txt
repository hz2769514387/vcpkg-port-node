# The two ABI numbers a consumer reads without linking anything.
#
# NODE_MODULE_VERSION decides which prebuilt addon may be loaded; NAPI_VERSION which native API surface
# may be called. The exported config publishes both, and nothing compared them with the runtime until
# this case existed - a wrong number fails in the consumer's addon load, with a message that names
# neither this port nor this file. It found one: the config published the *maximum* N-API the runtime
# supports as if it were the default, so a consumer that trusted it targeted an API version the runtime
# would refuse.
#
# `node_NAPI_VERSION` and `node_NAPI_VERSION_MAX` are both passed because they are different promises:
# the first is what an addon may assume by default, the second is the ceiling the runtime implements.

add_test(NAME abi.napi_version COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/abi.mjs")
set_tests_properties(abi.napi_version PROPERTIES
  ENVIRONMENT "NODE_PORT_MODULE_VERSION=${node_MODULE_VERSION};NODE_PORT_NAPI_VERSION=${node_NAPI_VERSION};NODE_PORT_NAPI_VERSION_MAX=${node_NAPI_VERSION_MAX}"
  TIMEOUT 180
  LABELS "smoke")
