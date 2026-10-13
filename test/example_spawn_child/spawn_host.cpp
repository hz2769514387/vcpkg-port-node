// 场景五：**不链接** node，把 node 当子进程用。
//
// 这是最常见的一类消费方："我不想把上百兆的静态库链进我的程序，我只想在
// 某些时候跑一段 JS、或者用一下 npm/npx"。port 的 `tools` feature 就是为
// 这个准备的：它把 node 可执行（以及 npm / npx / corepack）按官方发行版
// 布局装到 <prefix>/tools/node/，配置导出 `node_EXECUTABLE` 等变量。
//
// 本示例演示宿主这一侧的正确姿势，一个可复制的模板：
//   1) node 可执行路径从外面传进来（真实项目里可以来自配置/环境变量）；
//   2) spawn 它，并把**输出捕获回来** —— 而不是甩给继承的 stdout，
//      那样你的程序无法对输出做任何判断；
//   3) 如实拿到子进程退出码，打印出来（`CHILD-EXIT: <码>`），并让自己的
//      退出码反映它（子进程失败了宿主却 exit 0，是集成里最坑人的误用之一）；
//   4) spawn 本身失败（可执行不存在/起不来）与"子进程跑完但失败"是两回事，
//      报错要说清是哪一种。
//
// 两种收场口径（按调用方的角色选，`--expect-exit` 切换）：
//   * 默认 = **镜像口径**：宿主退出码 = 子进程退出码。适合"我就是那个
//     程序的门面，它成功我才成功"（CI 里包一层 node 跑脚本的常见形态）。
//   * `--expect-exit=N` = **断言口径**：宿主退出码 = "子进程码是否等于 N"。
//     适合"我来跑它并核对结果"（测试胶水、CI 探针）—— 子进程以**期望的**
//     失败码收场时，宿主认为自己的任务成功了（exit 0），并把
//     `CHILD-EXIT: N` 留在输出里供断言。
//
// 用法：
//   spawn_host [--expect-exit=N] <node 可执行> [传给 node 的参数...]
// 例：
//   spawn_host tools/node/node.exe -e "process.stdout.write(process.versions.node)"
//   spawn_host tools/node/node.exe script.js
//   spawn_host --expect-exit=3 tools/node/node.exe -e "process.exit(3)"

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/wait.h>
#include <unistd.h>
#endif

namespace {

struct RunResult {
  bool spawned = false;   // 进程有没有被成功创建
  int exit_code = -1;     // 子进程退出码（spawned == true 时有效）
  std::string out;        // 捕获到的子进程 stdout
};

#ifdef _WIN32

// CreateProcess 的命令行是一个字符串，参数要按 MSVCRT 的规则加引号：
// 含空格/制表符的包双引号，内部双引号转成 \"。node.exe 用的就是这个解析规则。
std::string QuoteForWindows(const std::string& arg) {
  const bool need_quote =
      arg.find_first_of(" \t\"") != std::string::npos;
  if (!need_quote) return arg;
  std::string quoted = "\"";
  for (char c : arg) {
    if (c == '"') quoted += "\\\"";
    else quoted += c;
  }
  quoted += "\"";
  return quoted;
}

RunResult RunChild(const std::string& exe,
                   const std::vector<std::string>& args) {
  RunResult r;

  // stderr 故意不做重定向：子进程的报错直接进我们自己的 stderr，
  // 留在 ctest 日志里，判读时不用再手工跑一遍。
  SECURITY_ATTRIBUTES sa{sizeof(SECURITY_ATTRIBUTES), nullptr, TRUE};
  HANDLE read_end = nullptr;
  HANDLE write_end = nullptr;
  if (!CreatePipe(&read_end, &write_end, &sa, 0)) {
    std::fprintf(stderr, "SPAWN-HOST-FAIL: CreatePipe 失败（%lu）\n",
                 GetLastError());
    return r;
  }
  if (!SetHandleInformation(read_end, HANDLE_FLAG_INHERIT, 0)) {
    std::fprintf(stderr, "SPAWN-HOST-FAIL: SetHandleInformation 失败（%lu）\n",
                 GetLastError());
    CloseHandle(read_end);
    CloseHandle(write_end);
    return r;
  }

  std::string cmdline = QuoteForWindows(exe);
  for (const std::string& a : args) {
    cmdline += ' ';
    cmdline += QuoteForWindows(a);
  }

  STARTUPINFOA si{};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES;
  // 三个 std 句柄都要显式给全，一个都不能留空：
  // 一旦带上 STARTF_USESTDHANDLES，子进程就用这里给的句柄；留空的那些
  // 不会"退回继承"，而是**直接没有这个句柄** —— 子进程写 stderr 会静默
  // 丢失（实测：node 的 console.error 什么都不打印，也不报错）。
  // 这里的取舍：stdout 接管道（要捕获回来给程序判断），stdin/stderr 继承
  // 宿主自己的（stderr 尤其要流进 ctest 日志，判读时不用再手工跑一遍）。
  si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  si.hStdOutput = write_end;
  si.hStdError = GetStdHandle(STD_ERROR_HANDLE);

  PROCESS_INFORMATION pi{};
  const BOOL ok = CreateProcessA(
      exe.c_str(), cmdline.data(), nullptr, nullptr, /*bInheritHandles=*/TRUE,
      CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi);
  CloseHandle(write_end);  // 本进程不再写；不关的话读端等不到 EOF
  if (!ok) {
    std::fprintf(stderr, "SPAWN-HOST-FAIL: 起不来 %s（%lu）\n", exe.c_str(),
                 GetLastError());
    CloseHandle(read_end);
    return r;
  }
  r.spawned = true;

  char buf[4096];
  DWORD got = 0;
  while (ReadFile(read_end, buf, sizeof(buf), &got, nullptr) && got > 0) {
    r.out.append(buf, got);
  }
  CloseHandle(read_end);

  WaitForSingleObject(pi.hProcess, INFINITE);
  DWORD code = 0;
  GetExitCodeProcess(pi.hProcess, &code);
  r.exit_code = static_cast<int>(code);
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return r;
}

#else  // POSIX

RunResult RunChild(const std::string& exe,
                   const std::vector<std::string>& args) {
  RunResult r;

  int pipefd[2];
  if (pipe(pipefd) != 0) {
    std::fprintf(stderr, "SPAWN-HOST-FAIL: pipe 失败\n");
    return r;
  }

  const pid_t pid = fork();
  if (pid < 0) {
    std::fprintf(stderr, "SPAWN-HOST-FAIL: fork 失败\n");
    close(pipefd[0]);
    close(pipefd[1]);
    return r;
  }
  if (pid == 0) {
    // 子进程：stdout 接管道写端（stderr 保持继承，直接进日志）。
    dup2(pipefd[1], STDOUT_FILENO);
    close(pipefd[0]);
    close(pipefd[1]);
    std::vector<char*> argv;
    argv.push_back(const_cast<char*>(exe.c_str()));
    for (const std::string& a : args) argv.push_back(const_cast<char*>(a.c_str()));
    argv.push_back(nullptr);
    execv(exe.c_str(), argv.data());
    // 只有 execv 失败才会到这里（比如路径不存在、没有执行位）。
    perror("execv");
    _exit(127);
  }

  close(pipefd[1]);
  char buf[4096];
  ssize_t got = 0;
  while ((got = read(pipefd[0], buf, sizeof(buf))) > 0) {
    r.out.append(buf, static_cast<size_t>(got));
  }
  close(pipefd[0]);
  int status = 0;
  waitpid(pid, &status, 0);
  r.spawned = true;
  if (WIFEXITED(status)) {
    r.exit_code = WEXITSTATUS(status);
  } else if (WIFSIGNALED(status)) {
    r.exit_code = 128 + WTERMSIG(status);  // 约定俗成：被信号杀掉 → 128+信号
  }
  return r;
}

#endif

}  // namespace

