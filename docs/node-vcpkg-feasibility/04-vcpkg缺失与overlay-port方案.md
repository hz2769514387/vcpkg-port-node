# 04 · vcpkg 缺失库清单与 overlay-port 决策

## 0. 背景：vcpkg 补充机制

vcpkg 允许通过 **overlay-ports**（`VCPKG_OVERLAY_PORTS` 指向的目录）提供 vcpkg 官方 registry 之外的 port；也允许用 **baseline/versions + `--overlay-ports`** 固定特定版本。因此"vcpkg 没有此 port"≠"无法 vcpkg 化"，而是"要么自建 port 维护一个第三方库的构建+版本，要么继续内嵌"。本调研对每个缺失库给出**成本-收益**判断。

## 1. vcpkg 缺失库逐项分析

### 1.1 Node 主创 / 内部项目（无 vcpkg port，且基本无社区维护版本）

| 库 | 版本 | 用途 | 是否值得自制 overlay-port |
|---|---|---|---|
| **uvwasi** | 0.0.23 | WASI 实现（node:wasm 用)；基于 libuv，2023 年后上游几乎无更新 | ❌ 不值。库几乎冻结，自制 port 无收益；它关联 node 的 WASI ABI，node 尽量保持自控 |
| **nbytes** | 0.1.4 | Node webcrypto 字节解析（release-please 自动发版） | ❌ 不值。nodejs org 内部库，几乎只有 node 用 |
| **ncrypto** | 0.0.1 | OpenSSL C++ 封装层（node 独有） | ❌ 不值。强耦合 node 的 openssl 定制 |
| **merve** | 1.2.2 | ESM named-export 探测（C++），随 node 仓库维护 | ❌ 不值。node 仓库内嵌，外部无消费场景 |
| **postject** | （工具） | SEA（single executable）注入工具 + C API | ❌ 不值。JS/C 混合工具，node 自控 |
| **inspector_protocol** | rev 随 v8 | chromium 代码生成器（生成 v8inspector 协议代码） | ❌ 不值。与 v8 版本树强绑定，同步窗口按周计 |

> 共性：这些库要么"只服务于 node"，要么"只服务于 v8"，要么"上游死水"。自制 overlay-port 的维护成本（跟踪上游、构建矩阵、测试）**超过收益**。→ **一律维持内嵌**，但在供应链管理上可为其建立"vendor 版本清单"（记录 vendored commit/version）。

> ⚠️ **重要澄清**：uvwasi / nbytes / ncrypto / merve / postject 在 node26 的 configure 中**均有对应的 `--shared-*` 外接通道**（`--shared-uvwasi` / `--shared-ncrypto` / `--shared-merve` / `--shared-nbytes` / `--shared-postject`）。因此"必须内嵌"的根因不是"node 不让外接"，而是 **"vcpkg 无对应 port + 自制 overlay 收益为负"**。若供应链策略要求强制外接，技术上通道是通的，只需自建 port 并承担维护成本。详见 [07](07-官方shared机制与发行版实践.md)。

### 1.2 WASM / 语言生态（不属于 C/C++ 包管理）

