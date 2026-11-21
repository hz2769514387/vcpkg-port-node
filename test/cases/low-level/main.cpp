// The lower-level environment path, and what EnvironmentFlags::kNoBrowserGlobals really removes.
//
// CommonEnvironmentSetup takes no EnvironmentFlags, so a host that needs one has to go through
// NewIsolate / CreateIsolateData / CreateEnvironment - the same path IsolateSettings would be
// passed through. This case verifies that path is callable against this install and pins the
// measured effect of kNoBrowserGlobals; it does not exercise the IsolateSettings callbacks. The
// header's comment ("browser globals like setTimeout, console, etc.") is not what the runtime
// does: console survives, setImmediate survives, and fetch/setTimeout/queueMicrotask do not. A
// product that relies on the comment instead of this table gets either a missing timer or a
// global it thought it had suppressed.
//
// Two ctest cases run this binary: the default is kNoBrowserGlobals, and the env var asks for
// kDefaultFlags so the difference is measured rather than assumed.

#include <node.h>
#include <uv.h>
#include <v8.h>

#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <vector>

namespace {

// `return` matters: a CommonJS module body without one evaluates to undefined, which is a
// perfectly valid MaybeLocal and not an error. The first version of this probe treated
// "not a string" as a failure and reported the low-level path as broken.
const char* kScript = R"JS(
  const type_of = (name) => typeof globalThis[name];
  return ['fetch', 'console', 'setTimeout', 'setImmediate', 'queueMicrotask', 'process',
          'Buffer']
      .map((name) => name + '=' + type_of(name))
      .join('\n');
)JS";

struct Expectation {
  const char* name;
  const char* with_browser_globals;
  const char* without_browser_globals;
};

// Measured on the pinned 26.13.x tree with this port's install (x64 Windows static).
const Expectation kExpected[] = {
    {"fetch", "function", "undefined"},
    {"console", "object", "object"},
    {"setTimeout", "function", "undefined"},
    {"setImmediate", "function", "function"},
    {"queueMicrotask", "function", "undefined"},
    {"process", "object", "object"},
    {"Buffer", "function", "function"},
};

// getenv is deprecated by the MSVC CRT (C4996); _dupenv_s is its replacement and needs the
// matching free. Kept to one helper so the Windows branch does not leak into the case.
bool EnvironmentVariableIsSet(const char* name) {
#ifdef _WIN32
  char* value = nullptr;
  size_t length = 0;
  const bool set = _dupenv_s(&value, &length, name) == 0 && value != nullptr;
  std::free(value);
  return set;
#else
  return std::getenv(name) != nullptr;
#endif
}

}  // namespace

int main() {
  const bool default_flags = EnvironmentVariableIsSet("NODE_PORT_TEST_DEFAULT_GLOBALS");

  std::vector<std::string> args = {"low_level"};
  std::shared_ptr<node::InitializationResult> initialization =
      node::InitializeOncePerProcess(
          args, {node::ProcessInitializationFlags::kNoInitializeV8,
                 node::ProcessInitializationFlags::kNoInitializeNodeV8Platform});
  for (const std::string& error : initialization->errors()) {
    std::fprintf(stderr, "low_level: %s\n", error.c_str());
  }
  if (initialization->early_return() != 0) {
    return initialization->exit_code();
  }

  std::unique_ptr<node::MultiIsolatePlatform> platform =
      node::MultiIsolatePlatform::Create(4);
  v8::V8::InitializePlatform(platform.get());
  v8::V8::Initialize();

  uv_loop_t loop;
  if (uv_loop_init(&loop) != 0) {
    std::fprintf(stderr, "low_level: uv_loop_init failed\n");
    return 1;
  }
  std::shared_ptr<node::ArrayBufferAllocator> allocator =
      node::ArrayBufferAllocator::Create();
  v8::Isolate* isolate = node::NewIsolate(allocator, &loop, platform.get());

  int exit_code = 1;
  std::string observed;
  {
    v8::Locker locker(isolate);
    v8::Isolate::Scope isolate_scope(isolate);
    v8::HandleScope handle_scope(isolate);
    v8::Local<v8::Context> context = node::NewContext(isolate);
    v8::Context::Scope context_scope(context);

    node::IsolateData* isolate_data =
        node::CreateIsolateData(isolate, &loop, platform.get(), allocator.get());
    node::Environment* env = node::CreateEnvironment(
        isolate_data, context, initialization->args(), initialization->exec_args(),
        default_flags ? node::EnvironmentFlags::kDefaultFlags
                      : node::EnvironmentFlags::kNoBrowserGlobals);
    if (env == nullptr) {
      std::fprintf(stderr, "low_level: CreateEnvironment returned nullptr\n");
    } else {
      v8::Local<v8::Value> value;
      v8::MaybeLocal<v8::Value> loaded = node::LoadEnvironment(env, kScript);
      if (!loaded.ToLocal(&value)) {
        std::fprintf(stderr, "low_level: LoadEnvironment returned empty\n");
      } else if (!value->IsString()) {
        std::fprintf(stderr, "low_level: the script did not return a string\n");
      } else {
        v8::String::Utf8Value text(isolate, value);
        observed = *text ? *text : "";
        exit_code = 0;
      }
      node::Stop(env);
      node::FreeEnvironment(env);
    }
    node::FreeIsolateData(isolate_data);
  }

  if (exit_code == 0) {
    std::printf("low_level flags=%s\n", default_flags ? "default" : "noBrowserGlobals");
    size_t position = 0;
    for (const Expectation& expectation : kExpected) {
      const std::string prefix = std::string(expectation.name) + "=";
      const size_t start = observed.find(prefix, position);
      if (start == std::string::npos) {
        std::fprintf(stderr, "low_level: no value for %s\n", expectation.name);
        exit_code = 1;
        continue;
      }
      const size_t value_start = start + prefix.size();
      const size_t end = observed.find('\n', value_start);
      const std::string actual =
          observed.substr(value_start, end == std::string::npos ? std::string::npos
                                                               : end - value_start);
      position = end == std::string::npos ? observed.size() : end;
      const char* expected = default_flags ? expectation.with_browser_globals
                                           : expectation.without_browser_globals;
      std::printf("  %s = %s (expected %s)\n", expectation.name, actual.c_str(), expected);
      if (actual != expected) {
        std::fprintf(stderr, "low_level: %s is '%s', expected '%s'\n", expectation.name,
                     actual.c_str(), expected);
        exit_code = 1;
      }
    }
  }

  // The low-level path closes its own handles; an unconditional UV_RUN_ONCE loop hangs when one
  // never becomes closable.
  platform->DisposeIsolate(isolate);
  uv_stop(&loop);
  uv_walk(&loop, [](uv_handle_t* handle, void*) {
    if (!uv_is_closing(handle)) uv_close(handle, nullptr);
  }, nullptr);
  for (int i = 0; i < 1000 && uv_loop_alive(&loop); ++i) uv_run(&loop, UV_RUN_NOWAIT);
  const int close_result = uv_loop_close(&loop);
  if (close_result != 0) {
    std::fprintf(stderr, "low_level: uv_loop_close returned %d\n", close_result);
    exit_code = 1;
  }
  v8::V8::Dispose();
  v8::V8::DisposePlatform();
  node::TearDownOncePerProcess();
  return exit_code;
}
