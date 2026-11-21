// The embedder snapshot API: build a snapshot, then start an environment from it.
//
// `cases/snapshot` asserts the *built-in* snapshot artefact (node_use_node_snapshot). This case
// is the other half of the embedding API: CommonEnvironmentSetup::CreateForSnapshotting /
// CreateSnapshot / CreateFromSnapshot, which `docs/consumer-recipes.md` did not cover and
// `cases/snapshot` cannot see. A product uses it to move its own bootstrap JavaScript out of
// startup, the way Electron does.
//
// Two modes, because Node.js requires every setup in one process to use the same snapshot, so
// building and consuming cannot share a process:
//
//   embedder_snapshot build <blob>    CreateForSnapshotting, run the builder script, CreateSnapshot
//   embedder_snapshot consume <blob>  FromBlob, CreateFromSnapshot, read the marker
//
// The marker is a string the builder script assigns to a global; a snapshot that silently
// contained nothing would fail the read rather than pass on an empty value.

#include <node.h>
#include <v8.h>

#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <memory>
#include <string>
#include <vector>

namespace {

const char* kBuilderScript = R"JS(
  if (!require('v8').startupSnapshot.isBuildingSnapshot()) {
    throw new Error('not building a snapshot');
  }
  globalThis.__snapshot_marker = 'from-snapshot';
  globalThis.__snapshot_number = 42;
)JS";

std::vector<char> ReadFile(const char* path) {
  std::ifstream file(path, std::ios::binary);
  if (!file) return {};
  return std::vector<char>(std::istreambuf_iterator<char>(file),
                           std::istreambuf_iterator<char>());
}

bool WriteFile(const char* path, const std::vector<char>& data) {
  std::ofstream file(path, std::ios::binary);
  if (!file) return false;
  file.write(data.data(), static_cast<std::streamsize>(data.size()));
  return file.good();
}

