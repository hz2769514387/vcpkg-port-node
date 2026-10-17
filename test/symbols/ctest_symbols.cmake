# Register the symbol audit as a ctest target.
#
# Why this exists: externalizing abseil, highway, simdutf, zlib only delivers "one copy
# per process" if no two archives define the same strong symbol. A link success cannot
# tell - the linker silently picks one - so this scan makes the violation visible.
#
# What it checks: the port's own archives (libnode and friends) against the vcpkg archives
# they externalize. Weak symbols and inline/template instantiations are expected to
# collide and are not findings.
#
# Platform: dumpbin /SYMBOLS on Windows, nm on Linux/macOS. Skips with a reason when
# neither is available. A finding is a build-time bug in this repository, not a test
# failure to be suppressed.

set(_node_port_symbol_audit "${CMAKE_CURRENT_LIST_DIR}/symbol_check.js")
if(NOT EXISTS "${_node_port_symbol_audit}")
  message(WARNING "symbol_check.js not found at ${_node_port_symbol_audit}; skipping symbol audit")
  return()
endif()

# Resolve the tool's absolute path at configure time: the CMake process has the MSVC
# toolchain on PATH (via the chainloaded toolchain), so dumpbin is findable here. The
# ctest process is NOT in vcvars, so it cannot find dumpbin by PATH - we must pass the
# absolute path into the script.
set(_node_port_symtool_arg "")
if(WIN32)
  find_program(NODE_PORT_DUMPBIN NAMES dumpbin)
  if(NOT NODE_PORT_DUMPBIN)
    message(WARNING "dumpbin not found; skipping symbol audit (needs MSVC or Windows SDK dumpbin)")
    return()
  endif()
  set(_node_port_symtool_arg --dumpbin "${NODE_PORT_DUMPBIN}")
else()
  find_program(NODE_PORT_NM NAMES nm)
  if(NOT NODE_PORT_NM)
    message(WARNING "nm not found; skipping symbol audit")
    return()
  endif()
  set(_node_port_symtool_arg --nm "${NODE_PORT_NM}")
endif()

# node's library directory: node-config.cmake lives in <prefix>/share/unofficial-node/,
# so the libraries are in <prefix>/lib. After the collision-move step, abseil/highway/
# crdtp/v8_zlib etc. live in <prefix>/lib/manual-link - both dirs must be scanned
# (the script accepts a repeated --node-lib-dir).
get_filename_component(_node_port_prefix "${node_DIR}/../.." ABSOLUTE)
set(_node_port_libdir "${_node_port_prefix}/lib")

# Key: treat ONLY the libraries node itself installed as the "node side". <prefix>/lib
# is shared by the whole manifest project, so it also holds libraries this test project
# declared (gtest, fmt, ...); without distinguishing, the audit compares those against
# same-named vcpkg packages and reports "self vs self" false positives.
# node-config.cmake exports node_INSTALLED_LIBRARIES, which is exactly this list.
set(_node_port_libs_csv "")
if(DEFINED node_INSTALLED_LIBRARIES AND NOT node_INSTALLED_LIBRARIES STREQUAL "")
  string(REPLACE ";" "," _node_port_libs_csv "${node_INSTALLED_LIBRARIES}")
else()
  message(WARNING "node-config.cmake did not export node_INSTALLED_LIBRARIES; "
                  "the symbol audit will scan the whole lib dir and may report 'self vs self' false positives")
endif()

# vcpkg's packages directory: derive VCPKG_ROOT from the toolchain path.
if(DEFINED CMAKE_TOOLCHAIN_FILE)
  get_filename_component(_node_port_vcpkg_root "${CMAKE_TOOLCHAIN_FILE}/../../.." ABSOLUTE)
endif()
set(_node_port_packages "${_node_port_vcpkg_root}/packages")

if(NOT IS_DIRECTORY "${_node_port_packages}")
  message(WARNING "vcpkg packages directory not found ('${_node_port_packages}'); skipping symbol audit")
  return()
endif()

add_test(NAME symbols-no-duplicate-strong
         COMMAND node_embedder "${_node_port_symbol_audit}"
                 --node-lib-dir "${_node_port_libdir}"
                 --node-lib-dir "${_node_port_libdir}/manual-link"
                 --node-libs "${_node_port_libs_csv}"
                 --dep-root "${_node_port_packages}"
                 --triplet "${VCPKG_TARGET_TRIPLET}"
                 ${_node_port_symtool_arg}
                 --json "${CMAKE_CURRENT_BINARY_DIR}/symbol-audit.json"
                 --fail-on-duplicates)
set_tests_properties(symbols-no-duplicate-strong PROPERTIES
  LABELS "symbols;coexist;tools"
  TIMEOUT 3600)

message(STATUS "symbol audit: registered (script=${_node_port_symbol_audit}, "
               "node libs=${_node_port_libdir}, vcpkg packages=${_node_port_packages}, "
               "tool=${_node_port_symtool_arg})")
