// The embedding executable: this project's libnode consumer, and the shell Node.js's own
// test driver runs the official suite against.
//
// It stays deliberately close to upstream src/node_main.cc, and the two places that matter
// are exactly the two places upstream cares about:
//
//   1. argv is handed to node::Start unchanged - every argument means what it means in
//      upstream node, which is what makes this usable as `tools/test.py --shell=...`.
//   2. On Windows it enters through wmain and converts to UTF-8 itself. Using main(char**)
//      would interpret every argument through the system ANSI code page, and a large part
//      of the official suite passes non-ASCII paths and filenames - those tests are checking
//      Node.js behaviour, not our argv conversion.
//
// Nothing else is added. A shell that reinterprets its arguments is a shell whose test
// results mean something else.

#include <node.h>

#include <cstdio>
#include <cstdlib>

#ifdef _WIN32
#include <windows.h>

#include <string>
#include <vector>

namespace {

std::vector<char*> ToUtf8Argv(int argc, wchar_t* wargv[], std::vector<std::string>* storage) {
  storage->reserve(static_cast<size_t>(argc));
  for (int i = 0; i < argc; i++) {
    const int size =
        WideCharToMultiByte(CP_UTF8, 0, wargv[i], -1, nullptr, 0, nullptr, nullptr);
    if (size <= 0) {
      std::fprintf(stderr, "Could not convert arguments to utf8.\n");
      std::exit(1);
    }
    std::string buffer(static_cast<size_t>(size - 1), '\0');
    if (size > 1 &&
        WideCharToMultiByte(CP_UTF8, 0, wargv[i], -1, buffer.data(), size, nullptr, nullptr) == 0) {
      std::fprintf(stderr, "Could not convert arguments to utf8.\n");
      std::exit(1);
    }
    storage->push_back(std::move(buffer));
  }
  std::vector<char*> argv;
  argv.reserve(static_cast<size_t>(argc) + 1);
  for (std::string& value : *storage) {
    argv.push_back(value.data());
  }
  argv.push_back(nullptr);
  return argv;
}

}  // namespace

int wmain(int argc, wchar_t* wargv[]) {
  std::vector<std::string> storage;
  std::vector<char*> argv = ToUtf8Argv(argc, wargv, &storage);
  return node::Start(argc, argv.data());
}

#else

int main(int argc, char* argv[]) { return node::Start(argc, argv); }

#endif
