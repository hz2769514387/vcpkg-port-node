// The application: it links the engine library and nothing else.
//
// If it builds and runs, the port's requirements survived a PRIVATE link through a static
// library, which is the case a consumer is most likely to hit and the one that breaks first
// when a config forgets to state something on its interface.
#include "engine.h"

#include <cstdio>

int main(int argc, char* argv[]) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s <script.js>\n", argv[0]);
    return 2;
  }
  std::printf("layered app: engine built against %s\n", engine::RuntimeVersions().c_str());
  return engine::RunScriptFile(argv[1]);
}
