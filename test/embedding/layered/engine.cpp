#include "engine.h"

#include <node.h>
#include <v8.h>

#include <vector>

namespace engine {

std::string RuntimeVersions() {
  return std::string("node ") + NODE_VERSION_STRING + " / v8 " + v8::V8::GetVersion();
}

int RunScriptFile(const std::string& path) {
  // node::Start takes the same argv node.exe would see, so the first element is the program
  // name and the second is the script.
  const std::vector<std::string> args = {"node", path};
  std::vector<char*> argv;
  argv.reserve(args.size() + 1);
  for (const std::string& arg : args) {
    argv.push_back(const_cast<char*>(arg.c_str()));
  }
  argv.push_back(nullptr);
  return node::Start(static_cast<int>(args.size()), argv.data());
}

}  // namespace engine
