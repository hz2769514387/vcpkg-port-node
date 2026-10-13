// 场景七（vcpkg 侧）第二层 B：同一个工程里的另一个可执行，**直接**链 node。
//
// 与第二层 A（ layered_app 只链引擎库）并存，演示的是：一个工程里两种接法
// 可以同时存在，各自清楚 —— 有的目标想把 node 藏起来，有的目标自己就是
// node 的门面。这里还顺手和 **fmt**（另一个 vcpkg 库）一起用：node 与其它
// vcpkg 库在同一个目标里各干各的，互不干涉。
//
// 这个文件也是"带日志的 node 门面"的最小参考实现：启动/退出都打一行，
// 退出码原样透传。
#include <node.h>

#include <fmt/format.h>

#include <cstdio>

int main(int argc, char* argv[]) {
  if (argc < 2) {
    fmt::print(stderr, "usage: {} <script.js> [who]\n", argv[0]);
    return 2;
  }
  const std::string who = argc >= 3 ? argv[2] : "direct-cli";

  fmt::print("direct-cli: starting node for {} (who={})\n", argv[1], who);

  const int rc = node::Start(argc, argv);

  fmt::print("direct-cli: node exited with {}\n", rc);
  return rc;  // 原样透传
}
