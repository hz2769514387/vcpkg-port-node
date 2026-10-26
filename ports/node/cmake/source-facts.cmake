# Facts this port reads out of the Node.js source tree, in one place.
#
# They are read from the tree - never typed into a manifest or a portfile - because everything this
# port publishes to a consumer has to describe the tree that was actually built:
#
#   node_version_string   what find_package(unofficial-node CONFIG) reports
#   node_module_version   NODE_MODULE_VERSION, what a prebuilt addon was compiled against
#   node_napi_version     NAPI_VERSION
#   node_stack_reserve    node.gyp's StackReserveSize, exported as /STACK for the host executable
#
# The version is also compared against the manifest, so a tarball that is not the version the
# manifest claims fails the build here rather than shipping a package that lies about itself. That
# is not hypothetical: before this file existed the version was a literal, and 26.12.0 was
# delivered as 26.12.1 (run 40102604734).
#
# Requires: SOURCE_PATH, VERSION.

file(STRINGS "${SOURCE_PATH}/src/node_version.h" _node_v_line
     REGEX "^#define NODE_(MAJOR|MINOR|PATCH)_VERSION [0-9]+$")

foreach(_part MAJOR MINOR PATCH)
    file(STRINGS "${SOURCE_PATH}/src/node_version.h" _node_v_${_part}_line
         REGEX "^#define NODE_${_part}_VERSION [0-9]+$")
    string(REGEX MATCH "[0-9]+" _node_v_${_part} "${_node_v_${_part}_line}")
    if(NOT _node_v_${_part})
        message(FATAL_ERROR
            "could not read NODE_${_part}_VERSION from ${SOURCE_PATH}/src/node_version.h; "
            "update the regex in ports/node/cmake/source-facts.cmake to match the new header.")
    endif()
endforeach()
set(node_version_string "${_node_v_MAJOR}.${_node_v_MINOR}.${_node_v_PATCH}")
if(NOT node_version_string STREQUAL "${VERSION}")
    message(FATAL_ERROR
        "the Node.js source tree is ${node_version_string} while the manifest says ${VERSION}; "
        "the tarball, the manifest version and versions.json have to agree.")
endif()

# NODE_MODULE_VERSION can be overridden by an embedder at compile time (NODE_EMBEDDER_MODULE_VERSION
# in the consuming build), so what is published here is the default this library was built with.
file(STRINGS "${SOURCE_PATH}/src/node_version.h" _node_module_line
     REGEX "^#define NODE_MODULE_VERSION [0-9]+$")
string(REGEX MATCH "[0-9]+" node_module_version "${_node_module_line}")
file(STRINGS "${SOURCE_PATH}/src/js_native_api_types.h" _node_napi_line
     REGEX "^#define NAPI_VERSION [0-9]+$")
string(REGEX MATCH "[0-9]+" node_napi_version "${_node_napi_line}")
if(NOT node_module_version OR NOT node_napi_version)
    message(FATAL_ERROR
        "could not read NODE_MODULE_VERSION / NAPI_VERSION from the Node.js source tree "
        "(module='${node_module_version}', napi='${node_napi_version}'); update the regexes in "
        "ports/node/cmake/source-facts.cmake to match the new headers.")
endif()

if(VCPKG_TARGET_IS_WINDOWS)
    # Upstream node.gyp sets StackReserveSize for the executable gyp builds; a consumer's
    # executable would otherwise get the linker default of 1 MiB, which is too small for some
    # V8/inspector paths. Read the value rather than hard-coding it, and fail loudly when upstream
    # reorganises the setting.
    file(READ "${SOURCE_PATH}/node.gyp" _node_gyp_text)
    string(REGEX MATCHALL "'StackReserveSize'[^0-9]*0x[0-9A-Fa-f]+" _node_stack_hits "${_node_gyp_text}")
    list(LENGTH _node_stack_hits _node_stack_count)
    if(NOT _node_stack_count EQUAL 1)
        message(FATAL_ERROR
            "node port: found ${_node_stack_count} 'StackReserveSize' entries in node.gyp "
            "(expected exactly 1); upstream reorganised this setting, update the exported "
            "stack-size requirement accordingly.")
    endif()
    string(REGEX MATCH "0x[0-9A-Fa-f]+" node_stack_reserve "${_node_stack_hits}")
    unset(_node_gyp_text)
    unset(_node_stack_hits)
    unset(_node_stack_count)
endif()

message(STATUS
    "node port: source tree is Node.js ${node_version_string} "
    "(module ${node_module_version}, napi ${node_napi_version})")
