// 基线单元测试：这一批"使用者很可能同时想要"的 vcpkg 库，单独链进来能不能用。
//
// 为什么单独一个可执行：本文件**不链 node**。于是同一批断言分两处跑（这里 + 
// test_node_coexist.cpp），失败时立刻能区分"库自己有毛病"还是"和 node 共存有毛病"。
//
// 选库的依据：node 的直接依赖，加上与 v8 内嵌第三方同名的 port
// （abseil / highway / simdutf / zlib）—— 后者正是"担心符号冲突"的那一类。
#include <gtest/gtest.h>

#include <cstdint>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

#include <absl/strings/str_format.h>      // v8 内嵌 abseil：同名符号的第二份来源
#include <absl/strings/str_join.h>
#include <brotli/decode.h>
#include <brotli/encode.h>
#include <fmt/format.h>
#include <hdr/hdr_histogram.h>            // node 依赖（hdr-histogram）
#include <hwy/aligned_allocator.h>        // v8 内嵌 highway
// ★ MSVC 的头里没有 ssize_t，而 nghttp2.h 直接就用它。node 自己是在 node.h 里补的
//   （node 的 node_http2.h 注释原话："nghttp2.h needs ssize_t"）；但**本可执行故意不链
//   node**（那正是"基线"的意义），所以这里自己补一个 —— Windows 上的对应物就是
//   BaseTsd.h 的 SSIZE_T。
#if defined(_WIN32) && !defined(_SSIZE_T_DEFINED)
#include <BaseTsd.h>
using ssize_t = SSIZE_T;
#endif
#include <nghttp2/nghttp2.h>              // node 依赖（HTTP/2）
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <simdjson.h>                     // node 依赖
#include <simdutf.h>                      // v8 内嵌 simdutf（已被本 port 换成 vcpkg 的那一份）
#include <sqlite3.h>                      // node 依赖（node:sqlite）
#include <unicode/unistr.h>               // node 依赖（ICU）
#include <unicode/uversion.h>
#include <uv.h>                           // node 依赖（事件循环）
#include <zlib.h>                         // v8 内嵌 zlib（方案 Z1 后与 node 共用 vcpkg 的 zs/z）
#include <zstd.h>                         // node 依赖

namespace {

const char* const kSample = "The quick brown fox jumps over the lazy dog.";

}  // namespace

TEST(VcpkgBaseline, ZlibRoundTrip) {
  const size_t n = std::strlen(kSample);
  uLongf csize = compressBound(static_cast<uLong>(n));
  std::vector<Bytef> compressed(csize);
  ASSERT_EQ(compress2(compressed.data(), &csize,
                      reinterpret_cast<const Bytef*>(kSample),
                      static_cast<uLong>(n), 6),
            Z_OK);
  std::vector<Bytef> out(n);
  uLongf osize = static_cast<uLongf>(n);
  ASSERT_EQ(uncompress(out.data(), &osize, compressed.data(), csize), Z_OK);
  EXPECT_EQ(std::string(reinterpret_cast<char*>(out.data()), osize), kSample);
  std::cout << "[baseline] zlib " << zlibVersion() << " deflate 长度 "
            << csize << std::endl;
}

TEST(VcpkgBaseline, OpenSslSha256KnownVector) {
  unsigned char digest[EVP_MAX_MD_SIZE];
  unsigned int len = 0;
  ASSERT_EQ(EVP_Digest("abc", 3, digest, &len, EVP_sha256(), nullptr), 1);
  ASSERT_EQ(len, 32u);
  // 已知向量：SHA256("abc")
  static const unsigned char kExpected[32] = {
      0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea, 0x41, 0x41, 0x40,
      0xde, 0x5d, 0xae, 0x22, 0x23, 0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17,
      0x7a, 0x9c, 0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad};
  EXPECT_EQ(0, std::memcmp(digest, kExpected, 32));
  std::cout << "[baseline] openssl " << OpenSSL_version(OPENSSL_VERSION) << std::endl;
}

TEST(VcpkgBaseline, LibuvLoopRuns) {
  EXPECT_STRNE(uv_version_string(), "");
  uv_loop_t loop;
  ASSERT_EQ(0, uv_loop_init(&loop));
  EXPECT_EQ(0, uv_run(&loop, UV_RUN_DEFAULT));
  EXPECT_EQ(0, uv_loop_close(&loop));
  std::cout << "[baseline] libuv " << uv_version_string() << std::endl;
}

TEST(VcpkgBaseline, BrotliRoundTrip) {
  const size_t n = std::strlen(kSample);
  size_t csize = BrotliEncoderMaxCompressedSize(n);
  std::vector<uint8_t> compressed(csize);
  ASSERT_EQ(BROTLI_TRUE,
            BrotliEncoderCompress(BROTLI_DEFAULT_QUALITY, BROTLI_DEFAULT_WINDOW,
                                  BROTLI_MODE_TEXT, n,
                                  reinterpret_cast<const uint8_t*>(kSample),
                                  &csize, compressed.data()));
  std::vector<uint8_t> out(n);
  size_t osize = n;
  ASSERT_EQ(BROTLI_DECODER_RESULT_SUCCESS,
            BrotliDecoderDecompress(csize, compressed.data(), &osize, out.data()));
  EXPECT_EQ(std::string(reinterpret_cast<char*>(out.data()), osize), kSample);
  const uint32_t v = BrotliEncoderVersion();
  std::cout << "[baseline] brotli " << (v >> 24) << "."
            << ((v & 0xFFF000) >> 12) << "." << (v & 0xFFF) << std::endl;
}

