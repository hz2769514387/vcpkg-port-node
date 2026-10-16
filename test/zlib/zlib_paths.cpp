// The C half of the cross-path zlib check, in two stages.
//
// This is the consumer-side verification the zlib decision calls for: the same input pushed
// through zlib's C API and through Node.js's own compression, in one process each, with both
// directions of the round trip checked. Node.js links vcpkg's zlib through `--shared-zlib`, so
// the two paths should be the same library - and "the same library" is exactly what a version
// string cannot prove on its own.
//
// Two stages, because they are separated by something that cannot be inside one process: the
// runtime has to run the JavaScript, and an embedded runtime ends the process when its script
// ends. So:
//
//   prepare <workdir>   compress a deterministic input with the C API and record what it saw
//   verify  <workdir>   inflate what the runtime compressed, and compare everything the runtime
//                       wrote against what this process recorded
//
// In between, the consumer-linked runtime (the embedder, which is what a real host looks like)
// runs zlib_paths.js against the same workdir.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <vector>

#include <zlib.h>

namespace {

constexpr size_t kInputSize = 256 * 1024;

bool ReadFile(const std::string& path, std::vector<unsigned char>* out) {
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) {
    std::fprintf(stderr, "zlib_paths: cannot read %s\n", path.c_str());
    return false;
  }
  std::fseek(f, 0, SEEK_END);
  long size = std::ftell(f);
  std::fseek(f, 0, SEEK_SET);
  out->resize(static_cast<size_t>(size));
  size_t read = std::fread(out->data(), 1, out->size(), f);
  std::fclose(f);
  if (read != out->size()) {
    std::fprintf(stderr, "zlib_paths: short read on %s\n", path.c_str());
    return false;
  }
  return true;
}

bool WriteFile(const std::string& path, const void* data, size_t size) {
  FILE* f = std::fopen(path.c_str(), "wb");
  if (!f) {
    std::fprintf(stderr, "zlib_paths: cannot write %s\n", path.c_str());
    return false;
  }
  bool ok = std::fwrite(data, 1, size, f) == size;
  std::fclose(f);
  return ok;
}

// Deterministic, compressible, and not trivially so, so a compressor has real work to do and
// both stages see the same bytes every run.
std::vector<unsigned char> MakeInput() {
  std::vector<unsigned char> data(kInputSize);
  unsigned int state = 0x1234abcd;
  for (size_t i = 0; i < data.size(); i++) {
    state = state * 1103515245u + 12345u;
    data[i] = static_cast<unsigned char>(((state >> 17) & 0x1f) + (i / 97) % 5);
  }
  return data;
}

unsigned char HexDigit(unsigned int value) {
  return static_cast<unsigned char>(value < 10 ? '0' + value : 'a' + (value - 10));
}

std::string ToHex(unsigned long value) {
  std::string out(8, '0');
  for (int i = 7; i >= 0; i--) {
    out[static_cast<size_t>(i)] = static_cast<char>(HexDigit(value & 0xf));
    value >>= 4;
  }
  return out;
}

// A tiny key=value file, and a tiny parser for it. No JSON dependency, no escaping questions.
bool ReadMeta(const std::string& path, std::string* version, std::string* crc32_hex) {
  std::vector<unsigned char> raw;
  if (!ReadFile(path, &raw)) {
    return false;
  }
  std::string text(raw.begin(), raw.end());
  size_t at = 0;
  while (at < text.size()) {
    size_t end = text.find('\n', at);
    if (end == std::string::npos) {
      end = text.size();
    }
    std::string line = text.substr(at, end - at);
    size_t eq = line.find('=');
    if (eq != std::string::npos) {
      const std::string key = line.substr(0, eq);
      const std::string value = line.substr(eq + 1);
      if (key == "version") {
        *version = value;
      } else if (key == "crc32") {
        *crc32_hex = value;
      }
    }
    at = end + 1;
  }
  return true;
}

