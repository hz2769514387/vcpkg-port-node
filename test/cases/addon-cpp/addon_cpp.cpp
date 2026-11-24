// A C++ addon written with node-addon-api, the way a product's native module would be.
//
// The wrapper is a header-only layer over the C API: Napi::ObjectWrap generates the class
// registration, the property accessors and the method dispatch. If <node_api.h> in the include
// path were a different header from the one the runtime was built with, this would either not
// compile or register against a mismatch the C API cannot see.
#include <napi.h>

#include <cstdint>

namespace {

class Counter : public Napi::ObjectWrap<Counter> {
 public:
  static Napi::Object Init(Napi::Env env, Napi::Object exports) {
    Napi::Function constructor = DefineClass(env, "Counter", {
        InstanceMethod("increment", &Counter::Increment),
        InstanceAccessor("value", &Counter::GetValue, nullptr),
    });
    exports.Set("Counter", constructor);
    return exports;
  }

  explicit Counter(const Napi::CallbackInfo& info)
      : Napi::ObjectWrap<Counter>(info) {
    if (info.Length() > 0 && info[0].IsNumber()) {
      value_ = info[0].As<Napi::Number>().Int32Value();
    }
  }

 private:
  Napi::Value Increment(const Napi::CallbackInfo& info) {
    int32_t step = 1;
    if (info.Length() > 0 && info[0].IsNumber()) {
      step = info[0].As<Napi::Number>().Int32Value();
    }
    value_ += step;
    return Napi::Number::New(info.Env(), value_);
  }

  Napi::Value GetValue(const Napi::CallbackInfo& info) {
    return Napi::Number::New(info.Env(), value_);
  }

  int32_t value_ = 0;
};

Napi::Object InitAll(Napi::Env env, Napi::Object exports) {
  return Counter::Init(env, exports);
}

}  // namespace

NODE_API_MODULE(node_port_addon_cpp, InitAll)