int main(int argc, char* argv[]) {
  // ---- 解析自己的参数：可选的 --expect-exit=N ------------------------------
  int expected_child_exit = -1;  // -1 = 镜像口径（不核对，直接镜像）
  int i = 1;
  for (; i < argc; i++) {
    const std::string a = argv[i];
    if (a.rfind("--expect-exit=", 0) == 0) {
      expected_child_exit = std::atoi(a.c_str() + sizeof("--expect-exit=") - 1);
      continue;
    }
    break;  // 第一个非本程序选项的参数：node 可执行路径
  }
  if (i >= argc) {
    std::fprintf(stderr,
                 "用法: %s [--expect-exit=N] <node 可执行> [传给 node 的参数...]\n"
                 "例: %s tools/node/node.exe -e "
                 "\"process.stdout.write(process.versions.node)\"\n",
                 argv[0], argv[0]);
    return 2;
  }
  const std::string node_exe = argv[i];
  const std::vector<std::string> node_args(argv + i + 1, argv + argc);

  const RunResult r = RunChild(node_exe, node_args);

  // 子进程的输出原样打出来：调用方（以及 ctest 的正则）直接可用。
  if (!r.out.empty()) std::fputs(r.out.c_str(), stdout);

  if (!r.spawned) {
    // "起不来"和"跑完了但失败"是两回事，上面 RunChild 已经把区别报过了。
    std::fprintf(stderr, "SPAWN-HOST-FAIL: 子进程没有跑起来\n");
    return 1;
  }

  // ★ 这行就是本示例要立住的规矩：子进程的退出码如实打印。
  std::printf("CHILD-EXIT: %d\n", r.exit_code);

  if (expected_child_exit >= 0) {
    // 断言口径：核对子进程退出码，不符就红（附上期望值，方便判读）。
    if (r.exit_code != expected_child_exit) {
      std::fprintf(stderr,
                   "EXPECT-EXIT-FAIL: 期望子进程退出码 %d，实际 %d\n",
                   expected_child_exit, r.exit_code);
      return 1;
    }
    std::printf("EXPECT-EXIT-OK: 子进程按预期以 %d 退出\n", r.exit_code);
    return 0;  // 核对成功 = 宿主任务成功（哪怕子进程本身是失败收场）
  }

  // 镜像口径：宿主退出码跟随子进程。
  if (r.exit_code != 0) {
    std::fprintf(stderr, "SPAWN-HOST-FAIL: node 子进程退出码 %d\n",
                 r.exit_code);
    return 1;
  }
  std::printf("SPAWN-HOST-OK\n");
  return 0;
}
