// The host calls into JavaScript after the environment is up, and the I/O that call starts
// has to reach the loop the host is pumping.
//
// A host does this for everything it runs on demand - "handle this request", "reload this
// module", "run this plugin hook" - and the call does not go through Node's own execution
// path the way a script does. nodejs/node#48760 reported that a fetch/net started from
// v8::Function::Call after LoadEnvironment never reached the loop (`uv_loop_alive` was
// immediately 0). This program measures the current behaviour instead of trusting that
// report: one connection is started from inside the script's own listen callback (the
// supported path) and one from a v8::Function::Call made by the host afterwards, and both
// have to be serviced by the same pump loop.
//
// The assertion is deliberately on the *effect* (both connections completed) rather than on
// uv_loop_alive or handle counts: a build that queues the work but never runs it fails here,
// and a future regression of #48760 fails here rather than hanging a product.

#include <node.h>
#include <uv.h>
#include <v8.h>

#include <cstdio>
#include <memory>
#include <string>
#include <vector>

namespace {

v8::Local<v8::String> Name(v8::Isolate* isolate, const char* text) {
  return v8::String::NewFromUtf8(isolate, text).ToLocalChecked();
}

bool GetGlobal(v8::Local<v8::Context> context, v8::Isolate* isolate, const char* name,
               v8::Local<v8::Value>* out) {
  return context->Global()->Get(context, Name(isolate, name)).ToLocal(out);
}

// Starts one connection per call. `inside-callback` is invoked by the script itself once the
// server is listening; `outside-call` only from C++, after LoadEnvironment returned.
const char* kScript = R"JS(
  const net = require('node:net');
  const events = [];
  globalThis.__events = events;
  function connect(tag) {
    const client = net.connect(globalThis.__port, '127.0.0.1', () => {
      events.push(tag + ':connect');
    });
    client.on('data', (chunk) => {
      events.push(tag + ':data:' + chunk);
      client.end();
    });
    client.on('error', (error) => {
      events.push(tag + ':error:' + error.code);
    });
  }
  const server = net.createServer((socket) => {
    socket.end('server-ok');
  });
  server.listen(0, '127.0.0.1', () => {
    globalThis.__port = server.address().port;
    connect('inside-callback');
  });
  globalThis.__start = (tag) => connect(tag);
)JS";

const char* kExpected[] = {
    "inside-callback:connect",  "inside-callback:data:server-ok",
    "outside-call:connect",     "outside-call:data:server-ok",
};

}  // namespace

int main(int argc, char** argv) {
  std::vector<std::string> args(argv, argv + argc);
  std::shared_ptr<node::InitializationResult> initialization =
      node::InitializeOncePerProcess(
          args, {node::ProcessInitializationFlags::kNoInitializeV8,
                 node::ProcessInitializationFlags::kNoInitializeNodeV8Platform});
  for (const std::string& error : initialization->errors()) {
    std::fprintf(stderr, "host_call: %s\n", error.c_str());
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
      std::fprintf(stderr, "host_call: %s\n", error.c_str());
    }
    return 1;
  }

  v8::Isolate* isolate = setup->isolate();
  uv_loop_t* loop = reinterpret_cast<uv_loop_t*>(setup->event_loop());
  int exit_code = 1;

  {
    v8::Locker locker(isolate);
    v8::Isolate::Scope isolate_scope(isolate);
    v8::HandleScope handle_scope(isolate);
    v8::Local<v8::Context> context = setup->context();
    v8::Context::Scope context_scope(context);

    if (node::LoadEnvironment(setup->env(), kScript).IsEmpty()) {
      std::fprintf(stderr, "host_call: LoadEnvironment failed\n");
      node::Stop(setup->env());
      return 1;
    }

    // Pump until the script's own listen callback recorded the port.
    bool port_ready = false;
    for (int i = 0; i < 2000 && !port_ready; ++i) {
      uv_run(loop, UV_RUN_NOWAIT);
      platform->DrainTasks(isolate);
      v8::Local<v8::Value> port;
      port_ready = GetGlobal(context, isolate, "__port", &port) && !port->IsUndefined();
      if (!port_ready) uv_sleep(1);
    }

    bool host_called = false;
    if (port_ready) {
      v8::Local<v8::Value> starter;
      if (GetGlobal(context, isolate, "__start", &starter) && starter->IsFunction()) {
        v8::Local<v8::Value> tag = Name(isolate, "outside-call");
        host_called =
            !starter.As<v8::Function>()->Call(context, context->Global(), 1, &tag).IsEmpty();
      }
    }

    // Keep pumping until both connections have completed, or five seconds passed.
    v8::Local<v8::Array> events;
    for (int i = 0; i < 2500; ++i) {
      uv_run(loop, UV_RUN_NOWAIT);
      platform->DrainTasks(isolate);
      v8::Local<v8::Value> events_value;
      if (GetGlobal(context, isolate, "__events", &events_value) && events_value->IsArray()) {
        events = events_value.As<v8::Array>();
        if (events->Length() >= 4) break;
      }
      uv_sleep(2);
    }

    std::printf("host_call port_ready=%d host_called=%d\n", port_ready ? 1 : 0,
                host_called ? 1 : 0);
    std::vector<std::string> seen;
    if (!events.IsEmpty()) {
      for (uint32_t i = 0; i < events->Length(); ++i) {
        v8::Local<v8::Value> item;
        if (events->Get(context, i).ToLocal(&item) && item->IsString()) {
          v8::String::Utf8Value text(isolate, item);
          seen.emplace_back(*text ? *text : "");
          std::printf("  event: %s\n", *text ? *text : "(null)");
        }
      }
    }

    bool complete = port_ready && host_called;
    for (const char* expected : kExpected) {
      bool found = false;
      for (const std::string& actual : seen) {
        if (actual == expected) {
          found = true;
          break;
        }
      }
      if (!found) {
        std::fprintf(stderr, "host_call: missing '%s'\n", expected);
        complete = false;
      }
    }
    exit_code = complete ? 0 : 1;

    node::Stop(setup->env());
  }

  return exit_code;
}
