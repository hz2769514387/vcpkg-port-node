// 场景六的最小嵌入器：把 node 嵌进自己的可执行，然后跑 workers.js。
//
// 这个文件与 example_embed/main.cpp 是同一副样子（故意的）：每个示例都
// 自带一个完整、最小、忠实的嵌入器，消费方拷走**一个目录**就能跑，
// 不依赖别的示例编出来的东西。
//
// "忠实"体现在两处（也是 node 官方 src/node_main.cc 的做法）：
//   1) 参数一字不改地交给 node::Start；
//   2) Windows 上用 wmain 并把 argv 转成 UTF-8 —— 不是 ANSI 代码页，
//      否则带非 ASCII 的路径/参数会错乱。
#include <node.h>

#include <cstdio>
#include <cstdlib>

#ifdef _WIN32
#include <windows.h>

#include <string>
#include <vector>

namespace {

// wchar_t** → UTF-8 的 char**（返回的缓冲由 args 持有，node::Start 期间存活）。
std::vector<char*> ToUtf8Argv(int argc, wchar_t* wargv[],
                              std::vector<std::string>* args) {
  args->reserve(static_cast<size_t>(argc));
  for (int i = 0; i < argc; i++) {
    const int size = WideCharToMultiByte(CP_UTF8, 0, wargv[i], -1, nullptr, 0,
                                         nullptr, nullptr);
    if (size <= 0) {
      std::fprintf(stderr, "Could not convert arguments to utf8.\n");
      std::exit(1);
    }
    std::string buf(static_cast<size_t>(size - 1), '\0');
    if (size > 1 &&
        WideCharToMultiByte(CP_UTF8, 0, wargv[i], -1, buf.data(), size, nullptr,
                            nullptr) == 0) {
      std::fprintf(stderr, "Could not convert arguments to utf8.\n");
      std::exit(1);
    }
    args->push_back(std::move(buf));
  }
  std::vector<char*> argv;
  argv.reserve(static_cast<size_t>(argc) + 1);
  for (std::string& s : *args) argv.push_back(s.data());
  argv.push_back(nullptr);
  return argv;
}

}  // namespace

int wmain(int argc, wchar_t* wargv[]) {
  std::vector<std::string> args;
  std::vector<char*> argv = ToUtf8Argv(argc, wargv, &args);
  return node::Start(argc, argv.data());
}

#else  // 非 Windows：与上游一致，直通

int main(int argc, char* argv[]) { return node::Start(argc, argv); }

#endif
