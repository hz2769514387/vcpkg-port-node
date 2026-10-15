# vcpkg-port-node

把 **Node.js v24.21.0 的整棵源码树**（含 V8 与 V8 内嵌的第三方）用**官方 gyp → ninja** 编成**可链接的静态库**，以 vcpkg **overlay port** 的形式交付，并提供 CMake 消费配置。

---

## 项目定位（先读这个）

**本项目是一个 overlay port，不投稿 vcpkg 官方 curated registry。**

理由不是"还不够好"，而是有一项**技术上不可解**的硬限制：

V8 用的是 abseil / highway 的**内部符号**（`container_internal::DeallocateBackingArray`、
`hash_internal::MixingHashState::kSeed` 等），换成 vcpkg 那份会在链接期直接挂（实测 LNK2019）。
所以 **V8 必须用它源码树里自带的那份 abseil / highway** —— 这一点无法改变。

但“不能替换”不等于“不能共存”：实测两侧 abseil 符号名**不相交**（V8 那份无内联命名空间，
vcpkg 那份带 `lts_20260107`，dumpbin 对比求交为 0），所以同一个可执行里再链一份 vcpkg 的
abseil 在**链接层是安全的**，代价是进程里有两份 abseil 运行时。abseil 的 LTS 内联命名空间
正是为“不同版本共存”设计的。

相关背景与实测记录见 `.workbuddy/个人工作流/docs/1014-应然审计-约束-补丁-同类实践.md` §2.1。

## 已知限制（用之前请确认）

| 限制 | 说明 |
|---|---|
| 内嵌 V8 | 用的是 Node 自带的 V8（Node fork），**不是 vcpkg 的 `v8` 端口**。V8 头文件装在 `include/node-v8/`、可能与 vcpkg 其他端口同名的库装在 `lib/manual-link/`，由消费配置用绝对路径引用 |
| 只实现静态库形态 | 请求 `VCPKG_LIBRARY_LINKAGE=dynamic` 会被 vcpkg 直接拒绝。动态交付需要另一套 triplet/口径（动态 CRT + `--shared`），属“未实现”而非“不可能”（Debian/conda 有 `--shared` 先例） |
| Windows 上 node 必须 clang-cl 编 | node 24+ 官方口径（vcbuild.bat 强制），也是 ninja 生成器能编过 DevTools 协议模板的前提。**但编译器与 MSVC 环境由 port 自己准备，消费方用标准 triplet 即可，无需任何自定义 toolchain/triplet** |
| abseil / highway 必须用 V8 自带那份 | 换成 vcpkg 那份会在链接期 LNK2019（同一份 .o 引用 `absl::X` 而库里只有 `lts_20260107::X`）。同进程再链一份 vcpkg abseil 链接层安全（符号不相交），但会有两份运行时 |
| V8 与 Node 版本绑定 | V8 是 Node 源码树的一部分，安全更新依赖 Node 上游的发布节奏，无法独立升降级 |
| 不保证跨大版本 ABI | Node 的 C++ embedder API 本身不保证跨大版本 ABI 兼容，升级大版本请重新编译下游项目 |

## 怎么用

### 1. 作为 overlay port 引用

```jsonc
// vcpkg-configuration.json（你的工程里）
{
  "default-registry": { "kind": "git", "repository": "https://github.com/microsoft/vcpkg", "baseline": "…" },
  "overlay-ports": [ "…/vcpkg-port-node/ports" ]
}
```

### 2. manifest 里声明依赖

```jsonc
{
  "dependencies": [ { "name": "node", "features": ["tools", "test-suite"] } ]
}
```

`tools` = node 可执行与 npm / npx / corepack；`test-suite` = Node 官方测试套件（约 80 MB，用于真跑官方用例）。两者都是可选的。

### 3. 用标准 triplet 构建你的工程

**不需要任何自定义 triplet / toolchain。** Windows 上 node 由 clang-cl 编译（node 24+ 官方口径），
但编译器与 MSVC 命令行环境由 port 自己准备。直接用 vcpkg 自带的标准 triplet：

| 平台 | triplet | 说明 |
|---|---|---|
| Windows x64 | `x64-windows-static` | 静态 CRT + 静态库 + **双份**（Release+Debug） |
| Windows x64（只要 release） | `x64-windows-static-release` | 只编 Release，省一半构建时间 |
| Windows x64（动态 CRT） | `x64-windows` | /MD 口径同样支持 |
| Windows arm64 | `arm64-windows-static` | 同上，也有 `-release` 变体 |
| Linux x64 / arm64 | `x64-linux` / `arm64-linux` | gcc，静态库 |
| macOS arm64 / x64 | `arm64-osx` / `x64-osx` | clang，静态库 |