| 库 | 版本 | 说明 |
|---|---|---|
| **amaro** | 1.1.11 | SWC 编译产物 + JS glue（WASM 二进制，npm 分发），node 直接内嵌文件 |
| **crates/**（node26） | Rust 清单 | cargo 生态，用于可选 WASI（`--experimental-wasi`）构建 |

→ 走各自生态（npm / cargo），**vcpkg 化无意义**。

### 1.3 V8 third_party 中 vcpkg 缺失的小型/内部库

| 库 | 版本 | 说明 | 建议 |
|---|---|---|---|
| **dragonbox**（node26 新增） | 1.1.3 | v8 浮点格式化（v8 源码树 vendored，非 chromium deps 引用） | 内嵌（随 v8） |
| **ittapi** | Intel 内置 | gyp 构建未启用，Intel VTune 支持垫片 | 内嵌（不参与构建亦可忽略） |
| **siphash** | v8 内置 | 哈希算法头文件 | 内嵌 |
| **utf8-decoder** | 2010 静态头 | DFA UTF-8 解码器 | 内嵌 |
| **wasm-api** | commit debd0908 | wasm-c-api 头文件集 | 内嵌 |
| **re2** | （无源码） | gyp 构建不启用；GN 构建才需要 | 无需处理（node 构建不触发） |
| **cpu_features** | （v0.8.0 声明） | 同上，gyp 不启用 | 无需处理 |
| **glut 等平台垫片** | glibc/valgrind/vtune/llvm-libc/fuchsia-sdk/zoslib | 平台/工具链辅助 | 不属于交付依赖 |
| **jinja2/markupsafe/colorama** | — | Python 构建链（GN 骨架生成） | 走 pip（node/tools 或 v8 构建时 pip install），不属 vcpkg |

### 1.4 有对应 port 但名字/来源易混淆的（用户特别提示）

| Node 里的库 | 实际对应 vcpkg port | 易混淆的错误 port |
|---|---|---|
| ada（URL 解析器） | **`ada-url`**（3.4.4） | ⚠️ `ada-idna`（0.6.0）是独立 IDNA 库（`ada-url/idna` 仓库拆出），node 不单独使用——**node 的 ada-url 内嵌了 idna 代码**（`ada.cpp` 含 `namespace ada::idna`）。注意：vcpkg `ada-url` **无 simdutf feature**，vcpkg `ada-idna` **有 simdutf feature**；node 启用 `ADA_USE_SIMDUTF=1`，详见 [05 §2.8b](05-特性差异与node-patch深挖.md) |
| histogram（HdrHistogram_c） | **`hdr-histogram`**（0.11.10） | ⚠️ 不要找 `histogram`（vcpkg 无此名） |
| cares | **`c-ares`** | ⚠️ 不要找 `cares` |
| sqlite | **`sqlite3`** | ⚠️ 不要找 `sqlite`（vcpkg 无） |
| uv | **`libuv`** | ⚠️ 不要找 `uv` |
| libffi | **`libffi`** | ✓ 已正确 |
| gtest | **`gtest`**（官方版） | ⚠️ node 用 chromium fork |

## 2. overlay-port vs 内嵌 决策矩阵

| 维度 | 二层信号 | 决策 |
|---|---|---|
| 上游活跃度 | 活跃（每月发版）且 node 领先 | **overlay-port**（eg. simdjson、llhttp、ada-url）或接受 vcpkg 偏移 |
| 上游活跃度 | 冻结/低活跃 | **内嵌**（eg. uvwasi、fp16、utf8-decoder） |
| 与 v8/构建树耦合 | 强（随 v8 同步）+ 源码同树 | **内嵌**（eg. inspector_protocol、abseil、simdutf、dragonbox） |
| node 有专属 patch/fork | 有（eg. zlib chromium fork、merve/nbytes/ncrypto 主创） | **内嵌** |
| 仅测试用 | googletest、jsoncpp（v8 测试） | **内嵌**（无运行时收益） |
| 纯构建链工具 | glibc/valgrind/vtune/python 链 | **内嵌/工具链** |
| JS/WASM/Rust | amaro、npm、undici、crates | **各自生态** |

## 3. 若坚持"缺 port 也 vcpkg 化"：哪些可低成本自制 overlay-port？

按成本从低到高排序（仅建议，不强制）：

1. **hdr-histogram 0.12.0**（node26）——纯 C 库，portfile ~30 行，可直接参照官方 0.11.10 port 改版本。
2. **ada-url 4.0.0**——upstream 有现成 CMake，依赖极少（可关 tests），portfile 简单；这是"名字对齐 + 版本强制"最值得做的。
3. **nghttp2 1.70.0 / llhttp 9.4.3 / simdjson 4.6.7+**——都是标准 CMake 工程，改 REF/SHA512 即可，但 node 领先的版本 vcpkg 通常下月跟进，**未必值得长期维护**。
4. **openssl 3.5.9（若要求精确对齐）**——vcpkg 自身对 openssl 支持极成熟，但要 pin 到 3.5.9 需要 `--x-package` overlay；建议直接接受 3.6.3 或等 vcpkg baseline 更新（openssl 是 port 生态核心，overlay 它影响面大）。
5. **libffi 3.8.0 / perfetto 58.2**——libffi 易做；perfetto 因与 v8 共享源码树，不推荐 overlay。
6. **zlib（chromium fork）**——**唯一"不同源"且能显著影响运行时（性能/行为）的库**。若要 vcpkg 化：overlay 一个 `chromium-zlib` port（上游 chromium `third_party/zlib`，含 node-specific commit），或评估 zlib-ng 兼容替代。推荐维持内嵌。

## 4. vcpkg 版本固定机制小结（应对"node 领先"场景）

- **baseline 固定**：`vcpkg.json` 的 `vcpkg-configuration` 用 `registries` + `baseline` 锁版本，可整体锁定 2026-07-29 快照（本调研 vcpkg）。
- **版本格式约束**：`version >= 1.70.0#1`（nghttp2）这类约束在 `vcpkg.json` 中不支持任意范围；"node 领先"版本只能靠 **overlay-ports 提供新版 port 文件**或接受 vcpkg 侧更新的延迟。
- 对"node 领先"类依赖（llhttp/nghttp2/simdjson/ada-url），若坚持完全一致，**overlay-port 是唯一途径**；对 vcpkg 领先类（openssl/simdutf）则**无需动作**。