int InitializeProcess(int argc, char** argv) {
  std::vector<std::string> raw_args(argv, argv + argc);
  // The two custom arguments are not Node.js CLI flags; without this the parser would reject
  // them as "bad option" (measured) instead of leaving them in process.argv.
  std::vector<std::string> filtered_args = {raw_args[0]};
  std::shared_ptr<node::InitializationResult> initialization =
      node::InitializeOncePerProcess(
          filtered_args, {node::ProcessInitializationFlags::kNoInitializeV8,
                          node::ProcessInitializationFlags::kNoInitializeNodeV8Platform,
                          node::ProcessInitializationFlags::kDisableCLIOptions});
  for (const std::string& error : initialization->errors()) {
    std::fprintf(stderr, "embedder_snapshot_error: %s\n", error.c_str());
  }
  return initialization->early_return();
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 3) {
    std::fprintf(stderr, "usage: embedder_snapshot build|consume <blob>\n");
    return 2;
  }
  const bool build = std::strcmp(argv[1], "build") == 0;
  const char* blob_path = argv[2];

  const int early = InitializeProcess(argc, argv);
  if (early != 0) return early;

  std::unique_ptr<node::MultiIsolatePlatform> platform =
      node::MultiIsolatePlatform::Create(4);
  v8::V8::InitializePlatform(platform.get());
  v8::V8::Initialize();

  // The builder runs its script under the name GetAnonymousMainPath() returns, so no
  // build-machine path ends up in the snapshot. A consumer must pass no second argument: with
  // one, StartExecution treats it as a main module and tries to run it (measured:
  // "Cannot find module .../__node_anonymous_main").
  std::vector<std::string> args =
      build ? std::vector<std::string>{"embedder_snapshot", node::GetAnonymousMainPath()}
            : std::vector<std::string>{"embedder_snapshot"};
  std::vector<std::string> exec_args;
  std::vector<std::string> errors;
  int exit_code = 1;

  if (build) {
    // A fixture that did not run must leave consume with nothing to read, rather than a blob
    // from a previous invocation of a reused build directory.
    std::remove(blob_path);
    std::unique_ptr<node::CommonEnvironmentSetup> setup =
        node::CommonEnvironmentSetup::CreateForSnapshotting(platform.get(), &errors, args,
                                                            exec_args);
    if (!setup) {
      for (const std::string& error : errors) {
        std::fprintf(stderr, "embedder_snapshot_error: %s\n", error.c_str());
      }
      return 1;
    }
    v8::Isolate* isolate = setup->isolate();
    {
      v8::Locker locker(isolate);
      v8::Isolate::Scope isolate_scope(isolate);
      v8::HandleScope handle_scope(isolate);
      v8::Context::Scope context_scope(setup->context());
      if (node::LoadEnvironment(setup->env(), kBuilderScript).IsEmpty()) {
        std::fprintf(stderr, "embedder_snapshot_error: the builder script failed\n");
        node::Stop(setup->env());
        return 1;
      }
      const int spin = node::SpinEventLoop(setup->env()).FromMaybe(1);
      if (spin != 0) {
        std::fprintf(stderr, "embedder_snapshot_error: SpinEventLoop returned %d\n", spin);
        node::Stop(setup->env());
        return 1;
      }
      node::EmbedderSnapshotData::Pointer snapshot = setup->CreateSnapshot();
      if (!snapshot) {
        std::fprintf(stderr, "embedder_snapshot_error: CreateSnapshot returned null\n");
        node::Stop(setup->env());
        return 1;
      }
      const std::vector<char> blob = snapshot->ToBlob();
      if (blob.empty() || !WriteFile(blob_path, blob)) {
        std::fprintf(stderr, "embedder_snapshot_error: could not write %s\n", blob_path);
        node::Stop(setup->env());
        return 1;
      }
      std::printf("embedder_snapshot: built %zu bytes\n", blob.size());
      exit_code = 0;
      node::Stop(setup->env());
    }
  } else {
    const std::vector<char> blob = ReadFile(blob_path);
    if (blob.empty()) {
      std::fprintf(stderr, "embedder_snapshot_error: could not read %s\n", blob_path);
      return 1;
    }
    node::EmbedderSnapshotData::Pointer snapshot =
        node::EmbedderSnapshotData::FromBlob(blob);
    if (!snapshot) {
      std::fprintf(stderr, "embedder_snapshot_error: FromBlob rejected the blob\n");
      return 1;
    }
    std::unique_ptr<node::CommonEnvironmentSetup> setup =
        node::CommonEnvironmentSetup::CreateFromSnapshot(platform.get(), &errors,
                                                         snapshot.get(), args, exec_args);
    if (!setup) {
      for (const std::string& error : errors) {
        std::fprintf(stderr, "embedder_snapshot_error: %s\n", error.c_str());
      }
      return 1;
    }
    v8::Isolate* isolate = setup->isolate();
    {
      v8::Locker locker(isolate);
      v8::Isolate::Scope isolate_scope(isolate);
      v8::HandleScope handle_scope(isolate);
      v8::Local<v8::Context> context = setup->context();
      v8::Context::Scope context_scope(context);
      if (node::LoadEnvironment(setup->env(), node::StartExecutionCallback{}).IsEmpty()) {
        std::fprintf(stderr, "embedder_snapshot_error: deserialization failed\n");
        node::Stop(setup->env());
        return 1;
      }
      v8::Local<v8::Value> marker;
      if (!context->Global()
               ->Get(context, v8::String::NewFromUtf8Literal(isolate, "__snapshot_marker"))
               .ToLocal(&marker) ||
          !marker->IsString()) {
        std::fprintf(stderr, "embedder_snapshot_error: the snapshot carries no marker\n");
      } else {
        v8::String::Utf8Value text(isolate, marker);
        const char* value = *text ? *text : "";
        std::printf("embedder_snapshot: marker=%s\n", value);
        exit_code = std::strcmp(value, "from-snapshot") == 0 ? 0 : 1;
        if (exit_code != 0) {
          std::fprintf(stderr, "embedder_snapshot_error: marker was '%s'\n", value);
        }
      }
      // The builder writes a number too. A build that serialised the string but lost numeric
      // values (or Smi encoding) would pass on the marker alone.
      v8::Local<v8::Value> number;
      if (!context->Global()
               ->Get(context, v8::String::NewFromUtf8Literal(isolate, "__snapshot_number"))
               .ToLocal(&number) ||
          !number->IsNumber() || number->Int32Value(context).FromMaybe(-1) != 42) {
        std::fprintf(stderr, "embedder_snapshot_error: the snapshot has no numeric marker\n");
        exit_code = 1;
      } else {
        std::printf("embedder_snapshot: number=42\n");
      }
      node::Stop(setup->env());
    }
  }

  return exit_code;
}
