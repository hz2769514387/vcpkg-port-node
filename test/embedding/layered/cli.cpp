// The second target in the same project: it links the engine *and* the port directly.
//
// Two linkage styles coexisting in one build is normal - the library hides Node.js from its
// users, a command line tool built from the same sources wants the headers for its own
// reasons - and it is worth checking that the imported target is usable both ways without
// anything being included twice.
#include "engine.h"

#include <node.h>

#include <cstdio>

int main(int argc, char* argv[]) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s <script.js>\n", argv[0]);
    return 2;
  }
  std::printf("layered cli: sees node %s directly, %s through the engine\n",
              NODE_VERSION_STRING, engine::RuntimeVersions().c_str());
  return engine::RunScriptFile(argv[1]);
}
