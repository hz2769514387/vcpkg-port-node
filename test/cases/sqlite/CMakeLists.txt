# node:sqlite reaches vcpkg's sqlite3 through the port's --shared-sqlite path, built with
# the feature set Node.js expects: fts3/fts5, JSON1, math functions, rtree and the session
# extension. cases/externalization checks one FTS4 query; this case checks the rest of the
# product surface a database-backed application would actually call.
#
# A build with a stock registry sqlite3 (no FTS5, no math) links and starts perfectly. The
# failure arrives as a syntax error in the consumer's first query, which is why each feature
# gets its own statement here.

add_test(NAME sqlite.feature_surface
         COMMAND node_embedder "${CMAKE_CURRENT_SOURCE_DIR}/sqlite.mjs")
set_tests_properties(sqlite.feature_surface PROPERTIES
  ENVIRONMENT "NODE_OPTIONS="
  TIMEOUT 180
  LABELS "smoke")
