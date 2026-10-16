// One process, both sides of the same libraries.
//
// The port externalizes abseil, highway, simdutf and zlib: Node.js's own artifacts are
// compiled against the vcpkg copies, so a consumer that links those same libraries ends up
// with exactly one definition of each in a single process. This program is the proof: it
// calls into each library directly, then hands a script to the Node.js runtime built from
// the same tree, in the same process.
//
// If the two sides ever disagree - a different inline namespace (abseil's lts_20260107), a
// different C++ standard (simdutf's atomic_* functions need C++20), a different set of
// compile definitions - this stops linking or stops working right here, instead of in a
// consumer's bug report.
#include <node.h>

#include <cstdio>

#include <absl/strings/str_cat.h>
#include <hwy/highway.h>
#include <openssl/evp.h>
#include <simdutf.h>
#include <zlib.h>

int main(int argc, char* argv[]) {
  // abseil: the library V8 would otherwise compile into itself. StrCat is enough to prove
  // the headers and the archive agree.
  const std::string joined = absl::StrCat("abseil ", "agrees");
  // highway: ditto, through a runtime query rather than a vector intrinsic, so the test
  // does not depend on the target CPU.
  const int64_t highway_targets = hwy::SupportedTargets();
  // simdutf: the one where a C++ standard mismatch would show up as a missing symbol.
  const bool simdutf_ok = simdutf::validate_utf8("simdutf agrees", 15);
  // OpenSSL and zlib: both externalized, both needed by the runtime that follows. The local
  // variable must not be called zlib_version: zlib.h defines that name as a macro for
  // compatibility with versions before 1.0.2, and the collision surfaces as a syntax error
  // on the '=' rather than as anything the compiler explains.
  const int digest_size = EVP_MD_size(EVP_sha256());
  const char* zlib_runtime_version = zlibVersion();

  std::printf("coexist: %s\n", joined.c_str());
  std::printf("coexist: highway targets 0x%llx\n",
              static_cast<unsigned long long>(highway_targets));
  std::printf("coexist: simdutf validates utf8: %s\n", simdutf_ok ? "yes" : "no");
  std::printf("coexist: sha256 digest size %d\n", digest_size);
  std::printf("coexist: zlib %s\n", zlib_runtime_version);

  if (!simdutf_ok || digest_size != 32 || highway_targets == 0) {
    std::fprintf(stderr, "coexist: one of the externalized libraries misbehaved\n");
    return 1;
  }

  // And the runtime, in the same process, on the same link line.
  return node::Start(argc, argv);
}
