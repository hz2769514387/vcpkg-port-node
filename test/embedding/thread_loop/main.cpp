// Node.js on a worker thread, with the host keeping its own main loop.
//
// A host cannot always hand its main thread to the runtime: it has a UI, a polling loop or a
// service loop of its own. The runtime then has to be created on a thread the host owns,
// driven from that thread, and shut down from that thread - which is a different code path
// from node::Start, and one that quietly depends on the platform, the isolate and the event
// loop being wired up by hand.
//
// This is the sequence from Node.js's own embedding documentation, with one addition: the
// main thread keeps ticking while the runtime runs, and the test asserts that it did.
#include <node.h>
#include <v8.h>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <memory>
#include <string>
#include <thread>
#include <vector>

int main(int argc, char* argv[]) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s <script.js>\n", argv[0]);
    return 2;
  }

  // Parse argv the way node.exe would, but without letting V8 or the Node.js platform
  // initialize themselves: this host owns both, and it decides when they come up.
  std::vector<std::string> args(argv, argv + argc);
  std::shared_ptr<node::InitializationResult> initialization =
      node::InitializeOncePerProcess(
          args, {node::ProcessInitializationFlags::kNoInitializeV8,
                 node::ProcessInitializationFlags::kNoInitializeNodeV8Platform});
  for (const std::string& error : initialization->errors()) {
    std::fprintf(stderr, "thread_loop: %s\n", error.c_str());
  }
  if (initialization->early_return() != 0) {
    return initialization->exit_code();
  }

  std::unique_ptr<node::MultiIsolatePlatform> platform =
      node::MultiIsolatePlatform::Create(4);
  v8::V8::InitializePlatform(platform.get());
  v8::V8::Initialize();

  std::atomic<bool> runtime_done{false};
  std::atomic<unsigned long> host_ticks{0};
  int runtime_exit_code = 1;

  std::thread runtime([&]() {
    std::vector<std::string> errors;
    std::unique_ptr<node::CommonEnvironmentSetup> setup =
        node::CommonEnvironmentSetup::Create(platform.get(), &errors,
                                             initialization->args(),
                                             initialization->exec_args());
    if (!setup) {
      for (const std::string& error : errors) {
        std::fprintf(stderr, "thread_loop: %s\n", error.c_str());
      }
      runtime_done = true;
      return;
    }

    v8::Isolate* isolate = setup->isolate();
    {
      // An isolate used from a thread that does not own it has to be locked; this is the
      // part that makes the whole scenario different from embedding on the main thread.
      v8::Locker locker(isolate);
      v8::Isolate::Scope isolate_scope(isolate);
      v8::HandleScope handle_scope(isolate);
      v8::Context::Scope context_scope(setup->context());

      // The `require` given to this script sees built-in modules only, so the standard file
      // loader is put on globalThis first and used to load the script as CommonJS. (The
      // documentation's own example hands `process.argv[1]` straight to runInThisContext,
      // which is the `node -e <code>` case: there argv[1] is the source, not a path.)
      v8::MaybeLocal<v8::Value> loaded = node::LoadEnvironment(
          setup->env(),
          "const publicRequire ="
          "  require('node:module').createRequire(process.cwd() + '/');"
          "globalThis.require = publicRequire;"
          "publicRequire(process.argv[1]);");
      if (loaded.IsEmpty()) {
        runtime_exit_code = 1;
      } else {
        runtime_exit_code = node::SpinEventLoop(setup->env()).FromMaybe(1);
      }
      node::Stop(setup->env());
    }

    // Destroying the setup here, on this thread, is deliberate: it unregisters the isolate
    // from the platform, and doing it from the host's thread after joining is the kind of
    // ordering mistake that shows up as a crash at exit rather than as a test failure.
    setup.reset();
    runtime_done = true;
  });

  while (!runtime_done.load()) {
    // The host's own loop. Telemetry, a UI pump, a socket - whatever it is, it must not be
    // blocked by the runtime, and this counter is the evidence that it was not.
    host_ticks.fetch_add(1);
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  }
  runtime.join();

  // Dispose V8 and the platform before releasing the platform object:
  // V8::DisposePlatform touches the platform, so resetting the unique_ptr
  // first leaves it with a dangling pointer and segfaults.
  v8::V8::Dispose();
  v8::V8::DisposePlatform();
  platform.reset();
  node::TearDownOncePerProcess();

  std::printf("host: %lu ticks while the runtime ran on its own thread\n",
              host_ticks.load());
  return runtime_exit_code;
}
