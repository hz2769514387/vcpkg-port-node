// 场景七（vcpkg 侧）第一层：消费方自己的"引擎"静态库。
//
// 这个文件回答的是："我的工程不是一个小 main.cpp，它有分层 —— node port
// 怎么接进来？"答案是：**node 只在最底层出现一次，而且 PRIVATE**。
// 上层可执行只链这个引擎库，连 node 的头文件都不用见 —— node 对上层是
// 引擎的实现细节。将来换 node 版本、甚至换掉 node，上层零改动。
#pragma once

#include <string>
#include <vector>

namespace engine {

// 跑一段 JS。返回 node 的退出码 —— **原样透传，不改写**
// （为什么：见 example_host_exit，退出码是调用方判定成败的依据）。
//
// extra_args 会作为脚本的参数传给 JS 侧（process.argv[3] 起）。
int RunScript(const std::string& script_path,
              const std::vector<std::string>& extra_args = {});

}  // namespace engine