构建口径跟随 triplet：`VCPKG_BUILD_TYPE` 不设 ⇒ port 编 Release + Debug 两份
（debug 库按 vcpkg 惯例进 `debug/lib/`），消费方 Debug/Release 都原生可用；
`VCPKG_CRT_LINKAGE` 决定 /MT 还是 /MD。

### 4. CMake 里链接

```cmake
find_package(unofficial-node CONFIG REQUIRED)
target_link_libraries(<你的目标> PRIVATE unofficial::node::node)
```

`unofficial::node::node` 已经把 node 的全部实现与第三方依赖接好，并带好 include 目录
（含 V8 头所在的 `include/node-v8`）。Windows 上平台兼容性清单（`/MANIFEST:EMBED` 等）、
栈大小（`/STACK:`）、clang compiler-rt 内建库也都由导出配置自动带上 —— 不需要手抄任何片段。
**C++20 也由它声明**（`INTERFACE_COMPILE_FEATURES cxx_std_20`；MSVC 另自动加
`/Zc:__cplusplus`，因为 cl.exe 默认把 `__cplusplus` 报成 199711L）—— 你不用自己写
`target_compile_features(... cxx_std_20)`。

> Windows 上还有两件**任何 CMake 工程都要做**、本 port 替不掉的事（2026-10-15 实测，
> 两条都是配置期就红、报错点离真因很远）：
> 1. **MSVC 命令行环境** —— vcpkg 只给 **port 构建**摆环境；你的 cmake 若在裸 shell 里跑
>    就没有 `cl.exe` / `rc.exe` / `LIB` / `INCLUDE`。请在 VS 开发者命令行（或任何已
>    `vcvarsall` 过的 shell）里配置与构建。
> 2. **`CMAKE_MSVC_RUNTIME_LIBRARY` 要自己给** —— 设 `/MT` 的那份 vcpkg 脚本
>    （`scripts/toolchains/windows.cmake`）只作用于 port 构建，消费端的 cmake 不会加载它
>    ⇒ 默认值 `/MD` 与 node 的 `/MT` 在链接期喷一整屏 LNK2038。静态 CRT triplet 时请设
>    `set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")`
>    （`*-static-md` / `x64-windows` 这类动态 CRT 口径别设，默认 /MD 正好一致）。
>    忘了设会在 `find_package` 处直接得到一条写明了该设什么的 FATAL。

> 为什么是 `unofficial-` 前缀：Node 上游用 gyp、**不提供**官方 CMake config；按 vcpkg 规则，端口自己导出的 config 一律加 `unofficial-` 前缀、目标进 `unofficial::<port>::` 命名空间，这样将来若出现官方 `node` 端口不会撞名。

完整用法见 `ports/node/usage`；一个可跑起来的消费端示例工程在 `test/`（含 ctest）。

## 支持矩阵

| preset | triplet | 口径 | 等级 |
|---|---|---|---|
| `windows` | `x64-windows-static` / `-release` | 静态 CRT + 静态库；node clang-cl | 硬门 |
| `linux` | `x64-linux` / `-release` | gcc，静态库 | 硬门 |
| `linux-arm64` | `arm64-linux` / `-release` | gcc，静态库 | 硬门 |
| `windows-arm64` | `arm64-windows-static` / `-release` | 静态 CRT + 静态库；node clang-cl | 硬门 |
| `macos` | `arm64-osx` / `-release` | clang，静态库 | 硬门 |
| `macos-x64` | `x64-osx` / `-release` | clang，静态库 | 硬门（macos-15 arm64 + Rosetta） |

2026-10-14 起六个平台**全部硬门**（`allow_failure: false`）：debug 首跑六腿全红、逐条修完后
用户拍板升硬门 —— 开发期不对消费方承诺接口稳定，红了就修。分层含义：

- **硬门** —— CI 保证；失败 = 红灯。
- 动态库交付 / 32 位 / mingw / android / ios —— 结构性不支持或未实现。

### CI 结构（四个 workflow）

