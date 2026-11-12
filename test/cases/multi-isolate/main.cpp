// Two environments, two isolates, two event loops, one host thread that pumps both.
//
// The assertion has three parts: both scripts' timers fire during an iteration the host
// drove (not before it started pumping); each context holds only its own globals; and the
// two loops are distinct objects. Any one of these can pass while the others are broken in
// a library build that shares a global between isolates.
#include <node.h>
#include <uv.h>
#include <v8.h>

#include <cstdio>
#include <memory>
#include <string>
#include <vector>

namespace {

constexpr const char* kIteration = "__node_port_iteration";
constexpr const char* kDone = "__node_port_done";
constexpr const char* kOwnerMarker = "__node_port_owner_marker";
constexpr const char* kForeign = "__node_port_foreign";

struct Environment {
  char owner = 0;
  std::unique_ptr<node::CommonEnvironmentSetup> setup;
  v8::Isolate* isolate = nullptr;
  uv_loop_t* loop = nullptr;
  bool done = false;
  unsigned iterations = 0;
  int done_at = -1;
};

v8::Local<v8::String> Name(v8::Isolate* isolate, const char* text) {
  return v8::String::NewFromUtf8(isolate, text).ToLocalChecked();
}

void SetString(v8::Isolate* isolate, v8::Local<v8::Context> context,
               const char* name, const char* value) {
  v8::Local<v8::String> local = v8::String::NewFromUtf8(isolate, value).ToLocalChecked();
  context->Global()->Set(context, Name(isolate, name), local).Check();
}

void SetIteration(v8::Isolate* isolate, v8::Local<v8::Context> context, unsigned value) {
  context->Global()
      ->Set(context, Name(isolate, kIteration), v8::Integer::NewFromUnsigned(isolate, value))
      .Check();
}

// Returns -1 when the global is undefined, which is how "the timer has not fired yet" is
// distinguished from "the timer fired in iteration 0".
int ReadInt(v8::Isolate* isolate, v8::Local<v8::Context> context, const char* name) {
  v8::Local<v8::Value> value;
  if (!context->Global()->Get(context, Name(isolate, name)).ToLocal(&value) ||
      value->IsUndefined()) {
    return -1;
  }
  return value->Int32Value(context).FromMaybe(-1);
}

bool IsUndefined(v8::Isolate* isolate, v8::Local<v8::Context> context, const char* name) {
  v8::Local<v8::Value> value;
  return !context->Global()->Get(context, Name(isolate, name)).ToLocal(&value) ||
         value->IsUndefined();
}

std::string ReadString(v8::Isolate* isolate, v8::Local<v8::Context> context, const char* name) {
  v8::Local<v8::Value> value;
  if (!context->Global()->Get(context, Name(isolate, name)).ToLocal(&value) ||
      !value->IsString()) {
    return "";
  }
  v8::String::Utf8Value utf8(isolate, value);
  return *utf8 ? std::string(*utf8, static_cast<size_t>(utf8.length())) : std::string();
}

// One turn of one environment. Entering and leaving the isolate for every turn is what
// lets a single host thread own two isolates without nesting V8 lockers.
void Pump(Environment& env, node::MultiIsolatePlatform* platform) {
  if (env.done) return;
  v8::Isolate* isolate = env.isolate;
  v8::Locker locker(isolate);
  v8::Isolate::Scope isolate_scope(isolate);
  v8::HandleScope handle_scope(isolate);
  v8::Context::Scope context_scope(env.setup->context());
  v8::Local<v8::Context> context = env.setup->context();

  SetIteration(isolate, context, env.iterations);
  uv_run(env.loop, UV_RUN_NOWAIT);
  platform->DrainTasks(isolate);

  const int fired_at = ReadInt(isolate, context, kDone);
  if (fired_at >= 0) {
    env.done = true;
    env.done_at = fired_at;
  }
  ++env.iterations;
}

bool Load(Environment& env) {
  v8::Isolate* isolate = env.isolate;
  v8::Locker locker(isolate);
  v8::Isolate::Scope isolate_scope(isolate);
  v8::HandleScope handle_scope(isolate);
  v8::Context::Scope context_scope(env.setup->context());

  const std::string owner(1, env.owner);
  const std::string bootstrap =
      "globalThis.__node_port_owner = '" + owner + "';"
      "const publicRequire ="
      "  require('node:module').createRequire(process.cwd() + '/');"
      "globalThis.require = publicRequire;"
      "publicRequire(process.argv[1]);";
  // Only B gets this marker. Reading it back as undefined in A is the isolation check.
  if (env.owner == 'B') {
    SetString(isolate, env.setup->context(), kForeign, "only-in-B");
  }
  return !node::LoadEnvironment(env.setup->env(), bootstrap).IsEmpty();
}

}  // namespace

