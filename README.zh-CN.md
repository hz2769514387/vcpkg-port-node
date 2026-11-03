# vcpkg-port-node

[English](README.md) | **简体中文**

> 本文是 [README.md](README.md) 的中文翻译。**英文版为准**：两者不一致时以英文版为准，新内容也先写进英文版。

把 **Node.js 源码树**（含 V8）编译成一个**可链接的库**，以 **vcpkg overlay port** 的形式交付 ——
这样 C++ 项目可以直接嵌入 Node.js，不必自己 vendor 一份 Node.js 源码。

```cmake
find_package(unofficial-node CONFIG REQUIRED)
target_link_libraries(my_app PRIVATE unofficial::node::node)
```

## 这是你要找的吗？

- 把 **Node.js 嵌进 C++ 应用** —— 你要的是一份可链接的库，不是去调 `node.exe`。
- **两种链路都支持**：静态 libnode 直接链接进你的可执行文件（Windows 上这也是拿到静态 CRT 的方式），
  或者共享库 `.dll` / `.so` / `.dylib`，由一个宿主进程加载、多个进程共用。
- 找一个 **vcpkg 的 `node` / libnode port** —— 以 overlay port 形式提供，所有依赖来自同一棵 vcpkg 版本树。
- 用 **C++ 宿主通过 N-API 驱动 Node.js**，并且让 Node.js 自己的依赖由 vcpkg 构建，而不是内嵌一份。

以上都不是的话：本仓库不是 Node.js 发行版，也不是可以单独使用的 JavaScript 引擎（V8 在这里随
Node.js 一起交付，不单独提供），更不是 curated vcpkg 仓库能收录的东西 —— 原因见下面的
*为什么必须是 overlay port*。支持边界写在 *已知限制* 里。

## 状态

已发布：**`20261026_26.12.1_vcpkg-2026.10.16`**（首个发布为
`20261024_26.12.0_vcpkg-2026.07.29`）。本仓库目前处于维护期 —— 所有改动都走 pull request，
`main` 上每次 push 的完整矩阵都要求通过。

|             |                                                 |
| ----------- | ----------------------------------------------- |
| Node.js     | v26.13.0（v26 线，LTS）                         |
| vcpkg       | 2026.10.16（已钉死）                            |
| 构建路线    | `configure.py` → `gyp -f ninja` → `ninja`       |
| 交付形态    | 静态库或共享库 + CMake 配置，以 overlay port 交付 |

这些钉死值的机器可读记录（连同 V8 版本、`NODE_MODULE_VERSION` 和 Node.js 的 LTS 日期）在
[versions.json](versions.json)；版本、分支与标签之间的关系见
[docs/versioning.md](docs/versioning.md)。

## 为什么必须是 overlay port

V8 是 Node.js 自己维护的分支，Node.js 没有为它提供任何外接（externalize）通道，因此 Node.js 源码树
**只能在这里构建**。仅这一条就排除了提交到 vcpkg 官方 registry 的可能 —— 也正因如此，消费方式是
`overlay-ports`。

Node.js *确实*允许外接的部分（`--shared-*`、`--with-intl=system-icu`）一律从 vcpkg 取，而不用
其自带的副本，这样消费者的依赖图里每个库只有**一个**版本而不是两个。每个依赖当前的处置结论都写在
`docs/` 下。

## 如何使用

```jsonc
// 你项目里的 vcpkg-configuration.json
{
  "overlay-ports": ["path/to/vcpkg-port-node/ports"]
}
```

```jsonc
// 你项目里的 vcpkg.json
{
  "dependencies": [
    { "name": "node", "features": ["tools"] }
  ]
}
```

`tools` feature 会安装一个 `node` 可执行文件，连同 `npm` 和 `npx`；`test-suite` 会安装 Node.js
官方测试套件，方便消费者拿它跑自己的嵌入程序。

可用的示例工程和验证工程都在 `test/`：`cmake --preset …` 之后跑 `ctest`。细节见 `test/README.md`。

消费者需要 **C++20**：Node.js 和 V8 的头文件要求它，端口也在 imported target 上声明了它，所以
CMake 消费者无论哪种方式都会继承到。

## 已知限制