| workflow | 触发 | 跑什么 |
|---|---|---|
| `ci lint` | push + 手工 | 静态红线与语法闸门（与构建口径无关，两边都要跑） |
| `ci debug` | **push**（默认）+ 手工 | 六平台的 **debug 口径**：双份 triplet + 消费端 `CMAKE_BUILD_TYPE=Debug`（port 编两份，链 debug 库）。六腿全部硬门（2026-10-14 起） |
| `ci release` | **只手工** | 六平台的 release 口径（交付口径，由人决定何时测）：`*-release` triplet，只编 Release |
| `platform` | 被上面两个 `workflow_call` | 共享的"单平台 构建 + ctest"作业体，避免两处复制漂移 |

六平台 = x64/arm64 × linux/windows/macos（`x64-osx` 走 `macos-15`，arm64 镜像 +
Rosetta 跑 x86_64 产物；交叉口径见 `test/README.md`）。
本机想编 debug：双份 triplet + `cmake --preset windows -DCMAKE_BUILD_TYPE=Debug ...`。
动态 CRT（/MD）口径已支持（`VCPKG_CRT_LINKAGE=dynamic`），CI 覆盖列为后续项。

## 构建成本与资源需求

| 项 | 量级 |
|---|---|
| 首次构建耗时 | x64 档约 **30–50 分钟**（V8 是主要耗时）；本机 8 核实测"configure（含 vcpkg 装全部依赖 + 编 node）"约 32 分钟 |
| 内存 | V8 单个编译单元可能要数 GB；并发度建议压到核数（macOS 3 核 runner 上压到 2，否则容易 OOM） |
| 磁盘 | Node 源码树 + 构建产物 + vcpkg 依赖，约 **5–10 GB**；**双份构建（Release+Debug）约翻倍** |

改 port（portfile / 补丁 / vcpkg.json）会改变 vcpkg 的 ABI 哈希 ⇒ **下一次会重编整个 node**，
但**依赖不会重编**（实测：日志里只 `Removing/Installing node`，依赖全部命中）。所以改 port 前值得先把多次改动攒起来。

## 已验证环境矩阵

| 组件 | 版本 |
|---|---|
| vcpkg | 2026.07.29（CI 钉死；vcpkg 的脚本要求 **CMake ≥ 4.x**，这是 vcpkg 侧的要求，不是本 port 的） |
| CMake（消费端） | ≥ 3.13（Windows），≥ 3.24（GNU 系，`$<LINK_GROUP>` 需要） |
| 编译器 | Windows: clang-cl（VS 自带 LLVM 或独立 LLVM 均可）；Linux: gcc；macOS: clang |
| runner | `windows-latest`、`ubuntu-latest`、`ubuntu-24.04-arm`、`macos-latest`、`windows-11-arm` |

## 构建失败时看哪里

1. **port 自己的日志**：`$VCPKG_ROOT/buildtrees/node/{configure,build}-out.log`。
2. **消费端工程**：CI 里 `test-build.log` 与 `ctest.log`（都已归档）。
3. **常见错误**：
   - 找不到 clang-cl → 用把 clang-cl 交接进来的 triplet（见 `test/cmake/triplets/`）。
   - CMake 主版本 < 4 → vcpkg 侧的要求，请升级 CMake。
   - 链接期一堆 `undefined reference`（GNU 系）→ 检查是不是重复链了 `unofficial::node::node`
     已经覆盖的库：消费端重复列会让 CMake 去重把组内那份删掉（见 `test/example_coexist/CMakeLists.txt` 里的注释）。

## 还没做的事

见 `.workbuddy/个人工作流/docs/暂时还没做.md`（当前主线是文末《大规模重构：消费端解放与依赖策略》）。与采用直接相关的几条：

- 收窄 `vcpkg.json` 的 `supports`（当前声明偏宽）—— 等 arm64 / debug 通过后再做。
- 打 tag / release（版本可追溯）。
- 补 `CONTRIBUTING.md` / `CODE_OF_CONDUCT.md` / `CHANGELOG.md` / `SECURITY.md` 与英文文档。
- 依赖策略：libuv 的 4 处 node backport 丢失、ada-url 版本/特性差、zlib SIMD 差异（见欠账清单 R5）。
- 动态 CRT（/MD）口径的 CI 覆盖腿；CI 二进制缓存（欠账清单 R8）。
- Node 版本升级 checklist 与补丁 rebase 风险标注。
- 与官方 node 的 IDNA / URL 专项验证与性能 benchmark 对比。

## 许可

MIT（见 `LICENSE`）。
