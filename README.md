# vcpkg-port-node

把 **Node.js v24.21.0 的整棵源码树**（含 V8 与 V8 内嵌的第三方）用**官方 gyp → ninja** 编成**可链接的静态库**，以 vcpkg **overlay port** 的形式交付，并提供 CMake 消费配置。

---

## 项目定位（先读这个）

**本项目是一个 overlay port，不投稿 vcpkg 官方 curated registry。**

理由不是"还不够好"，而是有一项**技术上不可解**的硬限制：

V8 用的是 abseil / highway 的**内部符号**（`container_internal::DeallocateBackingArray`、
`hash_internal::MixingHashState::kSeed` 等），换成 vcpkg 那份会在链接期直接挂（实测 LNK2019）。
而 vcpkg 的核心承诺是"任意端口都能组合安装、不会符号冲突" —— 这一点我们做不到：

> **同一个可执行里不能同时链本端口和 vcpkg 的 `abseil` / `highway`。**

相关背景与实测记录见 `.workbuddy/个人工作流/docs/暂时还没做.md` §5g。

## 已知限制（用之前请确认）

| 限制 | 说明 |
|---|---|
| 内嵌 V8 | 用的是 Node 自带的 V8（Node fork），**不是 vcpkg 的 `v8` 端口**。V8 头文件装在 `include/node-v8/`、可能与 vcpkg 其他端口同名的库装在 `lib/manual-link/`，由消费配置用绝对路径引用 |
| 只交付静态库 | 请求 `VCPKG_LIBRARY_LINKAGE=dynamic` 会被 vcpkg 直接拒绝（结构性不可能） |
| Windows 必须 clang-cl | 需 triplet 把 clang-cl 交接进来（本仓库的 `test/cmake/triplets/` 有一份可抄的参考）；MSVC 口径未经过实测 |
| 不能与 vcpkg 的 abseil / highway 同进程 | 见上面"项目定位" |
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

### 3. CMake 里链接

```cmake
find_package(unofficial-node CONFIG REQUIRED)
target_link_libraries(<你的目标> PRIVATE unofficial::node::node)
```

`unofficial::node::node` 已经把 node 的全部实现与第三方依赖接好，并带好 include 目录（含 V8 头所在的 `include/node-v8`）。

> 为什么是 `unofficial-` 前缀：Node 上游用 gyp、**不提供**官方 CMake config；按 vcpkg 规则，端口自己导出的 config 一律加 `unofficial-` 前缀、目标进 `unofficial::<port>::` 命名空间，这样将来若出现官方 `node` 端口不会撞名。

完整用法见 `ports/node/usage`；一个可跑起来的消费端示例工程在 `test/`（含 ctest）。

## 支持矩阵

| preset | triplet | 口径 | 等级 |
|---|---|---|---|
| `windows-clang-cl` | `x64-windows-static-clang` | clang-cl + 静态 CRT | **Tier 1（硬门）** |
| `linux` | `x64-linux` | gcc，静态库 | **Tier 1（硬门）** |
| `linux-arm64` | `arm64-linux` | gcc，静态库 | Tier 2（允许失败） |
| `windows-clang-cl-arm64` | `arm64-windows-static-clang` | clang-cl + 静态 CRT | Tier 2 |
| `macos` | `arm64-osx` | clang，静态库 | Tier 2 |

全部 release-only（debug 从未实测，见"还没做的事"）。分层含义：

- **Tier 1** —— CI 保证；失败 = 红灯。
- **Tier 2** —— CI 会跑但允许失败：结果不承诺，只用来观察趋势与提前暴露问题。
- 动态库 / 32 位 / mingw / android / ios —— 结构性不支持。

### CI 结构（四个 workflow）

| workflow | 触发 | 跑什么 |
|---|---|---|
| `ci lint` | push + 手工 | 静态红线与语法闸门（与构建口径无关，两边都要跑） |
| `ci debug` | **push**（默认）+ 手工 | 六平台的 **debug** 口径（`NODE_PORT_BUILD_TYPE=debug` + `CMAKE_BUILD_TYPE=Debug`）。debug 从未实测 ⇒ 这几档先 `allow_failure`，修到全绿再升硬门 |
| `ci release` | **只手工** | 六平台的 release 口径（交付口径，由人决定何时测） |
| `platform` | 被上面两个 `workflow_call` | 共享的"单平台 构建 + ctest"作业体，避免两处复制漂移 |

六平台 = x64/arm64 × linux/windows/macos（`x64-osx` 走 `macos-15`，Intel 镜像）。
本机想编 debug：`NODE_PORT_BUILD_TYPE=debug cmake --preset <平台> -DCMAKE_BUILD_TYPE=Debug ...`。

## 构建成本与资源需求

| 项 | 量级 |
|---|---|
| 首次构建耗时 | x64 档约 **30–50 分钟**（V8 是主要耗时）；本机 8 核实测"configure（含 vcpkg 装全部依赖 + 编 node）"约 32 分钟 |
| 内存 | V8 单个编译单元可能要数 GB；并发度建议压到核数（macOS 3 核 runner 上压到 2，否则容易 OOM） |
| 磁盘 | Node 源码树 + 构建产物 + vcpkg 依赖，约 **5–10 GB** |

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
     已经覆盖的库：消费端重复列会让 CMake 去重把组内那份删掉（见 `test/unit/CMakeLists.txt` 里的注释）。

## 还没做的事

见 `.workbuddy/个人工作流/docs/暂时还没做.md`。与采用直接相关的几条：

- 收窄 `vcpkg.json` 的 `supports`（当前声明偏宽）—— 等 arm64 / debug 通过后再做。
- 打 tag / release（版本可追溯）。
- 补 `CONTRIBUTING.md` / `CODE_OF_CONDUCT.md` / `CHANGELOG.md` / `SECURITY.md` 与英文文档。
- debug 口径实测。
- Node 版本升级 checklist 与补丁 rebase 风险标注。
- 与官方 node 的 IDNA / URL 专项验证与性能 benchmark 对比。

## 许可

MIT（见 `LICENSE`）。
