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
- 找一个 **vcpkg 的 `node` / libnode port** —— 以 overlay port 形式提供，所有依赖来自同一棵 vcpkg 版本树。
- 要一份 **共享库形态的 Node.js**（`.dll` / `.so` / `.dylib`），由宿主进程加载，而不是把归档链接进可执行文件。
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
| Node.js     | v26.12.1（v26 线）                              |
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

目标是让这个端口表现得像普通的 vcpkg port：用标准 triplet、不需要特殊设置、和别的 port 链在一起也
不出意外。做不到的地方就列在这里并给出原因，而不是留给你在链接时才撞上。

**这里只列由本仓库无法控制的因素造成的限制。** 本仓库打算支持但尚未完成的，是工作项而不是限制：它们
记录在 [issues](https://github.com/hz2769514387/vcpkg-port-node/issues)（构建矩阵归在
[#11](https://github.com/hz2769514387/vcpkg-port-node/issues/11)）以及上面的状态一节里。

### 它是 overlay port，消费它就意味着构建 Node.js

`find_package(unofficial-node CONFIG REQUIRED)` 只有在你的 `vcpkg-configuration.json` 把本仓库
列进 `overlay-ports` 时才能解析成功。这无法回避：V8 是 Node.js 维护的分支、没有外接通道，所以
Node.js 源码树只能在这里构建，而官方 registry 也没有能承载它的机制。

有两个后果值得提前规划，它们都是这个 port 的性质而不是选择：

- **它会构建 Node.js 源码树。** 因此你项目的第一次 configure 要花几十分钟，机器上还需要构建文档里
  列出的东西：`cargo`、Python 3，以及 Windows 上 Visual Studio 2022 或更新版本的 clang-cl 组件
  （端口自己定位 clang-cl 并组装 MSVC 命令行环境，所以*你*要选的仍然只是标准 triplet）。交叉构建
  还要多一样，且容易忽略：**目标架构**的 Rust 标准库 —— 因为 `cargo --target` 会构建 Node.js 的
  Rust crates，而 rustup 只为它安装时的架构提供标准库。例如在 arm64 机器上构建 `x64-osx`：先执行
  `rustup target add x86_64-apple-darwin`。
- **不提供预编译产物。** 二进制缓存能让重复构建变便宜，但没有可以下载的成品来跳过构建。

### macOS 上库的最低系统版本取决于依赖图，而不是 Node.js

Node.js 为 macOS 13.5 构建，这个数字是 Node.js 自己的：它写死在 `common.gypi` 里且没有开关。依赖图
里其他一切都是 vcpkg 的：每个依赖都用 vcpkg 被告知的 deployment target 构建 —— `VCPKG_OSX_DEPLOYMENT_TARGET`，
必须写在 triplet 里，因为没有哪个标准 vcpkg triplet 钉了它 —— 或者在没被告知时用 SDK 的默认值，而
在任何现行机器上那个值都比 13.5 新。因此端口把依赖图的值交给 Node.js 自己的构建（`patches/0018`，
通过 `GYP_DEFINES`），并把 Node.js 的地板值作为下界，让整个库与它的依赖一致，而不是让链接器对每一个
依赖都报警（见它所替代的那条构建日志：`ld: warning: object file (...libicuuc.a[...]) was built for
newer 'macOS' version (15.0) than being linked (13.5)`）。

需要提前规划的是：**交付的库要求的是依赖图的 macOS 版本，默认即 SDK 的版本 —— 不是 Node.js 的 13.5。**
确实需要 13.5 的消费者，在 triplet 里写 `set(VCPKG_OSX_DEPLOYMENT_TARGET 13.5)`，依赖和 Node.js
都会跟随它。

### Windows 需要 Visual Studio 2022 或更新版本

这是 Node.js 的要求，不是本仓库的选择：Node.js 自 v24 起要求 clang-cl，而端口自己声明了 gyp 使用的
Visual Studio 版本（`GYP_MSVS_VERSION=2022`，见 `ports/node/portfile.cmake`），因为 gyp 自带的探测读
的是现代安装不再写入的注册表键。比 Visual Studio 2022 工具集更旧的东西本仓库从未构建或测量过，所以
2022 是地板而不是天花板。`test/` 下的预设因此不指定生成器：CMake 使用机器上最新的 Visual Studio，
而一台最新只有 2019 的机器会在端口的构建里失败（给出 gyp 或编译器的报错），而不是在生成器查找阶段。

### overlay 本仓库会替你整个依赖图替换十九个 registry port

声明 `overlay-ports` 之后，依赖图里每个消费者拿到的都是本仓库对同名 port 的构建。有十九个这样的 port：
zlib 的 Chromium 分支、`simdutf`、`sqlite3`、`simdjson`、`nghttp2`、`llhttp`、`hdr-histogram`、
`ada-url`、`libuv`、`brotli`、`c-ares`、`libffi`、`mbedtls`、`openssl`、`utfcpp`、`frozen`、
`tcb-span`、`lief` 和 `perfetto`。完整表格（每个替换了什么版本、依赖图实际拿到什么、如果你自己还直接
链接那个库会怎样）在 [docs/overlay-replacements.md](docs/overlay-replacements.md)。请先读 `mbedtls`
那一行：overlay 是 4.0，而钉死基线处的 registry 是 3.6，那是破坏性的 API 变化，不是版本号更新。

实际影响面最大的是 zlib 分支：**registry 里有 248 个 port 依赖 `zlib`**，overlay 本仓库的 port 会让
它们全部拿到 Chromium 分支，而不只是 node。在继续消费本 port 的前提下无法选择退出。这是有意的、经过
测量和测试而非假设的，证据与接受的代价写在 `docs/zlib-fork.md` 和 `docs/decisions/` 里。

Node.js 用的不是 madler 的 zlib：它 vendor 了 Chromium 分支，带有 SIMD 的 crc32/adler32 以及上游
从未合并的 inflate/deflate 修正。本仓库就以 `ports/zlib` 交付这个分支，因为 Node.js 的压缩行为和
`process.versions.zlib` 是这个 port 被要求对齐的参照。

### 消费者的配置与 CRT 必须与安装的库一致

这些是 MSVC 的 ABI 规则，不是本 port 的规定：

- **运行库（Runtime library）。** `/MD` 消费者无法链接 `/MT` 的库，反之亦然
  （`LNK2038 RuntimeLibrary mismatch`）。库用哪一个，由安装该 port 的 triplet 通过
  `VCPKG_CRT_LINKAGE` 决定。
- **配置（Configuration）。** Debug 消费者需要 Debug 库：MSVC 的 Debug 配置是 debug CRT
  （`/MTd` 或 `/MDd`）加 `_ITERATOR_DEBUG_LEVEL=2`，而 Release 库携带的是 release 值。只构建
  release 的 triplet 在 `debug/lib` 下什么都不装，所以 Debug 消费者根本无法链接这样的安装。

**Release 和 RelWithDebInfo 对任何安装都可用。** `RelWithDebInfo` 是带完整调试信息的 release ABI，
所以当你真正需要的是调试自己的代码时，用它 —— 你从不会被迫退回 Release。**Debug 需要双配置 triplet**
（标准 triplet，且 `VCPKG_BUILD_TYPE` 未设置），那才会让端口同时构建 Debug 库。

导出的配置在 configure 阶段就检查这两点，并在消息里给出解决办法，而不是让你撞上一整墙的链接错误。

### Windows x64 的 Debug 消费者无法通过 ICU 格式化日期

`new Intl.DateTimeFormat(...)` 会让进程在 ICU 自己的析构函数里中止：

```
debug_heap.cpp(904) : Assertion failed: _CrtIsValidHeapPointer(block)
```

调用路径是 V8 的 `CreateICUDateFormatFromCache` → `icu_78::DateFormatSymbols::initializeData`。
CRT 的调试堆拒绝了 ICU 交给 `free()` 的缓冲区。

范围（2026-10-21 在同一个双配置安装上实测）：

| 消费者 | `Intl.DateTimeFormat` |
|---|---|
| Windows x64，**Debug** | 中止 |
| Windows x64，Release / RelWithDebInfo | 正常 |
| Windows **arm64**，Debug | 正常 |
| 同一安装自带的 `node.exe`，Debug | 正常 |

所以既不是 ICU 也不是 libnode —— 该安装自带的可执行文件在同一个 Debug 库里做同样的调用是正常的。
问题是在同一个进程里把 clang-cl `/MTd` 编译的 Node.js 与 `cl` `/MTd` 编译的 ICU 放在一起，UCRT 会
无条件检查。两个候选机制已排除：ICU 的 Debug 对象确实带 `/DEFAULTLIB:LIBCMTD`（`icuucd.lib` 里有
202 条指令），而 `sizeof(icu::UnicodeString)` 在 `cl` 与 clang-cl、`/MT` 与 `/MTd` 下都是 64。

node24 线撞过完全相同的断言，也以同样方式记录过（`_CrtIsValidHeapPointer` 是无条件检查，清掉
`_CRTDBG_ALLOC_MEM_DF` 没用，对话框会卡住进程）；见 `legacy/node24_vcpkg-2026.07.29` 分支上的
`docs/memory/2026-10-15.md`。

**怎么办：** 如果选 Debug 的理由是调试自己的代码，请改用 `RelWithDebInfo` —— 它是带完整调试信息的
release ABI，本来也是这个 port 推荐的配置。如果你确实需要 Debug CRT 消费者且会调用
`Intl.DateTimeFormat`，目前本仓库这边没有解法。`test/cases/externalization` 在该 cell 上断言数字
格式化，只跳过日期那一半。

### Node.js 在 Windows 用 clang-cl、Linux 用 gcc、macOS 用 clang 编译

那是 Node.js 自己的构建与测试矩阵，本 port 不做更改。*你*用什么编译自己的代码是另一件事，受支持的
声明方式写在你的 preset 里：

| 平台 | 推荐 | 声明方式 |
|---|---|---|
| Windows | `clang-cl` | `toolset: {value: ClangCL, strategy: set}` |
| Linux | `gcc` | `CMAKE_C_COMPILER: gcc`、`CMAKE_CXX_COMPILER: g++` |
| macOS | `clang` | `CMAKE_C_COMPILER: clang`、`CMAKE_CXX_COMPILER: clang++` |

**Windows 上不要用 `CMAKE_CXX_COMPILER` 来要 clang。** Visual Studio 生成器从自己的 toolset 推导
编译器，完全忽略那个变量 —— 无论写裸名字还是完整路径，都没有报错也没有警告，于是你以为在用 clang，
实际拿到的是 `cl.exe`。这是 Visual Studio 2022 / CMake 3.31 上实测的，也是
[ADR 0007](docs/decisions/0007-toolchain-configuration-and-linkage-policy.md) 的全部内容。

其他所有组合 —— Windows 上的 `cl.exe`、Linux 上的 clang、依赖来自一个编译器而可执行文件来自另一个的
混合构建 —— 都是**合法但未验证**的：本仓库既不阻止也不承诺。改这些设置没问题，结果由你承担。注意
Windows 上"混合"是默认状态而非需要主动选择：端口总是用 clang-cl 构建 Node.js，所以不指定 toolset
时你拿到的就已经是"`cl.exe` 可执行文件 + clang-cl 库"。

### 共享库形式的 libnode 必须在运行时可被找到

当 `VCPKG_LIBRARY_LINKAGE=dynamic` 时，交付的是 DLL、`.so` 或 `.dylib`，找到它是消费者的事：Windows
上复制到可执行文件旁边，Unix 上给 target 一个 `BUILD_RPATH`。`test/CMakeLists.txt` 两者都做了，
写成一个小函数可以直接抄。

有两点与静态库不同，且都是刻意的：共享的 `libnode` 已经包含被外接的依赖，所以导出的配置只链接这个库、
**别的什么都不链** —— 再链一次会把每个符号的第二份复制塞进进程 —— 以及 addon 的情况不同，因为原生
addon 绑定的是宿主可执行文件导出的符号。

### 它只与 CMake 集成

端口安装了一份 CMake package config（`unofficial-node`）。没有 pkg-config 文件，也没有其他构建系统
集成，因为交付物是 Node.js 自己的 gyp 构建产出的一组静态归档，而不是单个能被通用工具描述的库。非
CMake 消费者必须手工链接这些归档、被外接的依赖和系统库；生成的配置就是那条链接行的可读描述。

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