TEST(VcpkgBaseline, ZstdRoundTrip) {
  const size_t n = std::strlen(kSample);
  std::vector<char> compressed(ZSTD_compressBound(n));
  const size_t csize =
      ZSTD_compress(compressed.data(), compressed.size(), kSample, n, 3);
  ASSERT_FALSE(ZSTD_isError(csize));
  std::vector<char> out(n);
  const size_t osize = ZSTD_decompress(out.data(), out.size(), compressed.data(), csize);
  ASSERT_FALSE(ZSTD_isError(osize));
  EXPECT_EQ(std::string(out.data(), osize), kSample);
  std::cout << "[baseline] zstd " << ZSTD_versionString() << std::endl;
}

TEST(VcpkgBaseline, SimdutfAsciiAndUtf16) {
  EXPECT_TRUE(simdutf::validate_ascii(kSample, std::strlen(kSample)));
  const std::u32string u32 = U"h\u00e9llo";  // 用转义而不是字面量，避开源码编码问题
  std::vector<char16_t> u16(u32.size() * 2);
  const size_t written = simdutf::convert_utf32_to_utf16le(u32.data(), u32.size(),
                                                          u16.data());
  ASSERT_GT(written, 0u);
  EXPECT_TRUE(simdutf::validate_utf16le(u16.data(), written));
  std::cout << "[baseline] simdutf " << SIMDUTF_VERSION
            << "（v8 内嵌副本已被替换成这一份）" << std::endl;
}

TEST(VcpkgBaseline, SimdjsonParses) {
  simdjson::dom::parser parser;
  simdjson::dom::element doc;
  // 单参数的 parse() 在这个版本里是 `&&` 重载、**被 delete 掉了**（simdjson 不接受
  // "不知道长度、也没保证尾部有填充"的输入）。给 (data, size) 两个参数走
  // realloc_if_needed 那条路（默认 true），由它自己去补填充。
  const std::string json_src = R"({"a":1,"b":"x"})";
  ASSERT_EQ(simdjson::SUCCESS,
            parser.parse(json_src.data(), json_src.size()).get(doc));
  int64_t a = 0;
  ASSERT_EQ(simdjson::SUCCESS, doc["a"].get_int64().get(a));
  EXPECT_EQ(a, 1);
  std::cout << "[baseline] simdjson " << SIMDJSON_VERSION << std::endl;
}

TEST(VcpkgBaseline, SqliteInMemory) {
  sqlite3* db = nullptr;
  ASSERT_EQ(SQLITE_OK, sqlite3_open(":memory:", &db));
  char* err = nullptr;
  ASSERT_EQ(SQLITE_OK, sqlite3_exec(db,
                                    "CREATE TABLE t(a INTEGER, b TEXT);"
                                    "INSERT INTO t VALUES (42, 'x');",
                                    nullptr, nullptr, &err));
  sqlite3_stmt* stmt = nullptr;
  ASSERT_EQ(SQLITE_OK, sqlite3_prepare_v2(db, "SELECT a, b FROM t", -1, &stmt, nullptr));
  ASSERT_EQ(SQLITE_ROW, sqlite3_step(stmt));
  EXPECT_EQ(42, sqlite3_column_int(stmt, 0));
  EXPECT_STREQ("x", reinterpret_cast<const char*>(sqlite3_column_text(stmt, 1)));
  sqlite3_finalize(stmt);
  sqlite3_close(db);
  std::cout << "[baseline] sqlite " << sqlite3_libversion() << std::endl;
}

TEST(VcpkgBaseline, AbseilStringsAndFormat) {
  const std::vector<std::string> parts = {"a", "b", "c"};
  EXPECT_EQ(absl::StrJoin(parts, "-"), "a-b-c");
  EXPECT_EQ(absl::StrFormat("%d/%s", 7, "x"), "7/x");
  std::cout << "[baseline] abseil（v8 内嵌同名库的另一份来源）" << std::endl;
}

TEST(VcpkgBaseline, HighwayAlignedAllocator) {
  auto p = hwy::AllocateAligned<float>(64);
  ASSERT_NE(p.get(), nullptr);
  for (size_t i = 0; i < 64; i++) p[i] = static_cast<float>(i);
  EXPECT_FLOAT_EQ(p[63], 63.0f);
  std::cout << "[baseline] highway（v8 内嵌同名库的另一份来源）" << std::endl;
}

TEST(VcpkgBaseline, HdrHistogramRecord) {
  hdr_histogram* h = nullptr;
  ASSERT_EQ(0, hdr_init(1, 100000, 3, &h));
  for (int i = 1; i <= 100; i++) hdr_record_value(h, i);
  EXPECT_GT(hdr_mean(h), 0.0);
  hdr_close(h);
  std::cout << "[baseline] hdr_histogram 记录 100 个样本 OK" << std::endl;
}

TEST(VcpkgBaseline, Nghttp2Version) {
  const nghttp2_info* info = nghttp2_version(0);
  ASSERT_NE(info, nullptr);
  EXPECT_STRNE(info->version_str, "");
  std::cout << "[baseline] nghttp2 " << info->version_str << std::endl;
}

TEST(VcpkgBaseline, IcuVersionAndUpper) {
  UVersionInfo ver{};
  u_getVersion(ver);
  icu::UnicodeString s = icu::UnicodeString::fromUTF8("stra\u00dfe");
  s.toUpper();
  std::string utf8;
  s.toUTF8String(utf8);
  EXPECT_FALSE(utf8.empty());
  std::cout << "[baseline] icu " << static_cast<int>(ver[0]) << "."
            << static_cast<int>(ver[1]) << std::endl;
}

TEST(VcpkgBaseline, FmtFormat) {
  EXPECT_EQ(fmt::format("{}-{}", 1, "x"), "1-x");
}
