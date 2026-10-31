# Symbol audit as a ctest target.
#
# Registers `symbols-no-duplicate-strong`: scans the port's own archives against the
# vcpkg archives they externalize, and fails when a strong symbol is defined twice.
# See symbol_check.js for why "it links" is not enough.
#
# The script runs under the node this project just built (node_embedder), which doubles
# as a self-check of the embedded runtime's fs/child_process/Buffer.
include(${CMAKE_CURRENT_LIST_DIR}/ctest_symbols.cmake)
