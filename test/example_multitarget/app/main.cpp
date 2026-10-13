// 场景七（vcpkg 侧）第二层 A：分层工程的上层可执行。
//
// 它**只链 node_engine**（消费方自己的静态库）—— 没有 node 的头文件、
// 没有 unofficial::node::node。这就是分层集成的样子：node 是引擎的实现
// 细节，上层零感知。
//
// 顺带立一个规矩：上层自己的日志走 **stderr**，stdout 原样留给脚本输出 ——
// 调用方想捕获/转发 node 的产物时，stdout 是干净的。
#include "engine.h"

#include <cstdio>

int main(int argc, char* argv[]) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s <script.js> [who]\n", argv[0]);
    return 2;
  }
  const std::string who = argc >= 3 ? argv[2] : "engine-app";

  const int rc = engine::RunScript(argv[1], {who});

  std::fprintf(stderr, "layered-app: engine returned %d\n", rc);
  return rc;  // 原样透传，不做任何改写
}
