// The host owns the event loop.
//
// `node::SpinEventLoop` hands the loop to the runtime: the host sits inside node's loop until
// there is nothing left to do. A UI toolkit or a service loop cannot work that way - it owns
// the main thread and pumps its own queue. The arrangement those hosts need is the other way
// round: the host creates the environment, then calls `uv_run(loop, UV_RUN_NOWAIT)` from its
// own loop, interleaving node's callbacks with its own work and yielding between them.
//
// `test/embedding/thread_loop` covers "the runtime runs on a thread the host owns, pumping
// itself". This one covers "the host pumps the loop", which is the path a host that keeps
// its main thread has to use, and which nothing else in the suite executes.
//
// The assertion is that the script's timer fires *inside* a host-driven `uv_run` iteration:
// the host stamps each iteration into a context global, the script records which stamp it saw,
// and the host checks the recorded value against its own loop counter.
#include <node.h>
#include <uv.h>
#include <v8.h>

#include <cstdio>
#include <memory>
#include <string>
#include <vector>

namespace {

constexpr const char* kIterationGlobal = "__node_port_host_iteration";
constexpr const char* kFiredGlobal = "__node_port_fired_at";

v8::Local<v8::String> Name(v8::Isolate* isolate, const char* text) {
  return v8::String::NewFromUtf8(isolate, text).ToLocalChecked();
}

}  // namespace

int main(int argc, char* argv[]) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s <script.js>\n", argv[0]);
    return 2;
  }

  // The host decides when V8 and node's platform come up, exactly as in thread_loop.
  std::vector<std::string> args(argv, argv + argc);
  std::shared_ptr<node::InitializationResult> initialization =
      node::InitializeOncePerProcess(
          args, {node::ProcessInitializationFlags::kNoInitializeV8,
                 node::ProcessInitializationFlags::kNoInitializeNodeV8Platform});
  for (const std::string& error : initialization->errors()) {
    std::fprintf(stderr, "host_loop: %s\n", error.c_str());
  }
  if (initialization->early_return() != 0) {
    return initialization->exit_code();
  }

  std::unique_ptr<node::MultiIsolatePlatform> platform =
      node::MultiIsolatePlatform::Create(4);
  v8::V8::InitializePlatform(platform.get());
  v8::V8::Initialize();

  std::vector<std::string> errors;
  std::unique_ptr<node::CommonEnvironmentSetup> setup =
      node::CommonEnvironmentSetup::Create(platform.get(), &errors,
                                           initialization->args(),
                                           initialization->exec_args());
  if (!setup) {
    for (const std::string& error : errors) {
      std::fprintf(stderr, "host_loop: %s\n", error.c_str());
    }
    return 1;
  }

  v8::Isolate* isolate = setup->isolate();
  uv_loop_t* loop = reinterpret_cast<uv_loop_t*>(setup->event_loop());
  if (loop == nullptr) {
    std::fprintf(stderr, "host_loop: the environment has no event loop\n");
    return 1;
  }

  int exit_code = 0;
  unsigned iterations = 0;
  bool fired = false;
  int fired_at = -1;
  {
    v8::Locker locker(isolate);
    v8::Isolate::Scope isolate_scope(isolate);
    v8::HandleScope handle_scope(isolate);
    v8::Context::Scope context_scope(setup->context());

    // Evaluate the script only. LoadEnvironment does not run the loop, so the timer the
    // script schedules stays queued until the host pumps it - which is the point.
    v8::MaybeLocal<v8::Value> loaded = node::LoadEnvironment(
        setup->env(),
        "const publicRequire ="
        "  require('node:module').createRequire(process.cwd() + '/');"
        "globalThis.require = publicRequire;"
        "publicRequire(process.argv[1]);");
    if (loaded.IsEmpty()) {
      exit_code = 1;
    }

    v8::Local<v8::Context> context = setup->context();
    v8::Local<v8::String> iteration_name = Name(isolate, kIterationGlobal);
    v8::Local<v8::String> fired_name = Name(isolate, kFiredGlobal);

    for (; exit_code == 0 && iterations < 1000; ++iterations) {
      // Stamp the iteration so the script can say which one it ran in.
      context->Global()
          ->Set(context, iteration_name, v8::Integer::NewFromUnsigned(isolate, iterations))
          .Check();

      // One non-blocking pump. This call runs node's loop callbacks on *this* thread.
      uv_run(loop, UV_RUN_NOWAIT);
      // When the host owns the loop it also owns the platform's tasks (V8 microtasks,
      // worker-thread callbacks); node's own SpinEventLoop would do this for you.
      platform->DrainTasks(isolate);

      v8::Local<v8::Value> value;
      if (context->Global()->Get(context, fired_name).ToLocal(&value) &&
          !value->IsUndefined()) {
        fired = true;
        fired_at = value->Int32Value(context).FromMaybe(-1);
        break;
      }

      // Yield like a real host loop would between pumps (waiting for the next UI event,
      // the next socket, the next frame).
      uv_sleep(1);
    }
  }

  if (fired && fired_at == static_cast<int>(iterations)) {
    std::printf("host: timer fired in host iteration %d of %u pumped\n",
                fired_at, iterations + 1);
  } else if (fired) {
    // The callback ran, but not during the iteration the host was driving: either it ran
    // before the host's loop started, or the loop advanced without the stamping.
    std::printf("host: timer fired at iteration %d, host drove iteration %u\n",
                fired_at, iterations);
    exit_code = 1;
  } else {
    std::printf("host: timer never fired in %u pumped iterations\n", iterations);
    exit_code = 1;
  }

  node::Stop(setup->env());
  setup.reset();
  v8::V8::Dispose();
  v8::V8::DisposePlatform();
  platform.reset();
  node::TearDownOncePerProcess();
  return exit_code;
}
