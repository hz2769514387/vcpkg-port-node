// A std::thread that the host owns signals a uv_async_t created on Node.js's loop.
//
// uv_async_send() is the one libuv call designed to be made from a foreign thread. The
// callback must then run on the host's pump of *that* loop, which only happens if the
// consumer's libuv and the runtime's libuv are the same implementation sharing the same
// uv_loop_t. A second copy of libuv would either fail to link or deliver the signal to a
// loop nobody pumps.
#include <node.h>
#include <uv.h>
#include <v8.h>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr const char* kIteration = "__node_port_iteration";
constexpr const char* kTimer = "__node_port_timer_at";

uv_loop_t* g_expected_loop = nullptr;
std::atomic<int> g_async_calls{0};
std::atomic<bool> g_async_on_expected_loop{false};

void OnAsync(uv_async_t* handle) {
  g_async_on_expected_loop.store(
      uv_handle_get_loop(reinterpret_cast<uv_handle_t*>(handle)) == g_expected_loop);
  g_async_calls.fetch_add(1);
  // Closing it inside the callback keeps the handle from holding the loop open, and lets
  // CommonEnvironmentSetup destroy the loop cleanly afterwards.
  uv_close(reinterpret_cast<uv_handle_t*>(handle), nullptr);
}

v8::Local<v8::String> Name(v8::Isolate* isolate, const char* text) {
  return v8::String::NewFromUtf8(isolate, text).ToLocalChecked();
}

}  // namespace

int main(int argc, char* argv[]) {
  if (argc < 2) {
    std::fprintf(stderr, "loop_wakeup_error: usage: %s <script.cjs>\n", argv[0]);
    return 2;
  }

  std::vector<std::string> args(argv, argv + argc);
  std::shared_ptr<node::InitializationResult> initialization =
      node::InitializeOncePerProcess(
          args, {node::ProcessInitializationFlags::kNoInitializeV8,
                 node::ProcessInitializationFlags::kNoInitializeNodeV8Platform});
  for (const std::string& error : initialization->errors()) {
    std::fprintf(stderr, "loop_wakeup_error: %s\n", error.c_str());
  }
  if (initialization->early_return() != 0) return initialization->exit_code();

  std::unique_ptr<node::MultiIsolatePlatform> platform =
      node::MultiIsolatePlatform::Create(4);
  v8::V8::InitializePlatform(platform.get());
  v8::V8::Initialize();

  int exit_code = 0;
  {
    std::vector<std::string> errors;
    std::unique_ptr<node::CommonEnvironmentSetup> setup =
        node::CommonEnvironmentSetup::Create(platform.get(), &errors,
                                             initialization->args(),
                                             initialization->exec_args());
    if (!setup) {
      for (const std::string& error : errors) {
        std::fprintf(stderr, "loop_wakeup_error: %s\n", error.c_str());
      }
      exit_code = 1;
    } else {
      v8::Isolate* isolate = setup->isolate();
      uv_loop_t* loop = reinterpret_cast<uv_loop_t*>(setup->event_loop());
      g_expected_loop = loop;

      uv_async_t async_handle;
      const int init_result = uv_async_init(loop, &async_handle, &OnAsync);
      if (init_result != 0) {
        std::fprintf(stderr, "loop_wakeup_error: uv_async_init: %s\n", uv_strerror(init_result));
        exit_code = 1;
      }

      // The producer thread knows nothing about V8 or JavaScript. All it has is a libuv
      // handle that belongs to the runtime's loop.
      std::thread producer;
      if (exit_code == 0) {
        producer = std::thread([&async_handle]() {
          std::this_thread::sleep_for(std::chrono::milliseconds(20));
          uv_async_send(&async_handle);
        });
      }

      unsigned iterations = 0;
      int timer_at = -1;
      // The timer can fire several iterations before the native thread's uv_async_send is
      // delivered: the loop keeps pumping until both have happened. What has to match is the
      // iteration the script recorded and the iteration in which the host first read it, not
      // the iteration on which the host finally stopped pumping. Measured on macOS: the timer
      // fired in iteration 4 while the async callback arrived in iteration 12.
      int timer_observed_at = -1;
      {
        v8::Locker locker(isolate);
        v8::Isolate::Scope isolate_scope(isolate);
        v8::HandleScope handle_scope(isolate);
        v8::Context::Scope context_scope(setup->context());
        v8::Local<v8::Context> context = setup->context();

        const std::string bootstrap =
            "const publicRequire ="
            "  require('node:module').createRequire(process.cwd() + '/');"
            "globalThis.require = publicRequire;"
            "publicRequire(process.argv[1]);";
        if (node::LoadEnvironment(setup->env(), bootstrap).IsEmpty()) {
          std::fprintf(stderr, "loop_wakeup_error: LoadEnvironment failed\n");
          exit_code = 1;
        }

        for (; exit_code == 0 && iterations < 1000; ++iterations) {
          context->Global()
              ->Set(context, Name(isolate, kIteration),
                    v8::Integer::NewFromUnsigned(isolate, iterations))
              .Check();
          uv_run(loop, UV_RUN_NOWAIT);
          platform->DrainTasks(isolate);

          v8::Local<v8::Value> value;
          if (context->Global()->Get(context, Name(isolate, kTimer)).ToLocal(&value) &&
              !value->IsUndefined()) {
            timer_at = value->Int32Value(context).FromMaybe(-1);
            if (timer_observed_at < 0) timer_observed_at = static_cast<int>(iterations);
          }
          if (timer_at >= 0 && g_async_calls.load() > 0) break;
          uv_sleep(1);
        }

        if (exit_code == 0) {
          if (timer_at < 0) {
            std::fprintf(stderr, "loop_wakeup_error: the JS timer never fired in %u pumps\n",
                         iterations);
            exit_code = 1;
          } else if (timer_at != timer_observed_at) {
            std::fprintf(stderr,
                         "loop_wakeup_error: the JS timer recorded iteration %d, but the host "
                         "first saw it in iteration %d\n", timer_at, timer_observed_at);
            exit_code = 1;
          } else if (g_async_calls.load() != 1 || !g_async_on_expected_loop.load()) {
            std::fprintf(stderr,
                         "loop_wakeup_error: async callback count %d, on the expected loop %d\n",
                         g_async_calls.load(), g_async_on_expected_loop.load() ? 1 : 0);
            exit_code = 1;
          }
        }
        // Let libuv finish the uv_close() started inside the callback while the isolate is
        // still entered; a handle still closing would make uv_loop_close() report UV_EBUSY.
        for (int i = 0; i < 4; ++i) {
          uv_run(loop, UV_RUN_NOWAIT);
          platform->DrainTasks(isolate);
        }
        node::Stop(setup->env());
      }

      if (producer.joinable()) producer.join();
      setup.reset();
    }
  }

  v8::V8::Dispose();
  v8::V8::DisposePlatform();
  platform.reset();
  node::TearDownOncePerProcess();

  if (exit_code == 0) {
    std::printf("loop-wakeup: native wakeup and JS timer both ran on node's loop\n");
  }
  return exit_code;
}
