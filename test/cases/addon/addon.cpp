// A real N-API addon, written the way a consumer's native module would be.
//
// It is deliberately not a "hello world" registration: a product's addon calls back into
// JavaScript, hands Buffers across the boundary, throws errors, queues work onto libuv's
// thread pool, and calls JavaScript from a thread the runtime does not own. Each of those
// is a different part of the ABI this port delivers.
#include <node_api.h>
#include <node_version.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <thread>

namespace {

napi_value Int(napi_env env, int32_t value) {
  napi_value result;
  napi_create_int32(env, value, &result);
  return result;
}

napi_value Fail(napi_env env, const char* message) {
  napi_throw_error(env, nullptr, message);
  return nullptr;
}

bool ReadInt(napi_env env, napi_value value, int32_t* out) {
  return napi_get_value_int32(env, value, out) == napi_ok;
}

// NODE_MODULE_VERSION comes from the installed headers; addon.mjs compares it with
// process.versions.modules. A mismatch means the headers a consumer compiled against do
// not belong to the runtime they loaded.
napi_value ModuleVersion(napi_env env, napi_callback_info) {
  return Int(env, NODE_MODULE_VERSION);
}

napi_value RuntimeInfo(napi_env env, napi_callback_info) {
  napi_value object;
  napi_create_object(env, &object);
  uint32_t napi_version = 0;
  napi_get_version(env, &napi_version);
  napi_set_named_property(env, object, "napi", Int(env, static_cast<int32_t>(napi_version)));

  const napi_node_version* node = nullptr;
  if (napi_get_node_version(env, &node) == napi_ok && node != nullptr) {
    char text[64];
    snprintf(text, sizeof(text), "%u.%u.%u", node->major, node->minor, node->patch);
    napi_value value;
    napi_create_string_utf8(env, text, NAPI_AUTO_LENGTH, &value);
    napi_set_named_property(env, object, "node", value);
  }
  return object;
}

napi_value Sum(napi_env env, napi_callback_info info) {
  size_t count = 1;
  napi_value args[1];
  if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count < 1) {
    return Fail(env, "sum(n) needs one argument");
  }
  int32_t n = 0;
  if (!ReadInt(env, args[0], &n) || n < 0) return Fail(env, "sum(n) needs a non-negative int");
  return Int(env, n * (n + 1) / 2);
}

// Invoke a JavaScript function with one argument and return what it returned.
napi_value CallWith(napi_env env, napi_callback_info info) {
  size_t count = 2;
  napi_value args[2];
  if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count < 2) {
    return Fail(env, "callWith(fn, value) needs two arguments");
  }
  napi_valuetype type;
  if (napi_typeof(env, args[0], &type) != napi_ok || type != napi_function) {
    return Fail(env, "callWith: first argument must be a function");
  }
  napi_value global;
  napi_get_global(env, &global);
  napi_value result;
  if (napi_call_function(env, global, args[0], 1, &args[1], &result) != napi_ok) {
    return nullptr;  // the call threw; N-API left the exception pending
  }
  return result;
}

napi_value MakeBuffer(napi_env env, napi_callback_info info) {
  size_t count = 1;
  napi_value args[1];
  if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count < 1) {
    return Fail(env, "makeBuffer(text) needs one argument");
  }
  size_t length = 0;
  if (napi_get_value_string_utf8(env, args[0], nullptr, 0, &length) != napi_ok) {
    return Fail(env, "makeBuffer: expected a string");
  }
  char* bytes = new char[length + 1];
  size_t written = 0;
  napi_get_value_string_utf8(env, args[0], bytes, length + 1, &written);
  napi_value buffer;
  napi_create_buffer_copy(env, written, bytes, nullptr, &buffer);
  delete[] bytes;
  return buffer;
}

napi_value ThrowExample(napi_env env, napi_callback_info info) {
  size_t count = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
  char message[128] = "addon threw on purpose";
  if (count >= 1) {
    size_t length = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &length);
    if (length + 1 < sizeof(message)) {
      napi_get_value_string_utf8(env, args[0], message, sizeof(message), &length);
    }
  }
  return Fail(env, message);
}

// --- async work on libuv's thread pool ---------------------------------------
struct AsyncSum {
  napi_async_work work;
  napi_ref callback;
  int32_t n;
  int32_t result;
};

void ExecuteAsync(napi_env, void* data) {
  AsyncSum* job = static_cast<AsyncSum*>(data);
  // Runs on a libuv worker thread: no V8 or N-API calls are allowed here.
  job->result = job->n * (job->n + 1) / 2;
}

