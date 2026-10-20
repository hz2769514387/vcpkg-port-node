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

# Resolve the tool's absolute path at configure time. The CMake process may not have
# the MSVC bin directory on PATH (Visual Studio generator does not chainload vcvars into
# the CMake process), so find_program by name alone can fail. Fall back to the compiler
# and linker directories: cl.exe and link.exe live in the same dir as dumpbin.exe.
# The ctest process is NOT in vcvars either, so we must pass the absolute path into the
# script.
set(_node_port_symtool_arg "")
if(WIN32)
  get_filename_component(_node_port_cl_dir "${CMAKE_CXX_COMPILER}" DIRECTORY)
  get_filename_component(_node_port_link_dir "${CMAKE_LINKER}" DIRECTORY)
  find_program(NODE_PORT_DUMPBIN NAMES dumpbin
               HINTS "${_node_port_cl_dir}" "${_node_port_link_dir}")
  if(NOT NODE_PORT_DUMPBIN)
    message(WARNING "dumpbin not found (looked in PATH and next to ${CMAKE_CXX_COMPILER}); "
                    "skipping symbol audit")
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
# so the libraries are in <prefix>/lib. <prefix>/lib/manual-link is scanned as well - it is
# vcpkg's directory for libraries a port deliberately keeps out of the shared link path, and
# this port installs nothing there today (the directory is usually absent and the script
# skips it). Keeping both on the command line means moving a colliding library aside later is
# a portfile change only. find_package(unofficial-node CONFIG) sets unofficial-node_DIR to
# the config file's directory.
get_filename_component(_node_port_prefix "${unofficial-node_DIR}/../.." ABSOLUTE)
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

# The audit compares *archives*, and a shared libnode is one library that deliberately
# contains the static-only dependencies: off Windows abseil, highway and simdutf have no
# shared form, so they are compiled into libnode by design, and the "duplicate" between
# libnode.so and libabsl_base.a is the intent rather than a finding. The archives next to
# libnode in <prefix>/lib are never linked into the consumer's process at all, so the
# question the audit asks does not describe this linkage. Measured on arm64-osx-dynamic
# (run 39424273491): 93 "node libraries" and a wall of abseil duplicates, all of them
# dependencies sitting untouched in the install prefix.
#
# What replaces it for a shared build: the port refuses to finish if libnode has undefined
# abseil symbols (ports/node/portfile.cmake), which is the property this audit exists to
# protect. Recorded in issue #11 as a coverage note, not as a passing leg.
if(node_LIBRARY_LINKAGE STREQUAL "dynamic")
  message(STATUS "symbol audit: skipped for a shared libnode (one library, static-only "
                 "dependencies embedded by design); the port's own undefined-symbol check "
                 "covers the same property")
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
