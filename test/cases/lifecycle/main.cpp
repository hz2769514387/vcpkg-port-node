// Three Node.js environments, created and destroyed one after another on one V8 platform.
//
// The claim is not merely "the script ran three times". Each environment registers two hooks:
// an environment cleanup hook (run when that setup is destroyed) and an AtExit hook (run when
// that environment is freed). If the host's global state were one-shot, the second and third
// environments would fail to create; if the hooks were registered on the process rather than
// on the environment, their counts would be 1 instead of 3.
//
// The script is loaded with CommonEnvironmentSetup / LoadEnvironment / SpinEventLoop rather
// than node::Start, because node::Start owns the process and cannot be called twice.
#include <node.h>
#include <v8.h>

#include <cstdint>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

namespace {

constexpr int kRounds = 3;
constexpr const char* kRanGlobal = "__node_port_round_ran";

struct HookRecord {
  int round;
  bool is_cleanup;
};

std::vector<HookRecord> g_hooks;

void* RoundArg(int round) {
  return reinterpret_cast<void*>(static_cast<intptr_t>(round));
}

int RoundFromArg(void* arg) {
  return static_cast<int>(reinterpret_cast<intptr_t>(arg));
}

void CleanupHook(void* arg) {
  g_hooks.push_back({RoundFromArg(arg), true});
  std::printf("lifecycle: cleanup hook for environment %d\n", RoundFromArg(arg));
}

void AtExitHook(void* arg) {
  g_hooks.push_back({RoundFromArg(arg), false});
  std::printf("lifecycle: at-exit hook for environment %d\n", RoundFromArg(arg));
}

v8::Local<v8::String> Name(v8::Isolate* isolate, const char* text) {
  return v8::String::NewFromUtf8(isolate, text).ToLocalChecked();
}

}  // namespace

int main(int argc, char* argv[]) {
  if (argc < 2) {
    std::fprintf(stderr, "lifecycle_error: usage: %s <script.cjs>\n", argv[0]);
    return 2;
  }

  std::vector<std::string> args(argv, argv + argc);
  std::shared_ptr<node::InitializationResult> initialization =
      node::InitializeOncePerProcess(
          args, {node::ProcessInitializationFlags::kNoInitializeV8,
                 node::ProcessInitializationFlags::kNoInitializeNodeV8Platform});
  for (const std::string& error : initialization->errors()) {
    std::fprintf(stderr, "lifecycle_error: %s\n", error.c_str());
  }
  if (initialization->early_return() != 0) {
    return initialization->exit_code();
  }

  std::unique_ptr<node::MultiIsolatePlatform> platform =
      node::MultiIsolatePlatform::Create(4);
  v8::V8::InitializePlatform(platform.get());
  v8::V8::Initialize();

  int environments = 0;
  int exit_code = 0;
  for (int round = 1; round <= kRounds && exit_code == 0; ++round) {
    std::vector<std::string> errors;
    std::unique_ptr<node::CommonEnvironmentSetup> setup =
        node::CommonEnvironmentSetup::Create(platform.get(), &errors,
                                             initialization->args(),
                                             initialization->exec_args());
    if (!setup) {
      for (const std::string& error : errors) {
        std::fprintf(stderr, "lifecycle_error: %s\n", error.c_str());
      }
      exit_code = 1;
      break;
    }

    v8::Isolate* isolate = setup->isolate();

    {
      v8::Locker locker(isolate);
      v8::Isolate::Scope isolate_scope(isolate);
      v8::HandleScope handle_scope(isolate);
      v8::Context::Scope context_scope(setup->context());

      // AddEnvironmentCleanupHook looks the Environment up from the isolate, so it has to
      // be called with the isolate (and its context) entered. Calling it outside this scope
      // aborts inside hooks.cc with "Assertion failed: (env) != nullptr".
      node::AddEnvironmentCleanupHook(isolate, &CleanupHook, RoundArg(round));
      node::AtExit(setup->env(), &AtExitHook, RoundArg(round));

      // The round number is put on the global so the script can prove it ran in this
      // environment, not in a previous one that was never torn down.
      const std::string bootstrap =
          "globalThis.__node_port_round = " + std::to_string(round) + ";"
          "const publicRequire ="
          "  require('node:module').createRequire(process.cwd() + '/');"
          "globalThis.require = publicRequire;"
          "publicRequire(process.argv[1]);";
      if (node::LoadEnvironment(setup->env(), bootstrap).IsEmpty()) {
        std::fprintf(stderr, "lifecycle_error: LoadEnvironment failed in round %d\n", round);
        exit_code = 1;
      } else {
        v8::Local<v8::Context> context = setup->context();
        v8::Local<v8::Value> value;
        const bool ran =
            context->Global()->Get(context, Name(isolate, kRanGlobal)).ToLocal(&value) &&
            value->IsTrue();
        if (!ran) {
          std::fprintf(stderr, "lifecycle_error: the script did not run in round %d\n", round);
          exit_code = 1;
        } else if (node::SpinEventLoop(setup->env()).FromMaybe(1) != 0) {
          std::fprintf(stderr, "lifecycle_error: the loop failed in round %d\n", round);
          exit_code = 1;
        }
      }
      node::Stop(setup->env());
    }

    // Destroying the setup here, before the next one is created, is what runs both hooks.
    setup.reset();
    ++environments;
  }

  v8::V8::Dispose();
  v8::V8::DisposePlatform();
  platform.reset();
  node::TearDownOncePerProcess();

  int cleanup_hooks = 0;
  int at_exit_hooks = 0;
  for (const HookRecord& record : g_hooks) {
    if (record.is_cleanup) ++cleanup_hooks;
    else ++at_exit_hooks;
    if (record.round < 1 || record.round > kRounds) {
      std::fprintf(stderr, "lifecycle_error: a hook reported round %d\n", record.round);
      exit_code = 1;
    }
  }
  // Cleanup hooks run before AtExit hooks within each environment; three environments in
  // sequence therefore give this exact interleaving. A hook registered on the process
  // would give one of each, not three.
  bool order_ok = g_hooks.size() == 2 * static_cast<size_t>(kRounds);
  if (order_ok) {
    for (int round = 1; round <= kRounds; ++round) {
      const HookRecord& cleanup = g_hooks[2 * (round - 1)];
      const HookRecord& at_exit = g_hooks[2 * (round - 1) + 1];
      if (cleanup.round != round || !cleanup.is_cleanup ||
          at_exit.round != round || at_exit.is_cleanup) {
        order_ok = false;
      }
    }
  }
  if (!order_ok || cleanup_hooks != kRounds || at_exit_hooks != kRounds) {
    std::fprintf(stderr,
                 "lifecycle_error: hook order or count is wrong (%d cleanup, %d at-exit)\n",
                 cleanup_hooks, at_exit_hooks);
    exit_code = 1;
  }

  if (exit_code == 0) {
    std::printf("lifecycle: %d environments, %d cleanup hooks, %d at-exit hooks\n",
                environments, cleanup_hooks, at_exit_hooks);
  }
  return exit_code;
}