int main(int argc, char* argv[]) {
  if (argc < 2) {
    std::fprintf(stderr, "multi_isolate_error: usage: %s <script.cjs>\n", argv[0]);
    return 2;
  }

  std::vector<std::string> args(argv, argv + argc);
  std::shared_ptr<node::InitializationResult> initialization =
      node::InitializeOncePerProcess(
          args, {node::ProcessInitializationFlags::kNoInitializeV8,
                 node::ProcessInitializationFlags::kNoInitializeNodeV8Platform});
  for (const std::string& error : initialization->errors()) {
    std::fprintf(stderr, "multi_isolate_error: %s\n", error.c_str());
  }
  if (initialization->early_return() != 0) return initialization->exit_code();

  std::unique_ptr<node::MultiIsolatePlatform> platform =
      node::MultiIsolatePlatform::Create(4);
  v8::V8::InitializePlatform(platform.get());
  v8::V8::Initialize();

  Environment environments[2];
  int exit_code = 0;
  environments[0].owner = 'A';
  environments[1].owner = 'B';
  for (Environment& env : environments) {
    std::vector<std::string> errors;
    env.setup = node::CommonEnvironmentSetup::Create(platform.get(), &errors,
                                                     initialization->args(),
                                                     initialization->exec_args());
    if (!env.setup) {
      for (const std::string& error : errors) {
        std::fprintf(stderr, "multi_isolate_error: %s\n", error.c_str());
      }
      exit_code = 1;
      break;
    }
    env.isolate = env.setup->isolate();
    env.loop = reinterpret_cast<uv_loop_t*>(env.setup->event_loop());
  }

  if (exit_code == 0) {
    if (environments[0].isolate == environments[1].isolate ||
        environments[0].loop == environments[1].loop || environments[0].loop == nullptr ||
        environments[1].loop == nullptr) {
      std::fprintf(stderr, "multi_isolate_error: the two environments share an isolate or loop\n");
      exit_code = 1;
    }
  }

  if (exit_code == 0) {
    for (Environment& env : environments) {
      if (!Load(env)) {
        std::fprintf(stderr, "multi_isolate_error: LoadEnvironment failed in %c\n", env.owner);
        exit_code = 1;
      }
    }
  }

  if (exit_code == 0) {
    // A bounded pump: a timer that never fires fails the case instead of hanging ctest.
    for (unsigned turn = 0; turn < 1000 && exit_code == 0; ++turn) {
      for (Environment& env : environments) Pump(env, platform.get());
      if (environments[0].done && environments[1].done) break;
      uv_sleep(1);
    }

    for (Environment& env : environments) {
      if (!env.done || env.done_at != static_cast<int>(env.iterations - 1)) {
        std::fprintf(stderr,
                     "multi_isolate_error: environment %c timer never fired in a host "
                     "iteration (done=%d, at=%d, pumped=%u)\n",
                     env.owner, env.done ? 1 : 0, env.done_at, env.iterations);
        exit_code = 1;
      }
    }

    // Isolation: each context holds only the global its own script wrote, and the marker
    // the host put in B's context is absent from A's.
    for (Environment& env : environments) {
      v8::Locker locker(env.isolate);
      v8::Isolate::Scope isolate_scope(env.isolate);
      v8::HandleScope handle_scope(env.isolate);
      v8::Context::Scope context_scope(env.setup->context());
      const std::string marker = ReadString(env.isolate, env.setup->context(), kOwnerMarker);
      if (marker != std::string(1, env.owner)) {
        std::fprintf(stderr, "multi_isolate_error: environment %c saw owner marker '%s'\n",
                     env.owner, marker.c_str());
        exit_code = 1;
      }
      if (env.owner == 'A' && !IsUndefined(env.isolate, env.setup->context(), kForeign)) {
        std::fprintf(stderr, "multi_isolate_error: B's global leaked into A's context\n");
        exit_code = 1;
      }
      node::Stop(env.setup->env());
    }
  }

  for (Environment& env : environments) env.setup.reset();
  v8::V8::Dispose();
  v8::V8::DisposePlatform();
  platform.reset();
  node::TearDownOncePerProcess();

  if (exit_code == 0) {
    std::printf("multi-isolate: 2 isolates, 2 loops, both pumped\n");
  }
  return exit_code;
}
