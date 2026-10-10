// node port 消费端冒烟测试：最小嵌入。
//
// 用途：验证 <prefix>/share/node/node-config.cmake 能被 find_package 找到、
// `node::node` 能被链接，并且**真的跑得起** node 运行时。
//
// 做法：把命令行参数原样交给 node —— 等价于 node 自带命令行：
//     smoke -e "console.log(process.versions.node)"
//     smoke script.js
#include <node.h>

#include <cstdio>

int main(int argc, char* argv[]) {
  if (argc <= 1) {
    std::fprintf(stderr,
                 "用法：%s [-e <脚本> | <脚本文件> ...]\n"
                 "例如：%s -e \"console.log(process.versions.node)\"\n",
                 argv[0], argv[0]);
    return 2;
  }
  return node::Start(argc, argv);
}