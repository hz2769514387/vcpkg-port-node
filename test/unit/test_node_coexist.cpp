// 共存单元测试：把 node::node（整棵静态库，含 V8、uvwasi/merve/nbytes/ncrypto/crdtp、
// 以及 v8 内嵌的 abseil / highway / v8_zlib）与一批 vcpkg 库**同时**链进同一个可执行，
// 然后验证两件事：
//
//   1) 链接成功本身就说明没有"重复强符号"这类硬冲突 —— 有的话 lld-link / ld 会直接报错。
//   2) node 报告的依赖版本，必须与我们在这个进程里直接调用的那份库报出来的版本**一致**。
//      这是"node 用的就是 vcpkg 那一份"的运行期证据：如果 node 里还藏着一份自带副本，
//      uv / zlib / brotli 这些**运行期取值**的版本号就会对不上。
//
// 为什么这几个版本号能当证据（见 node 源码 src/node_metadata.cc）：
//   uv     = uv_version_string()        ← 运行期函数
//   zlib   = zlibVersion()              ← 运行期函数（非 NODE_BUNDLED_ZLIB 时）
//   brotli = BrotliEncoderVersion()     ← 运行期函数
//   openssl= GetOpenSSLVersion()        ← 运行期/头文件版本号
// 其余的（nghttp2 / zstd / icu / simdutf / sqlite …）是编译期宏，比对它们证明"头文件
// 也是同一份"，对共存同样是必要的（头不一致会导致 ABI 理解不一致）。
#include <gtest/gtest.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <string>

#include <absl/strings/str_format.h>
#include <brotli/encode.h>
#include <fmt/format.h>
#include <hwy/aligned_allocator.h>
#include <nghttp2/nghttp2.h>
#include <node.h>  // 消费方能用 node 的公开头
#include <openssl/crypto.h>
#include <simdutf.h>
#include <sqlite3.h>
#include <unicode/uversion.h>
#include <uv.h>
#include <zlib.h>

namespace {

std::string Trim(std::string s) {
  auto not_space = [](unsigned char c) { return !std::isspace(c); };
  s.erase(s.begin(), std::find_if(s.begin(), s.end(), not_space));
  s.erase(std::find_if(s.rbegin(), s.rend(), not_space).base(), s.end());
  return s;
}

// 把嵌入可执行当 CLI 用：node -p '<js>'。用它来问 node"你用的是哪个版本"。
std::string RunNodeEval(const std::string& js) {
  const std::string cmd =
      std::string("\"") + NODE_EMBED_PATH + "\" -p \"" + js + "\"";
#ifdef _WIN32
  FILE* pipe = _popen(cmd.c_str(), "r");
#else
  FILE* pipe = popen(cmd.c_str(), "r");
#endif
  if (pipe == nullptr) return "<popen failed>";
  std::string out;
  char buf[512];
  size_t n;
  while ((n = fread(buf, 1, sizeof(buf), pipe)) > 0) out.append(buf, n);
#ifdef _WIN32
  _pclose(pipe);
#else
  pclose(pipe);
#endif
  return Trim(out);
}

// 只保留数字与点，便于把 "OpenSSL 3.6.3 1 Oct 2025" 与 "3.6.3" 放一起比。
std::string Digits(const std::string& s) {
  std::string out;
  bool last_dot = true;
  for (char c : s) {
    if (std::isdigit(static_cast<unsigned char>(c))) {
      out.push_back(c);
      last_dot = false;
    } else if (c == '.' && !last_dot) {
      out.push_back(c);
      last_dot = true;
    } else if (!out.empty() && !last_dot) {
      out.push_back('.');
      last_dot = true;
    }
  }
  while (!out.empty() && out.back() == '.') out.pop_back();
  return out;
}

std::string BrotliVersionString() {
  const uint32_t v = BrotliEncoderVersion();
  return fmt::format("{}.{}.{}", v >> 24, (v & 0xFFF000) >> 12, v & 0xFFF);
}

const char* const kSample = "The quick brown fox jumps over the lazy dog.";

}  // namespace

// ---- 运行期版本交叉核对：node 报的 == 我们链进来的库报的 ----------------------

TEST(NodeCoexist, NodeReportsSameLibuv) {
  const std::string reported = RunNodeEval("process.versions.uv");
  ASSERT_FALSE(reported.empty());
  EXPECT_EQ(reported, uv_version_string());
}

TEST(NodeCoexist, NodeReportsSameZlib) {
  const std::string reported = RunNodeEval("process.versions.zlib");
  ASSERT_FALSE(reported.empty());
  EXPECT_EQ(reported, zlibVersion());
}

TEST(NodeCoexist, NodeReportsSameBrotli) {
  const std::string reported = RunNodeEval("process.versions.brotli");
  ASSERT_FALSE(reported.empty());
  EXPECT_EQ(reported, BrotliVersionString());
}

TEST(NodeCoexist, NodeReportsSameOpenSsl) {
  const std::string reported = RunNodeEval("process.versions.openssl");
  ASSERT_FALSE(reported.empty());
  EXPECT_EQ(Digits(reported), Digits(OpenSSL_version(OPENSSL_VERSION)));
}

// ---- 编译期版本（证明头文件也是同一份）----------------------------------------

