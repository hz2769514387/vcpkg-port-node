// mutual_roundtrip.cpp —— "同进程互相操作"共存测试的 **C++ 那一半**。
//
// 与已有的测试相比，它补的是最硬的那块：
//   * `unit_node_coexist`：同一个可执行里同时链 unofficial::node::node 与 vcpkg 的一批库，
//     调双方 API 做**版本交叉核对**（但 node 那侧是通过子进程问的）；
//   * `coexist.js`：只跑 node 那侧，把各库提供的能力过一遍；
//   * **本文件**：一个进程里，C++ 侧用 vcpkg 的库**产出数据**，
//     交给**同一个进程里的 node 运行时**（node::Start）消费并产出结果，
//     C++ 侧再用 vcpkg 的库**读回来逐项核对**，最后再做一次反方向。
//     两侧用的是同一份库（node 链接的就是 vcpkg 那些），所以只要有一侧偷偷用了
//     另一份拷贝（版本不同／行为漂移），对照值就会不一致。
//
// 交接方式：工作目录里的文件（stage1.* 由 C++ 写、stage2.* 由 JS 写）。
// ★ ada_c.h **没有 extern "C" 保护**（它开头就写了 "This is a C file, not C++"），
//   C++ 里直接 include 会把 ada_parse / ada_is_valid 这些声明按 C++ 修饰，
//   而 ada.lib 里导出的是 C 符号 ⇒ 链接期 undefined symbol（名字对不上，
//   不是"没链上"——ada.lib 确实在链接行上）。
extern "C" {
#include <ada_c.h>
}
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <simdjson.h>
#include <sqlite3.h>
#include <unicode/unistr.h>
#include <unicode/uversion.h>
#include <zlib.h>

#include <node.h>  // 放在最后：它带 v8 头，避免和其它库的头互相干扰

#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <string_view>
#include <vector>

namespace {

std::string ReadFile(const std::filesystem::path& p) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return {};
  return std::string((std::istreambuf_iterator<char>(f)),
                     std::istreambuf_iterator<char>());
}

void WriteFile(const std::filesystem::path& p, const std::string& s) {
  std::ofstream f(p, std::ios::binary | std::ios::trunc);
  f.write(s.data(), static_cast<std::streamsize>(s.size()));
}

int Fail(const std::string& msg) {
  std::fprintf(stderr, "MUTUAL-FAIL: %s\n", msg.c_str());
  return 1;
}

std::string Sha256Hex(const std::string& s) {
  unsigned char digest[EVP_MAX_MD_SIZE];
  unsigned int len = 0;
  if (EVP_Digest(s.data(), s.size(), digest, &len, EVP_sha256(), nullptr) != 1)
    return {};
  std::string out;
  for (unsigned int i = 0; i < len; i++) {
    char buf[3];
    std::snprintf(buf, sizeof(buf), "%02x", static_cast<unsigned>(digest[i]));
    out += buf;
  }
  return out;
}

std::string Deflate(const std::string& s) {
  uLongf cap = compressBound(static_cast<uLong>(s.size()));
  std::string out(cap, '\0');
  if (compress2(reinterpret_cast<Bytef*>(out.data()), &cap,
                reinterpret_cast<const Bytef*>(s.data()),
                static_cast<uLong>(s.size()), 6) != Z_OK)
    return {};
  out.resize(cap);
  return out;
}

std::string Inflate(const std::string& s, size_t expected_size) {
  std::string out(expected_size + 1024, '\0');
  uLongf cap = static_cast<uLongf>(out.size());
  if (uncompress(reinterpret_cast<Bytef*>(out.data()), &cap,
                 reinterpret_cast<const Bytef*>(s.data()),
                 static_cast<uLong>(s.size())) != Z_OK)
    return {};
  out.resize(cap);
  return out;
}

std::string AdaString(ada_string s) { return std::string(s.data, s.length); }