void CompleteAsync(napi_env env, napi_status status, void* data) {
  AsyncSum* job = static_cast<AsyncSum*>(data);
  napi_value callback;
  napi_get_reference_value(env, job->callback, &callback);
  napi_value global;
  napi_get_global(env, &global);

  napi_value args[2];
  if (status == napi_ok) {
    napi_get_null(env, &args[0]);
    args[1] = Int(env, job->result);
  } else {
    napi_value error;
    napi_create_string_utf8(env, "async work was cancelled", NAPI_AUTO_LENGTH, &error);
    napi_create_error(env, nullptr, error, &args[0]);
    napi_get_undefined(env, &args[1]);
  }
  napi_call_function(env, global, callback, 2, args, nullptr);
  napi_delete_reference(env, job->callback);
  napi_delete_async_work(env, job->work);
  delete job;
}

napi_value AsyncSumTo(napi_env env, napi_callback_info info) {
  size_t count = 2;
  napi_value args[2];
  if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count < 2) {
    return Fail(env, "asyncSum(n, cb) needs two arguments");
  }
  AsyncSum* job = new AsyncSum{nullptr, nullptr, 0, 0};
  if (!ReadInt(env, args[0], &job->n)) {
    delete job;
    return Fail(env, "asyncSum: n must be an int");
  }
  napi_create_reference(env, args[1], 1, &job->callback);
  napi_value name;
  napi_create_string_utf8(env, "node-port:async-sum", NAPI_AUTO_LENGTH, &name);
  if (napi_create_async_work(env, nullptr, name, ExecuteAsync, CompleteAsync, job,
                             &job->work) != napi_ok ||
      napi_queue_async_work(env, job->work) != napi_ok) {
    napi_delete_reference(env, job->callback);
    delete job;
    return Fail(env, "asyncSum: could not queue the work");
  }
  napi_value undefined;
  napi_get_undefined(env, &undefined);
  return undefined;
}

// --- a thread-safe function fed by a thread the runtime does not own ----------
struct Producer {
  napi_threadsafe_function tsfn;
  int count;
};

void CallJs(napi_env env, napi_value callback, void*, void* data) {
  // env and callback are null while the function is closing; there is nothing to call.
  if (env == nullptr || callback == nullptr) return;
  napi_value global;
  napi_get_global(env, &global);
  napi_value argument = Int(env, static_cast<int32_t>(reinterpret_cast<intptr_t>(data)));
  napi_call_function(env, global, callback, 1, &argument, nullptr);
}

void RunProducer(void* context) {
  Producer* producer = static_cast<Producer*>(context);
  for (int i = 1; i <= producer->count; ++i) {
    napi_call_threadsafe_function(producer->tsfn,
                                  reinterpret_cast<void*>(static_cast<intptr_t>(i)),
                                  napi_tsfn_blocking);
  }
  // Releasing the last producer closes the function and lets the loop drain.
  napi_release_threadsafe_function(producer->tsfn, napi_tsfn_release);
  delete producer;
}

napi_value StreamFromThread(napi_env env, napi_callback_info info) {
  size_t count = 2;
  napi_value args[2];
  if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count < 2) {
    return Fail(env, "stream(count, cb) needs two arguments");
  }
  int32_t requested = 0;
  if (!ReadInt(env, args[0], &requested) || requested < 1 || requested > 100) {
    return Fail(env, "stream: count must be between 1 and 100");
  }
  Producer* producer = new Producer{nullptr, requested};
  napi_value name;
  napi_create_string_utf8(env, "node-port:stream", NAPI_AUTO_LENGTH, &name);
  if (napi_create_threadsafe_function(env, args[1], nullptr, name, 0, 1, nullptr,
                                      nullptr, producer, CallJs,
                                      &producer->tsfn) != napi_ok) {
    delete producer;
    return Fail(env, "stream: could not create the thread-safe function");
  }
  std::thread(RunProducer, producer).detach();
  napi_value undefined;
  napi_get_undefined(env, &undefined);
  return undefined;
}

napi_value Init(napi_env env, napi_value exports) {
  struct Entry { const char* name; napi_callback fn; };
  const Entry entries[] = {
    {"moduleVersion", ModuleVersion}, {"runtimeInfo", RuntimeInfo},
    {"sum", Sum}, {"callWith", CallWith}, {"makeBuffer", MakeBuffer},
    {"throwExample", ThrowExample}, {"asyncSum", AsyncSumTo},
    {"streamFromThread", StreamFromThread},
  };
  for (const Entry& entry : entries) {
    napi_value function;
    napi_create_function(env, entry.name, NAPI_AUTO_LENGTH, entry.fn, nullptr, &function);
    napi_set_named_property(env, exports, entry.name, function);
  }
  return exports;
}

}  // namespace

// Symbol-based registration (napi_register_module_v<ABI>), so no node-gyp-provided module
// name is needed: a CMake consumer can build this file unchanged.
NAPI_MODULE_INIT() {
  return Init(env, exports);
}