TEST(NodeCoexist, NodeReportsSameNghttp2) {
  const std::string reported = RunNodeEval("process.versions.nghttp2");
  ASSERT_FALSE(reported.empty());
  ASSERT_NE(nghttp2_version(0), nullptr);
  EXPECT_EQ(reported, nghttp2_version(0)->version_str);
}

TEST(NodeCoexist, NodeReportsSameSimdutf) {
  const std::string reported = RunNodeEval("process.versions.simdutf");
  ASSERT_FALSE(reported.empty());
  // v8 内嵌的 simdutf 6.4.0 已由本 port 换成 vcpkg 的那一份；两边必须是同一个号。
  EXPECT_EQ(reported, SIMDUTF_VERSION);
}

TEST(NodeCoexist, NodeReportsSameIcu) {
  const std::string reported = RunNodeEval("process.versions.icu");
  ASSERT_FALSE(reported.empty());
  UVersionInfo ver{};
  u_getVersion(ver);
  const std::string ours =
      fmt::format("{}.{}", static_cast<int>(ver[0]), static_cast<int>(ver[1]));
  EXPECT_EQ(reported, ours);
}

TEST(NodeCoexist, NodeReportsSameSqlite) {
  const std::string reported = RunNodeEval("process.versions.sqlite");
  if (reported.empty()) {
    GTEST_SKIP() << "这份 node 构建里没有 sqlite（process.versions.sqlite 为空）";
  }
  EXPECT_EQ(reported, sqlite3_libversion());
}

// ---- 行为级：同一份实现产出的字节必须一致 -------------------------------------
// 如果 node 里藏着另一份 zlib，同输入同参数的 deflate 结果大概率不同 —— 这条是
// "同一份实现"的行为级旁证（版本号相同而实现不同也能被它抓出来）。
TEST(NodeCoexist, DeflateBytesIdenticalBetweenNodeAndOurs) {
  const size_t n = std::strlen(kSample);
  uLongf csize = compressBound(static_cast<uLong>(n));
  std::string compressed(csize, '\0');
  ASSERT_EQ(compress2(reinterpret_cast<Bytef*>(compressed.data()), &csize,
                      reinterpret_cast<const Bytef*>(kSample),
                      static_cast<uLong>(n), 6),
            Z_OK);
  compressed.resize(csize);
  std::string ours_hex;
  for (unsigned char c : compressed) ours_hex += fmt::format("{:02x}", c);

  const std::string theirs = RunNodeEval(
      "require('node:zlib')"
      ".deflateSync(Buffer.from('The quick brown fox jumps over the lazy dog.','utf8'),"
      "{level:6}).toString('hex')");
  ASSERT_FALSE(theirs.empty());
  EXPECT_EQ(theirs, ours_hex);
}

// ---- 共存可用性：这些库在"同一个进程里还装着 node+v8"的情况下照样能用 ----------

TEST(NodeCoexist, AbseilWorksWhileV8IsLinked) {
  EXPECT_EQ(absl::StrFormat("%d-%s", 1, "x"), "1-x");
  std::cout << "[coexist] abseil 可用（注意：v8 内嵌也有自己的一份 abseil，"
               "两份同名符号由链接器择一，符号审计另有专门检查）" << std::endl;
}

TEST(NodeCoexist, HighwayWorksWhileV8IsLinked) {
  auto p = hwy::AllocateAligned<float>(32);
  ASSERT_NE(p.get(), nullptr);
  p[0] = 1.0f;
  EXPECT_FLOAT_EQ(p[0], 1.0f);
  std::cout << "[coexist] highway 可用" << std::endl;
}

TEST(NodeCoexist, FmtWorksWhileNodeIsLinked) {
  EXPECT_EQ(fmt::format("{}", 42), "42");
}

// ---- 证据汇总（永远通过，只为把对照表打进 CI 日志）----------------------------

TEST(NodeCoexist, Report) {
  struct Row {
    const char* lib;
    std::string node_says;
    std::string we_say;
  };
  const std::vector<Row> rows = {
      {"node", RunNodeEval("process.versions.node"), "24.21.0"},
      {"v8", RunNodeEval("process.versions.v8"), "(v8::V8::GetVersion)"},
      {"uv", RunNodeEval("process.versions.uv"), uv_version_string()},
      {"zlib", RunNodeEval("process.versions.zlib"), zlibVersion()},
      {"brotli", RunNodeEval("process.versions.brotli"), BrotliVersionString()},
      {"openssl", RunNodeEval("process.versions.openssl"),
       Digits(OpenSSL_version(OPENSSL_VERSION))},
      {"nghttp2", RunNodeEval("process.versions.nghttp2"),
       nghttp2_version(0) ? nghttp2_version(0)->version_str : ""},
      {"simdutf", RunNodeEval("process.versions.simdutf"), SIMDUTF_VERSION},
      {"sqlite", RunNodeEval("process.versions.sqlite"), sqlite3_libversion()},
  };
  std::cout << "[coexist] node 报告的依赖版本 vs 本进程直接调用得到的版本\n";
  for (const Row& r : rows) {
    std::cout << fmt::format("  {:<8} node={:<28} ours={}\n", r.lib, r.node_says,
                             r.we_say);
  }
  SUCCEED();
}
