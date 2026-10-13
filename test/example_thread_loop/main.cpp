// 场景四：消息循环**耦合还是分离** —— 消费方把 node 嵌进自己程序时的第一个问题。
//
// 问题原样是："node 会不会霸占我的主线程？我自己的消息循环还跑不跑？"
// 答案取决于 node::Start 放在哪个线程，两种形态都对，看你的程序是什么角色：
//
//   耦合形态：主线程直接 node::Start。你的循环**就是** node 的事件循环，
//            node 不退出你不退出。适合"我的程序就是个 node 运行时"
//            （example_embed 就是这一形态，最简单的嵌入）。
//
//   分离形态（本示例）：node::Start 放进 worker 线程，主线程继续跑**自己的**
//            循环。适合"我的程序是主，node 是干活的工"—— GUI / 服务程序 /
//            已经有一套事件循环的老程序。
//
// 本示例把分离形态的四个要点都演示到，并且**逐条断言**：
//   1) 宿主循环在 node 运行期间持续 tick（不是只跑了启动前那几下）；
//   2) 数据双向到达：宿主 → node（消息文件）、node → 宿主（回复文件）；
//   3) 退出码原样取自 node::Start 的返回值（线程收场不吞码）；
//   4) 挂死保护：宿主等 node 有硬上限，超时就带着失败退出，不会无限挂住 CI。
//
// 通信方式用**共享目录里的消息文件**（而不是 stdin/管道）：
//   * 不抢占进程的 stdin/stdout —— 那是宿主自己的；
//   * 跨平台行为一致（POSIX 与 Windows 都是普通文件 + rename）；
//   * 写方"先写临时名再 rename"，读方永远看不到半条消息。
// 这就是真实集成里最常见的"投递目录"模式，例子虽小，形态是完整的。

#include <node.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <set>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include <filesystem>

