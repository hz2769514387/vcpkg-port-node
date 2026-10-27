# Optional features: `tools` (the node executable and the npm/npx shims) and
# `test-suite` (Node.js's own test tree and its tools/test.py driver).
#
# Both are install-time only: they move files that a normal build already produced.
#
# Expects from the portfile: _node_configs, the build output directory, CURRENT_PACKAGES_DIR.

# ---------------------------------------------------------------------------
# 4) tools feature: node executable + npm / npx.
# ---------------------------------------------------------------------------
if("tools" IN_LIST FEATURES)
    set(_node_tools "${CURRENT_PACKAGES_DIR}/tools/${PORT}")
    if(VCPKG_TARGET_IS_WINDOWS)
        file(INSTALL "${SOURCE_PATH}/out/Release/node.exe" DESTINATION "${_node_tools}")
    else()
        file(INSTALL "${SOURCE_PATH}/out/Release/node" DESTINATION "${_node_tools}"
            FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                            GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
    endif()
    # A shared build needs its library beside the executable. node.gyp gives
    # the Linux binary `-rpath $ORIGIN/../lib` and the macOS one
    # `@rpath/libnode.dylib` with `@loader_path` and `@loader_path/../lib`,
    # so both spellings are covered: next to the binary, and one level up
    # under lib/. Windows looks next to the binary and nowhere else.
    if(_node_shared_build)
        if(VCPKG_TARGET_IS_WINDOWS)
            set(_node_tool_shlib "${SOURCE_PATH}/out/Release/libnode.dll")
        elseif(VCPKG_TARGET_IS_OSX)
            set(_node_tool_shlib "${SOURCE_PATH}/out/Release/${_node_shlib_name}")
        else()
            set(_node_tool_shlib "${SOURCE_PATH}/out/Release/lib/${_node_shlib_name}")
        endif()
        file(INSTALL "${_node_tool_shlib}" DESTINATION "${_node_tools}")
        file(INSTALL "${_node_tool_shlib}" DESTINATION "${CURRENT_PACKAGES_DIR}/tools/lib")
        unset(_node_tool_shlib)
    endif()
    file(INSTALL "${SOURCE_PATH}/deps/npm/" DESTINATION "${_node_tools}/node_modules/npm"
        USE_SOURCE_PERMISSIONS)
    # The shims are the ones the source tree ships. They resolve node and the package next to
    # themselves, which is this layout, so a copy here would only be a second version to keep in
    # step - and an out-of-date one: the four this port used to carry were 13-16 line rewrites of
    # upstream's 20-65 line scripts, without their WSL and Cygwin handling.
    #
    # Node.js 26 no longer ships corepack, so there is no third shim: `deps/corepack` does not
    # exist in the tree, and the port used to install one anyway whenever a path happened to exist.
    foreach(_shim IN ITEMS npm npx)
        file(INSTALL "${SOURCE_PATH}/deps/npm/bin/${_shim}" DESTINATION "${_node_tools}"
            RENAME "${_shim}"
            FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                            GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
        file(INSTALL "${SOURCE_PATH}/deps/npm/bin/${_shim}.cmd" DESTINATION "${_node_tools}"
            RENAME "${_shim}.cmd")
    endforeach()
    unset(_shim)
endif()

# ---------------------------------------------------------------------------
# 5) test-suite feature: the official test tree and the tools/test.py driver.
# ---------------------------------------------------------------------------
if("test-suite" IN_LIST FEATURES)
    set(_node_suite "${CURRENT_PACKAGES_DIR}/share/node/test-suite")
    # USE_SOURCE_PERMISSIONS: file(INSTALL) defaults to 0644/0755 and would drop
    # the executable bits the suite relies on for its fixture scripts.
    file(INSTALL "${SOURCE_PATH}/test/" DESTINATION "${_node_suite}/test" USE_SOURCE_PERMISSIONS)
    file(INSTALL "${SOURCE_PATH}/tools/" DESTINATION "${_node_suite}/tools" USE_SOURCE_PERMISSIONS)
    file(INSTALL "${SOURCE_PATH}/benchmark/" DESTINATION "${_node_suite}/benchmark" USE_SOURCE_PERMISSIONS)
    file(INSTALL "${SOURCE_PATH}/doc/" DESTINATION "${_node_suite}/doc" USE_SOURCE_PERMISSIONS)
    file(INSTALL "${SOURCE_PATH}/lib/" DESTINATION "${_node_suite}/lib" USE_SOURCE_PERMISSIONS)
    file(INSTALL "${SOURCE_PATH}/src/" DESTINATION "${_node_suite}/src" USE_SOURCE_PERMISSIONS
        FILES_MATCHING PATTERN "*.h" PATTERN "*.hpp" PATTERN "*.cc")
    file(INSTALL "${SOURCE_PATH}/CHANGELOG.md" DESTINATION "${_node_suite}")
    # corepack is not in this list because Node.js 26 does not ship it; the rest are the
    # dependencies the suite reaches into.
    foreach(_dep IN ITEMS npm acorn undici)
        if(EXISTS "${SOURCE_PATH}/deps/${_dep}")
            file(INSTALL "${SOURCE_PATH}/deps/${_dep}" DESTINATION "${_node_suite}/deps"
                USE_SOURCE_PERMISSIONS)
        endif()
    endforeach()
    unset(_dep)
    if(EXISTS "${SOURCE_PATH}/deps/v8/src/objects/intl-objects.h")
        file(INSTALL "${SOURCE_PATH}/deps/v8/src/objects/intl-objects.h"
            DESTINATION "${_node_suite}/deps/v8/src/objects")
    endif()
endif()
