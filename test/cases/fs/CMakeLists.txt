# Filesystem paths are where an embedder's argv handling and the runtime's path handling
# meet, and they are the first thing a non-English product notices.
#
# The first case creates filenames with spaces, escapes and non-ASCII characters entirely
# inside the runtime. The second one passes a non-ASCII argument *from CMake*, through ctest,
# through the embedder's wmain on Windows (which converts wargv to UTF-8 itself) and into
# JavaScript: a host that used main(char**) would interpret it through the system ANSI code
# page and the assertion would fail. The name is built from ASCII decimal byte values so the
# tracked file itself stays ASCII, as this repository's language gate requires.

set(_fs_workdir "${CMAKE_CURRENT_BINARY_DIR}/unicode")

add_test(NAME fs.paths_and_streams
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/fs.mjs" "${_fs_workdir}")
set_tests_properties(fs.paths_and_streams PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  TIMEOUT 180
  LABELS "smoke")

# E4 B8 AD = U+4E2D, E6 96 87 = U+6587, then "-1": "the name the host supplies".
string(ASCII 228 184 173 230 150 135 45 49 _fs_utf8_name)
add_test(NAME fs.utf8_argv
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/utf8_argv.mjs" "${_fs_utf8_name}")
set_tests_properties(fs.utf8_argv PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  TIMEOUT 180
  LABELS "smoke")
