// 场景七（vcpkg 侧）第一层的实现：引擎里唯一一处直接碰 node 的地方。
//
// 注意 argv 的拼法：argv[0] 给一个稳定的进程名（node 侧很少用它，但要有），
// 后面跟脚本路径与调用方给的额外参数 —— 与"命令行跑 node script.js arg"
// 的形状一致，JS 侧从 process.argv 拿。
//
// 缓冲区生命周期：script_path / extra_args 由调用方持有，node::Start 返回前
// 一直有效，所以这里直接取 c_str() 是安全的。
#include "engine.h"

#include <node.h>

#include <vector>

namespace engine {

int RunScript(const std::string& script_path,
              const std::vector<std::string>& extra_args) {
  std::vector<char*> argv;
  argv.push_back(const_cast<char*>("node-engine"));
  argv.push_back(const_cast<char*>(script_path.c_str()));
  for (const std::string& a : extra_args) {
    argv.push_back(const_cast<char*>(a.c_str()));
  }
  argv.push_back(nullptr);

  const int rc =
      node::Start(static_cast<int>(argv.size()) - 1, argv.data());
  return rc;  // 原样透传：调用方 -> 引擎 -> node -> 调用方
}

}  // namespace engine
