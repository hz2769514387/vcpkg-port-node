# A consumer-built native addon, loaded into the runtime the consumer linked.
#
# This is the case that "it links" cannot answer. An embedding executable is not node.exe:
# a .node module has to find every napi_* symbol in the process that loaded it. With a static
# libnode those symbols live in the host executable, which therefore has to export them - the
# embedder sets ENABLE_EXPORTS for exactly this case, and an addon author has to do the same.
# With a shared libnode they live in the DLL, and the addon resolves them from there.
#
# The addon itself is ordinary N-API code compiled against the headers in the installed
# package. It exercises sync calls, JS callbacks, Buffers, thrown errors, async work on
# libuv's thread pool, and a thread-safe function fed by a std::thread - the last one being
# how a native producer feeds a JavaScript consumer in a real application.

find_package(Threads REQUIRED)

add_library(node_port_addon MODULE addon.cpp)
set_target_properties(node_port_addon PROPERTIES
  PREFIX "" SUFFIX ".node" OUTPUT_NAME "node_port_addon")
target_compile_features(node_port_addon PRIVATE cxx_std_20)
target_include_directories(node_port_addon PRIVATE
  "$<TARGET_PROPERTY:unofficial::node::node,INTERFACE_INCLUDE_DIRECTORIES>")
target_link_libraries(node_port_addon PRIVATE Threads::Threads)

if(APPLE)
  # A Mach-O bundle resolves napi_* from the process that loads it; say so explicitly
  # rather than depending on the generator's default for MODULE targets.
  target_link_options(node_port_addon PRIVATE "-Wl,-undefined,dynamic_lookup")
endif()

if(WIN32)
  # An addon imports napi_* rather than defining them. dllimport is selected by the
  # BUILDING_NODE_EXTENSION define, which is what node-addon-api and node-gyp both set.
  target_compile_definitions(node_port_addon PRIVATE BUILDING_NODE_EXTENSION)
  # Use the config's own switch, not if(TARGET unofficial::node::libnode): CMake reports a
  # namespaced target as existing on a static install too, once find_package() has loaded a
  # config that mentions it (measured on CMake 3.31). Linking a name that does not really
  # exist would then fail at generate time rather than describe the linkage.
  if(NODE_PORT_SHARED)
    # Shared install: napi_* is exported by libnode.dll.
    target_link_libraries(node_port_addon PRIVATE unofficial::node::libnode)
  else()
    # Static install: napi_* is exported by the executable that linked libnode.
    target_link_libraries(node_port_addon PRIVATE node_embedder)
  endif()
endif()

add_test(NAME addon.napi_module
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/addon.mjs"
                 "$<TARGET_FILE:node_port_addon>")
set_tests_properties(addon.napi_module PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  PASS_REGULAR_EXPRESSION "addon: N-API module ok"
  FAIL_REGULAR_EXPRESSION "addon_error:"
  TIMEOUT 300
  LABELS "smoke")

# A worker thread has its own isolate; a forked child is a whole new process started from
# process.execPath. Both have to load the addon and find napi_* again. These are the shapes a
# product uses for a native work pool, and neither is implied by the main-thread case.
add_test(NAME addon.in_workers_and_children
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/addon_processes.mjs"
                 "$<TARGET_FILE:node_port_addon>")
set_tests_properties(addon.in_workers_and_children PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  PASS_REGULAR_EXPRESSION "addon: worker thread and child process ok"
  FAIL_REGULAR_EXPRESSION "addon_error:"
  TIMEOUT 300
  LABELS "smoke")