int Prepare(const std::string& workdir) {
  // The runtime side's outputs are removed here, not merely overwritten later: if the runtime
  // stage did not run, the verify stage has to fail on a missing file rather than read last
  // run's evidence and pass.
  std::remove((workdir + "/n.deflate").c_str());
  std::remove((workdir + "/n.meta").c_str());

  const std::vector<unsigned char> input = MakeInput();
  unsigned long crc = crc32(0L, Z_NULL, 0);
  crc = crc32(crc, input.data(), static_cast<uInt>(input.size()));

  uLongf bound = compressBound(static_cast<uLong>(input.size()));
  std::vector<unsigned char> deflated(bound);
  uLongf deflated_len = bound;
  if (compress2(deflated.data(), &deflated_len, input.data(),
                static_cast<uLong>(input.size()), 6) != Z_OK) {
    std::fprintf(stderr, "zlib_paths: the C library could not compress the input\n");
    return 1;
  }
  deflated.resize(deflated_len);

  if (!WriteFile(workdir + "/input.bin", input.data(), input.size()) ||
      !WriteFile(workdir + "/c.deflate", deflated.data(), deflated.size())) {
    return 1;
  }
  const std::string meta = "version=" + std::string(zlibVersion()) + "\n" +
                           "crc32=" + ToHex(crc) + "\n" +
                           "input_size=" + std::to_string(input.size()) + "\n" +
                           "c_deflate_size=" + std::to_string(deflated.size()) + "\n";
  if (!WriteFile(workdir + "/c.meta", meta.data(), meta.size())) {
    return 1;
  }

  std::printf("zlib_paths[prepare]: C path used zlib %s, %zu -> %zu bytes, crc32 %s\n",
              zlibVersion(), input.size(), deflated.size(), ToHex(crc).c_str());
  if (std::strstr(zlibVersion(), "motley") == nullptr) {
    std::fprintf(stderr,
                 "zlib_paths[prepare]: the C consumer is linked against zlib %s, which is not "
                 "the Chromium fork; the overlay port is not in play\n",
                 zlibVersion());
    return 1;
  }
  return 0;
}

int Verify(const std::string& workdir) {
  std::vector<unsigned char> input;
  std::vector<unsigned char> node_deflated;
  if (!ReadFile(workdir + "/input.bin", &input) ||
      !ReadFile(workdir + "/n.deflate", &node_deflated)) {
    return 1;
  }

  std::string c_version;
  std::string c_crc;
  std::string node_version;
  std::string node_crc;
  if (!ReadMeta(workdir + "/c.meta", &c_version, &c_crc) ||
      !ReadMeta(workdir + "/n.meta", &node_version, &node_crc)) {
    return 1;
  }

  int failures = 0;
  auto check = [&failures](bool condition, const std::string& description) {
    std::printf("%s  %s\n", condition ? "ok   " : "FAIL ", description.c_str());
    if (!condition) {
      failures++;
    }
  };

  // 1. The runtime's zlib is the fork. This is what the overlay port exists for.
  check(node_version.find("motley") != std::string::npos,
        "the runtime reports the Chromium fork (" + node_version + ")");
  check(c_version.find("motley") != std::string::npos,
        "the C consumer reports the Chromium fork (" + c_version + ")");

  // 2. The other direction from the runtime's own check: the C API inflates what Node.js
  //    compressed, and gets the input back.
  std::vector<unsigned char> inflated(input.size() + 1);
  uLongf inflated_len = static_cast<uLongf>(inflated.size());
  const int rc = uncompress(inflated.data(), &inflated_len, node_deflated.data(),
                            static_cast<uLong>(node_deflated.size()));
  check(rc == Z_OK, "uncompress() accepted the runtime's output");
  if (rc == Z_OK) {
    check(inflated_len == input.size(), "the inflated size matches the input");
    check(std::memcmp(inflated.data(), input.data(), input.size()) == 0,
          "the C API recovers the input from the runtime's output");
  }

  // 3. Both paths, same input, same crc32 - computed by different implementations if the port
  //    ever stopped externalizing zlib.
  check(node_crc == c_crc, "both paths compute the same crc32 (" + node_crc + ")");

  if (failures > 0) {
    std::fprintf(stderr, "zlib_paths[verify]: %d check(s) failed\n", failures);
    return 1;
  }
  std::printf("zlib_paths[verify]: both paths agree\n");
  return 0;
}

}  // namespace

int main(int argc, char* argv[]) {
  if (argc < 3) {
    std::fprintf(stderr, "usage: %s prepare|verify <workdir>\n", argv[0]);
    return 2;
  }
  const std::string mode = argv[1];
  const std::string workdir = argv[2];
  std::error_code fs_error;
  std::filesystem::create_directories(workdir, fs_error);
  if (fs_error) {
    std::fprintf(stderr, "zlib_paths: cannot create %s (%s)\n", workdir.c_str(),
                 fs_error.message().c_str());
    return 2;
  }
  if (mode == "prepare") {
    return Prepare(workdir);
  }
  if (mode == "verify") {
    return Verify(workdir);
  }
  std::fprintf(stderr, "zlib_paths: unknown mode '%s'\n", mode.c_str());
  return 2;
}