namespace {

namespace fs = std::filesystem;

// ---------------------------------------------------------------- 协议常量 --
// 宿主 → node：h2n-000001.msg（内容一行文本）；收场信号：stop（空文件）。
// node → 宿主：n2h-000001.rpy（内容一行文本）。
constexpr const char* kH2NPrefix = "h2n-";
constexpr const char* kH2NSuffix = ".msg";
constexpr const char* kN2HPrefix = "n2h-";
constexpr const char* kN2HSuffix = ".rpy";
constexpr const char* kStopFile = "stop";

constexpr int kTotalMessages = 5;     // 宿主一共要发给 node 的消息条数
constexpr int kTicksPerMessage = 5;   // 宿主每 5 个 tick 发一条（≈150ms）
constexpr int kMinHostTicks = 20;     // 断言用：node 跑完前宿主至少 tick 这么多次
constexpr int kMinTicksBeforeFirstReply = 3;  // 断言用：首条回复到达前宿主 tick 次数
constexpr int kMaxTicks = 4000;       // 硬上限 4000×30ms=120s，防挂死

// ------------------------------------------------------------ 小工具（宿主）--
std::string ReadWholeFile(const fs::path& p) {
  std::ifstream f(p, std::ios::binary);
  std::ostringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

// 先写临时名再 rename：读者要么看到旧文件、要么看到完整的新文件，
// 不会看到写了一半的内容（POSIX 的 rename 与 Windows 的 MoveFile 都保证）。
void WriteAtomically(const fs::path& final_path, const std::string& content) {
  fs::path tmp = final_path;
  tmp += ".tmp";
  {
    std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
    f << content;
    if (!f) {
      std::fprintf(stderr, "THREAD-LOOP-FAIL: 写不了 %s\n", tmp.string().c_str());
      std::exit(1);
    }
  }
  // Windows 上 rename 到已存在的目标会失败；我们的文件名唯一，不会撞。
  fs::rename(tmp, final_path);
}

std::vector<std::string> ListWithPrefix(const fs::path& dir, const char* prefix) {
  std::vector<std::string> out;
  std::error_code ec;
  for (const auto& e : fs::directory_iterator(dir, ec)) {
    std::string name = e.path().filename().string();
    if (name.rfind(prefix, 0) == 0) out.push_back(name);
  }
  std::sort(out.begin(), out.end());
  return out;
}

bool HasSuffix(const std::string& name, const char* suffix) {
  const size_t n = std::strlen(suffix);
  return name.size() >= n && name.compare(name.size() - n, n, suffix) == 0;
}

int Fail(const std::string& why) {
  std::fprintf(stderr, "THREAD-LOOP-FAIL: %s\n", why.c_str());
  return 1;
}

// ------------------------------------------------------------------ 主流程 --
// argv: [0]=程序名 [1]=要跑的 JS [2]=共享目录（邮箱）
int HostMain(int argc, char* argv[]) {
  if (argc < 3) {
    std::fprintf(stderr,
                 "用法: %s <script.js> <mailbox-dir>\n"
                 "  <script.js>    在 node 里跑的脚本（本目录 loop_worker.js）\n"
                 "  <mailbox-dir>  宿主与 node 共享的投递目录\n",
                 argv[0]);
    return 2;
  }
  const std::string script = argv[1];
  const fs::path mailbox = argv[2];

  // stdout 接管道时 C  stdio 默认**全缓冲**：所有 HOST 行会堆到进程退出才
  // 一次性出来，日志里就看不到"两个循环交错"这个看点（node 那侧是事件驱动
  // 写的，天然及时）。改成行缓冲，交错效果实时可见。
  std::setvbuf(stdout, nullptr, _IOLBF, 0);

  // 邮箱先清空再建：示例要可重复运行（ctest 可能跑第二遍）。
  std::error_code ec;
  fs::create_directories(mailbox, ec);
  for (const auto& e : fs::directory_iterator(mailbox, ec)) {
    std::string name = e.path().filename().string();
    if (name.rfind(kH2NPrefix, 0) == 0 || name.rfind(kN2HPrefix, 0) == 0 ||
        name == kStopFile) {
      fs::remove(e.path(), ec);
    }
  }

  // ---- node 跑在 worker 线程：主线程从此是宿主自己的循环 --------------------
  std::atomic<int> node_exit_code{-1};
  std::atomic<bool> node_done{false};

  std::thread node_thread([&]() {
    // 与 example_embed 同一套 argv 口径：一字不改交给 node::Start。
    // （这里传的是"脚本 + 邮箱目录"，JS 侧从 process.argv 拿。）
    std::vector<char*> node_argv;
    node_argv.push_back(argv[0]);
    node_argv.push_back(argv[1]);
    node_argv.push_back(argv[2]);
    node_argv.push_back(nullptr);
    const int rc = node::Start(static_cast<int>(node_argv.size()) - 1,
                               node_argv.data());
    node_exit_code.store(rc);
    node_done.store(true);
  });

  // ---- 宿主自己的主循环：自己的节奏，自己的活 ---------------------------------
  int host_ticks = 0;
  int messages_sent = 0;
  int replies_seen = 0;
  int ticks_before_first_reply = -1;  // -1 = 还没收到第一条回复
  bool stop_sent = false;
  // 已计数的回复文件名。★ 按名去重是必须的：Windows 上删除刚被别人创建过的
  // 文件可能遇到瞬时共享冲突（杀毒/索引器扫一下就拿不住），删除失败时文件
  // 会留在邮箱里被下一轮 drain 重复数一次（2026-10-14 实测：同一二进制
  // 跑出过 replies=8 的假失败）。按名去重后，删除失败只是"文件多留一轮"，
  // 计数不受影响；配合 JS 侧"回复名=消息序号"的约定，陈旧文件也只会同名
  // 碰撞，计数永远确定。
  std::set<std::string> seen_replies;

  while (!node_done.load() && host_ticks < kMaxTicks) {
    ++host_ticks;
    std::printf("HOST-TICK %d\n", host_ticks);  // 宿主的"活"：自己的心跳

    if (messages_sent < kTotalMessages && host_ticks % kTicksPerMessage == 0) {
      ++messages_sent;
      char buf[64];
      std::snprintf(buf, sizeof(buf), "HOST-MSG %d", messages_sent);
      char name[64];
      std::snprintf(name, sizeof(name), "%s%06d%s", kH2NPrefix, messages_sent,
                    kH2NSuffix);
      WriteAtomically(mailbox / name, std::string(buf) + "\n");
    }
    if (messages_sent == kTotalMessages && !stop_sent) {
      WriteAtomically(mailbox / kStopFile, "");
      stop_sent = true;
    }

    // 收 node 的回复（node 那侧也是 rename 落盘的，读到的都是完整消息）。
    for (const std::string& name : ListWithPrefix(mailbox, kN2HPrefix)) {
      if (!HasSuffix(name, kN2HSuffix)) continue;          // 跳过 .tmp 半成品
      if (!seen_replies.insert(name).second) continue;     // 同名只计一次
      const std::string text = ReadWholeFile(mailbox / name);
      std::error_code rm_ec;
      fs::remove(mailbox / name, rm_ec);
      if (rm_ec) {
        std::fprintf(stderr,
                     "HOST-WARN: 删不掉 %s（%s）—— 下轮启动时会再清理，计数不受影响\n",
                     name.c_str(), rm_ec.message().c_str());
      }
      ++replies_seen;
      if (ticks_before_first_reply < 0) ticks_before_first_reply = host_ticks;
      std::printf("HOST-GOT %s\n", text.c_str());
    }

    std::this_thread::sleep_for(std::chrono::milliseconds(30));
  }

  const bool timed_out = !node_done.load();
  if (timed_out) {
    // 不 join 一个还卡在 node::Start 里的线程（会无限等）：分离它，
    // 用 _Exit 立刻结束进程，避免静态析构跑在一半的 node 运行时上。
    std::fprintf(stderr, "THREAD-LOOP-FAIL: 等 node 收场超时（%d 个 tick）\n",
                 host_ticks);
    std::fflush(stdout);
    std::fflush(stderr);
    node_thread.detach();
    std::_Exit(1);
  }
  node_thread.join();

  // join 之后再收一次尾：最后一条回复可能和 node 退出前后脚到。
  for (const std::string& name : ListWithPrefix(mailbox, kN2HPrefix)) {
    if (!HasSuffix(name, kN2HSuffix)) continue;          // 跳过 .tmp 半成品
    if (!seen_replies.insert(name).second) continue;     // 同名只计一次
    const std::string text = ReadWholeFile(mailbox / name);
    std::error_code rm_ec;
    fs::remove(mailbox / name, rm_ec);
    if (rm_ec) {
      std::fprintf(stderr,
                   "HOST-WARN: 删不掉 %s（%s）—— 下轮启动时会再清理，计数不受影响\n",
                   name.c_str(), rm_ec.message().c_str());
    }
    ++replies_seen;
    if (ticks_before_first_reply < 0) ticks_before_first_reply = host_ticks;
    std::printf("HOST-GOT %s\n", text.c_str());
  }

  // ---- 逐条断言（这就是"示例自带的测试"在宿主侧的那一半）--------------------
  // 顺序有讲究：先看 node 自己成没成。node 失败了（比如脚本路径写错）它会
  // 很快返回非 0，那时宿主 tick 数少是**结果**不是原因 —— 先报 node 的错，
  // 免得把"脚本路径写错"误读成"node 霸占主线程"。
  const int node_code = node_exit_code.load();
  if (node_code != 0) {
    return Fail("node 退出码不是 0：" + std::to_string(node_code) +
                "（宿主原样透传，没有改写；先修 node 那一侧的报错）");
  }
  if (host_ticks < kMinHostTicks) {
    return Fail("宿主循环在 node 运行期间几乎没 tick（" +
                std::to_string(host_ticks) + " < " +
                std::to_string(kMinHostTicks) +
                "）—— 看起来 node 霸占了主线程，循环没有分离");
  }
  if (ticks_before_first_reply >= 0 &&
      ticks_before_first_reply < kMinTicksBeforeFirstReply) {
    return Fail("第一条 node 回复到达前宿主只 tick 了 " +
                std::to_string(ticks_before_first_reply) +
                " 次 —— 两个循环没有同时在跑");
  }
  if (replies_seen != kTotalMessages) {
    return Fail("收到的回复数不对：期望 " + std::to_string(kTotalMessages) +
                "，实际 " + std::to_string(replies_seen));
  }

  std::printf("THREAD-LOOP-OK ticks=%d replies=%d node-exit=%d\n", host_ticks,
              replies_seen, node_code);
  return node_code;  // 原样透传 node 的退出码
}

}  // namespace

#ifdef _WIN32
#include <windows.h>

namespace {

// 与 example_embed 同一套理由：Windows 上官方用 wmain 并把 argv 转成 UTF-8，
// 路径/参数里的非 ASCII 才不会按系统代码页错乱。
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
  return HostMain(argc, argv.data());
}
#else
int main(int argc, char* argv[]) { return HostMain(argc, argv); }
#endif