// 用 vcpkg 的 sqlite3 写一个真库文件，交给 node:sqlite 读
bool WriteSqlite(const std::filesystem::path& db_path) {
  sqlite3* db = nullptr;
  if (sqlite3_open(db_path.string().c_str(), &db) != SQLITE_OK) return false;
  const char* sql =
      "CREATE TABLE IF NOT EXISTS t(a INTEGER, b TEXT);"
      "DELETE FROM t;"
      "INSERT INTO t VALUES (1, 'one');"
      "INSERT INTO t VALUES (2, 'two');";
  bool ok = sqlite3_exec(db, sql, nullptr, nullptr, nullptr) == SQLITE_OK;
  sqlite3_close(db);
  return ok;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 3) {
    std::fprintf(stderr, "用法：mutual_roundtrip <mutual.js> <workdir>\n");
    return 2;
  }
  const std::filesystem::path js_path = argv[1];
  const std::filesystem::path work = argv[2];
  std::filesystem::create_directories(work);

  // 故意带非 ASCII：顺带压一压"参数/文件内容编码"这条路径（Windows 上尤其容易出问题）
  const std::string expected =
      "The quick brown fox jumps over the lazy dog. \xE2\x80\x94 \xE4\xB8\xAD\xE6\x96\x87";
  WriteFile(work / "expected.txt", expected);

  // ---- C++ 侧（vcpkg 的库）：zlib 压缩、openssl 摘要、ada 解析 URL、sqlite3 写库 ----
  const std::string deflated = Deflate(expected);
  if (deflated.empty()) return Fail("vcpkg zlib 压缩失败");
  WriteFile(work / "stage1.bin", deflated);

  const std::string cxx_sha = Sha256Hex(expected);
  if (cxx_sha.empty()) return Fail("vcpkg openssl 摘要失败");

  const std::string url_text = "https://b\xC3\xBC" "cher.example/a/b?q=1";
  WriteFile(work / "url.txt", url_text);
  ada_url parsed = ada_parse(url_text.data(), url_text.size());
  if (!ada_is_valid(parsed)) return Fail("vcpkg ada 解析 URL 失败");
  const std::string cxx_host = AdaString(ada_get_hostname(parsed));
  const std::string cxx_path = AdaString(ada_get_pathname(parsed));
  const std::string cxx_search = AdaString(ada_get_search(parsed));
  ada_free(parsed);

  if (!WriteSqlite(work / "stage1.sqlite")) return Fail("vcpkg sqlite3 写库失败");

  UVersionInfo uver{};
  u_getVersion(uver);
  char cxx_icu[32];
  std::snprintf(cxx_icu, sizeof(cxx_icu), "%d.%d", static_cast<int>(uver[0]),
                static_cast<int>(uver[1]));
  icu::UnicodeString up = icu::UnicodeString::fromUTF8("\xC3\x9F");  // ß
  up.toUpper();
  std::string cxx_upper;
  up.toUTF8String(cxx_upper);

  // ---- 把 node 运行时在**同一个进程**里跑起来 ----
  std::string js_arg = js_path.string();
  std::string work_arg = work.string();
  std::vector<char*> node_argv = {
      const_cast<char*>("node"),
      const_cast<char*>("--experimental-sqlite"),
      js_arg.data(),
      work_arg.data(),
  };
  const int rc = node::Start(static_cast<int>(node_argv.size()), node_argv.data());
  if (rc != 0) return Fail("node::Start 返回 " + std::to_string(rc));

  // ---- 回来用 vcpkg 的库核对 JS 侧产物 ----
  const std::string stage2 = ReadFile(work / "stage2.json");
  if (stage2.empty()) return Fail("JS 侧没有写出 stage2.json");

  simdjson::dom::parser parser;
  simdjson::dom::element doc;
  if (parser.parse(stage2).get(doc) != simdjson::SUCCESS)
    return Fail("vcpkg simdjson 解析 stage2.json 失败");

  bool inflated_matches = false;
  if (doc["inflatedMatches"].get_bool().get(inflated_matches) != simdjson::SUCCESS)
    return Fail("读 inflatedMatches 失败");
  if (!inflated_matches) return Fail("node 解压 vcpkg 压缩的数据对不上");

  std::string_view js_sha;
  if (doc["sha256"].get_string().get(js_sha) != simdjson::SUCCESS)
    return Fail("读 sha256 失败");
  if (std::string(js_sha) != cxx_sha)
    return Fail("sha256 两侧不一致：C++=" + cxx_sha + " JS=" + std::string(js_sha));

  simdjson::dom::element js_url;
  if (doc["urlParts"].get(js_url) != simdjson::SUCCESS) return Fail("读 urlParts 失败");
  std::string_view h, p, q;
  js_url["hostname"].get_string().get(h);
  js_url["pathname"].get_string().get(p);
  js_url["search"].get_string().get(q);
  if (std::string(h) != cxx_host || std::string(p) != cxx_path || std::string(q) != cxx_search)
    return Fail("URL 解析两侧不一致：C++=" + cxx_host + cxx_path + cxx_search +
                " JS=" + std::string(h) + std::string(p) + std::string(q));

  std::string_view js_upper, js_zlib, js_openssl, js_icu, js_sqlite, js_node;
  doc["nodeVersion"].get_string().get(js_node);
  if (std::string(js_node) != "24.21.0")
    return Fail("node 版本不是 24.21.0：" + std::string(js_node));
  doc["upper"].get_string().get(js_upper);
  doc["zlibVersion"].get_string().get(js_zlib);
  doc["opensslVersion"].get_string().get(js_openssl);
  doc["icuVersion"].get_string().get(js_icu);
  doc["sqliteVersion"].get_string().get(js_sqlite);

  if (std::string(js_upper) != cxx_upper)
    return Fail("ICU 大小写映射不一致：C++=" + cxx_upper + " JS=" + std::string(js_upper));
  if (std::string(js_zlib) != zlibVersion())
    return Fail("zlib 版本不一致：C++=" + std::string(zlibVersion()) + " JS=" + std::string(js_zlib));
  // ★ 取 OPENSSL_VERSION_STR（宏，值是 "3.6.3"），不是 OpenSSL_version(OPENSSL_VERSION)
  //   （返回 "OpenSSL 3.6.3 9 Jun 2026"，把日期也算进去；node 的
  //   process.versions.openssl 就是 "3.6.3"）。注意它不是 OpenSSL_version() 的索引。
  if (std::string(js_openssl) != OPENSSL_VERSION_STR)
    return Fail("openssl 版本不一致：C++=" + std::string(OPENSSL_VERSION_STR) +
                " JS=" + std::string(js_openssl));
  if (std::string(js_icu) != cxx_icu)
    return Fail("icu 版本不一致：C++=" + std::string(cxx_icu) +
                " JS=" + std::string(js_icu));
  if (!js_sqlite.empty() && std::string(js_sqlite) != sqlite3_libversion())
    return Fail("sqlite 版本不一致：C++=" + std::string(sqlite3_libversion()) +
                " JS=" + std::string(js_sqlite));

  // ---- 反方向：node 压缩，vcpkg zlib 解压 ----
  const std::string back = Inflate(ReadFile(work / "stage2.deflate"), expected.size());
  if (back != expected) return Fail("vcpkg zlib 解压 node 压缩的数据对不上");

  std::printf(
      "MUTUAL-OK: 同进程双向通过了 "
      "zlib / openssl / sqlite3 / ada / icu / simdjson 的互相校验\n"
      "  node=%s zlib=%s openssl=%s icu=%s sqlite=%s\n",
      std::string(js_node).c_str(), std::string(js_zlib).c_str(),
      std::string(js_openssl).c_str(), std::string(js_icu).c_str(),
      js_sqlite.empty() ? "(未编译进此构建)" : std::string(js_sqlite).c_str());
  return 0;
}