下表全部是本 port 或其平台自身带来的性质。未完成的支持不是限制：它们在
[issue 列表](https://github.com/hz2769514387/vcpkg-port-node/issues)里。

| 限制 | 原因 | 处理 |
|---|---|---|
| 消费它就要从源码构建 Node.js —— 首次 configure 需要几十分钟，且不提供任何预编译产物 | V8 是 Node.js 维护的分支，没有预编译渠道；curated registry 也无法容纳 overlay | 为构建做准备：`cargo`、Python 3，以及（Windows）Visual Studio 2022 的 clang-cl 组件。交叉构建还需要目标架构的 Rust 标准库（`rustup target add ...`） |
| overlay 会把 **19 个 registry port** 替换到整棵依赖图上 | `overlay-ports` 在全图生效；仅 zlib 分支就有 248 个依赖方 | 先读 [docs/overlay-replacements.md](docs/overlay-replacements.md) —— `mbedtls` 那一行是破坏性 API 变更（4.0 对 3.6） |
| macOS 的部署目标是依赖图的，不是 Node.js 的 13.5 | Node.js 把 13.5 写死且没有开关；其余依赖跟随 triplet | 需要 13.5 下限时在 triplet 里设 `VCPKG_OSX_DEPLOYMENT_TARGET 13.5` |
| Windows 需要 Visual Studio 2022 或更新 | Node.js 24 起要求 clang-cl | 更旧的版本未构建、未测量 |
| Debug 消费者需要 dual triplet | MSVC ABI：Debug 消费者链接 Debug 库，而 release-only triplet 不安装任何 Debug 库 | 调试自己代码用 `RelWithDebInfo` —— 它就是 release ABI |
| Windows x64、Debug：`Intl.DateTimeFormat` 在 ICU 内部中止 | UCRT 调试堆拒绝了 cl 编 ICU / clang-cl 编 Node 组合中的一个缓冲区 | 日期格式化用 `RelWithDebInfo`；`test/cases/externalization` 只跳过这一条断言 |
| Windows 上指定编译器要用工具集，不要用 `CMAKE_CXX_COMPILER` | Visual Studio 生成器从工具集推导编译器，静默忽略该变量 | 在 preset 里写 `toolset: {value: ClangCL, strategy: set}`；Linux 与 macOS 的编译器走 `CMAKE_{C,CXX}_COMPILER` |
| 共享 libnode 必须在运行时可被找到，且不要再链其它东西 | DLL/`.so`/`.dylib` 已包含全部外接依赖 | 把它拷到可执行文件旁，或设 `BUILD_RPATH`；不要二次链接那些依赖 |
| 只支持 CMake 集成 | 交付物是 gyp 构建出的一组静态归档，不是单一可描述的库 | 非 CMake 消费者按导出配置描述的链接行手工链接 |

## 持续集成

四道关卡，见 `docs/ci.md`。本仓库验证的每个维度都**在每次 push 时**执行，唯一不执行的那个会明说而
不是含糊带过：

- 一次秒级的 lint；
- `ci.yml` —— 通过 `test/` 在全部六个平台 cell（Windows、Linux、macOS 各两个架构）上构建端口，
  分别以 Release **和** RelWithDebInfo 消费，并在每条腿的 Release 消费者上跑 Node.js 官方测试套件；
- `debug.yml` —— **Debug** 消费者，它需要 Debug 库，因此需要单独的安装。四个 cell：Windows x64 与
  arm64、macOS arm64 与 x64。**两个 Linux cell 都没有 Debug 腿**：在四核机器上双配置安装 Node.js
  是 5h36m 的 vcpkg 工作（依赖全部命中缓存的情况下），于是 x64 腿在 GitHub 六小时 job 上限两侧来回
  摇摆，而 arm64 从未跑完。三次测量在 `docs/ci.md` 里；
- `matrix.yml` —— 矩阵的其余部分：Windows 上的动态 CRT，以及每个平台上的**共享 libnode**。八个
  cell 已全绿；它们仍被标为非阻塞，这件事记在
  [#35](https://github.com/hz2769514387/vcpkg-port-node/issues/35) 里。

Debug 和更宽的矩阵是独立工作流而不是 `ci.yml` 的额外腿，因为一个 job 要把端口为每个配置安装一遍、
每个配置再跑一遍套件，就会超出 GitHub 六小时的 job 上限；三个工作流并行跑，各自都在上限之内。

此外还有两个每日巡检，把钉死的 Node.js 与 vcpkg 版本与上游对比，任一动就开 issue —— 因为别的东西不会
做这件事：Renovate 和 Dependabot 都没有 vcpkg manager。每次运行所有腿的日志都汇总成一个归档，运行
摘要里带测试计数和第一个错误。

## 仓库结构

| 路径                 | 用途                                                                                   |
| -------------------- | -------------------------------------------------------------------------------------- |
| `ports/`             | overlay ports：`node` 以及任何需要钉死或打补丁的依赖                                    |
| `test/`              | 消费者侧示例工程与验证工程（ctest）                                                     |
| `tools/`             | 维护脚本：版本树哈希、卫生检查、发布巡检、基准对比                                       |
| `versions/`          | vcpkg 版本文件（每个 port 一个），携带各 port 的 git-tree                                |
| `.github/workflows/` | 持续集成，见 `docs/ci.md`                                                               |
| `docs/`              | 设计说明、依赖处置、构建与 CI 参考                                                       |
| `docs/decisions/`    | 架构决策记录（ADR）                                                                     |

## 文档

- `docs/` —— 参考材料，英文，与代码一起纳入版本管理。
- `docs/decisions/` —— 事情为什么是现在这样。
- `AGENTS.md` —— 本仓库的工作规则（对人也有用）。
- `CHANGELOG.md` —— 每个发布标签一条，内容与该标签的 release 说明相同。
- `CONTRIBUTING.md` —— `AGENTS.md` 的简明版，面向 pull request。
- `SECURITY.md` —— 如何私下报告问题，以及本仓库的范围。

## 许可证

MIT —— 见 `LICENSE`。被 vendor 和打补丁的第三方代码保留其自身许可证；相应的 NOTICE 文件均已保留。
