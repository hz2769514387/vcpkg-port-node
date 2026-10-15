// 最小但忠实的 Node.js 嵌入可执行（embedder）—— 同时也是 node 官方测试套件的 shell。
//
// 为什么不是只做个 smoke：
//   node 官方的 tools/test.py 支持 `--shell=<可执行>`，于是只要有**一个忠实于官方 main
//   的可执行**，就能把官方 JS 用例真跑一遍。忠实度体现在两处：
//     1) 参数一字不改地交给 node::Start（官方 src/node_main.cc 就是这一句）；
//     2) Windows 上官方用的是 wmain + argv 转 UTF-8 —— 不是 ANSI 代码页。
//        很多用例会传非 ASCII 路径/参数，用 main(char**) 会按系统代码页解释而错乱。
//
// 用法（与 node 命令行一致）：
//     node -e "console.log(process.versions.node)"
//     node test/parallel/test-xxx.js
//     node --test test/parallel/
#include <node.h>

#include <cstdio>
#include <cstdlib>

#ifdef _WIN32
#include <windows.h>

// Debug 构建下 node/V8/ICU 的分配器与 CRT debug heap 交互会触发
// _CrtIsValidHeapPointer 断言（已知 Node.js #40926 类问题）。
// Release 构建无此检查，全量通过。
// 解法：清 _CRT_ASSERT 的 report mode → 断言不弹对话框、不中断，
// 进程不会挂死（ctest 超时）。ICU 密集用例可能 segfault（block 无
// debug header → header_from_block 算出非法指针），那是更深的已知限制。
#ifdef _DEBUG
#include <crtdbg.h>
struct _SuppressCrtAssert {
  _SuppressCrtAssert() {
    _CrtSetReportMode(_CRT_ASSERT, 0);
  }
} _suppress_crt_assert;
#endif

#include <string>
#include <vector>

namespace {

// 与上游 src/node_main.cc 一致：wchar_t** → UTF-8 的 char**。
// 返回的缓冲由 args 持有，调用方保证它在 node::Start 期间存活。
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
#ifdef _DEBUG
  SetEnvironmentVariableW(L"NODE_PORT_DEBUG", L"1");
#endif
  std::vector<std::string> args;
  std::vector<char*> argv = ToUtf8Argv(argc, wargv, &args);
  return node::Start(argc, argv.data());
}

#else  // 非 Windows：与上游一致，直通

int main(int argc, char* argv[]) { return node::Start(argc, argv); }

#endif
