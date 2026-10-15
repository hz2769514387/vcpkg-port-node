# Node.js 依赖全量 vcpkg 化可行性调研（v2 · 增补实证版）

> 调研基线：
>
> - Node.js 源码：`node-v24.21.0`（Node 24 LTS 线）、`node-v26.11.1`（Node 26 线）
> - VCPKG：`C:\work\vcpkg`，2026-07-29 快照（2858 个 port）
> - 数据来源：**全部实测**。Node 侧 = 官方二进制 `process.versions` + 源码版本宏/README + `configure.py` 参数集；vcpkg 侧 = `ports/*/vcpkg.json` + `downloads/` 源码包；**并做了 vcpkg 源码包 ↔ node deps 的逐字节 diff**；社区实践 = 上网抓取 Debian/Ubuntu `debian/rules` 原文 + Node 官方 `BUILDING.md`。
> - 调研日期：2026-10-14（v2 增补 07/08 两章）

## 一、结论速览

**Node 依赖"全量"vcpkg 化不可行，但主体可外接；且官方已提供 24 个 `--shared-*` 外接通道。** v2 相对 v1 最重要的修正：**"不可 vcpkg 化"的清单大幅收缩**——merve/nbytes/uvwasi/lief/ada/simdjson/simdutf/abseil/highway/perfetto/libffi 官方均已支持 externalize，真正的技术天花板只剩 **V8 及其 third_party**（无 `--shared-v8`）。

| 类别                               | 数量(v26) | 处理方式                         |
| -------------------------------- | ------- | ---------------------------- |
| 官方 shared 通道 + vcpkg port 齐备，可外接 | 15+     | `--shared-*` 直接对接 vcpkg port |
| 官方通道在，但 vcpkg 无 port / 版本偏差大     | 6       | overlay-port 自建 或 维持内嵌       |
| 无 shared 通道（V8 树 / node 专属）      | 6       | 必须内嵌                         |
| JS/npm/WASM/Rust 生态              | 8       | 不属 vcpkg                     |

## 二、核心事实链（v2 新增实证，详见各章）

1. **官方 externalize 机制三通道**（[07](./07-官方shared机制与发行版实践.md)）：`--shared-<lib>`（C/C++ 动态库，v26 达 24 个）+ `--shared-builtin-<mod>-path`（JS/WASM 运行时加载）+ `--with-intl=system-icu`（ICU，名字里没有 "shared"）。`--shared` 是"一键全外接"开关（Debian 用它）。
2. **官方立场**（BUILDING.md 原文）：shared 模式定位为"给偏好自行管理依赖的发行版"；**mismatch 可能导致崩溃；Node CI 对这些非常规选项几乎没有覆盖；分发者全责**；依赖 ABI 变化必须申请自定义 `NODE_MODULE_VERSION`。
3. **Debian/Ubuntu 是 shared-deps 的最大生产先例**（[07](./07-官方shared机制与发行版实践.md)）：C/C++ 层全部系统化 + system-icu + JS 层 shared-builtin；同时用 **30+ 条测试 skip/flaky 注解**记录了代价：外部依赖升级→版本报告测试失效、系统 libuv 无法保证禁用 io_uring（CVE-2024-22017）、系统 openssl 3.6.4 破坏 crypto 测试、系统 sqlite 缺 RBU/GEOPOLY 扩展、system-icu 升级导致 Intl 行为不确定。
4. **"版本一致 ≠ 完全等同"有逐字节铁证**（[08](./08-逐字节源码对照验证.md)）：
   - c-ares 1.34.8 / zstd 1.5.7 / ngtcp2 1.25.0 / sqlite 3.53.4：**源码级一致** ✅
   - **libuv 1.52.1：4 处源文件差异**（win fs-event 越界/短路径修复、unix fs.c union 加固等 upstream backport）→ vcpkg 替换将丢失修复 🔴
   - brotli 1.2.0：1 处 platform.h 编译兼容补丁（IA64/attribute）🔶
   - zlib：与 madler 1.3.2 有 24 个文件内容不同（chromium fork：SIMD crc32/adler32）🔴
   - icu：node `icu-small` = full ICU 78.3 的**源码子集 + 完整 data**（127 个非代码文件被裁，data 相同）——行为等价，非"data 更少" ⚠️
5. **Windows 风险实锤**：node BUILDING.md 明确警告 VS/CLion 的 vcpkg 集成会注入 `zlib.lib(zlib1.dll)` 造成**符号重定义链接错误**（issue #24448、vcpkg #37518）。
6. **ada-url simdutf feature 缺失**（[05 §2.8b](./05-特性差异与node-patch深挖.md)）：node 的 ada 内嵌 idna 且启用 `ADA_USE_SIMDUTF=1`（用 v8 内嵌 simdutf 做 IDNA 转码）；vcpkg `ada-url` port **无 simdutf feature**（只有 tools），替换会丢失 SIMD 加速。vcpkg `ada-idna` 有 simdutf feature 但 node 不单独用 ada-idna。
7. **补丁传播与"选边站"**（[05 §4](./05-特性差异与node-patch深挖.md)）：overlay 打补丁会影响 vcpkg 依赖图中所有消费者。libuv（14 个依赖者）/brotli（9 个）补丁是纯 bugfix + ABI 不变，传播风险极低；但 zlib（**248 个依赖者**）/openssl（**198 个**）是依赖图枢纽节点，overlay 它等于"绑架"整个 vcpkg 依赖图 → 不推荐。

## 三、报告导航

| 文档                                                                                                                            | 内容                                                               |
| ----------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| [01-依赖全景与版本总表](01-%E4%BE%9D%E8%B5%96%E5%85%A8%E6%99%AF%E4%B8%8E%E7%89%88%E6%9C%AC%E6%80%BB%E8%A1%A8.md)                       | Node24/26/vcpkg 三方全量对照；v8 third_party 层；依赖拓扑                     |
| [02-node24-vs-vcpkg](02-node24-vs-vcpkg.md)                                                                                   | Node 24 逐项对比（21 个官方 shared 通道点对点）                                |
| [03-node26-vs-vcpkg](03-node26-vs-vcpkg.md)                                                                                   | Node 26 逐项对比（24 个官方 shared 通道点对点）                                |
| [04-vcpkg缺失与overlay-port方案](04-vcpkg%E7%BC%BA%E5%A4%B1%E4%B8%8Eoverlay-port%E6%96%B9%E6%A1%88.md)                             | vcpkg 无 port 库的 overlay vs 内嵌决策矩阵                                |
| [05-特性差异与node-patch深挖](05-%E7%89%B9%E6%80%A7%E5%B7%AE%E5%BC%82%E4%B8%8Enode-patch%E6%B7%B1%E6%8C%96.md)                       | fork/patch/构建配置差异专项分析                                            |
| [06-可行性结论与行动建议](06-%E5%8F%AF%E8%A1%8C%E6%80%A7%E7%BB%93%E8%AE%BA%E4%B8%8E%E8%A1%8C%E5%8A%A8%E5%BB%BA%E8%AE%AE.md)             | 分档结论、三种策略、路线图                                                    |
| [07-官方shared机制与发行版实践](07-%E5%AE%98%E6%96%B9shared%E6%9C%BA%E5%88%B6%E4%B8%8E%E5%8F%91%E8%A1%8C%E7%89%88%E5%AE%9E%E8%B7%B5.md) | **新增**：configure 参数全集、BUILDING.md 责任条款、Debian rules 原文与代价清单、隐性担忧 |
| [08-逐字节源码对照验证](08-%E9%80%90%E5%AD%97%E8%8A%82%E6%BA%90%E7%A0%81%E5%AF%B9%E7%85%A7%E9%AA%8C%E8%AF%81.md)                       | **新增**：vcpkg downloads 源码包 ↔ node deps 的 diff 结果与证据              |

## 四、一页纸结论（v2）

```
官方已有 shared 通道 + vcpkg port 齐备（15 个，v26）：
  openssl ． zlib ． libuv ． cares ． brotli ． zstd ． llhttp(--shared-http-parser) ．
  nghttp2 ． ngtcp2 ． nghttp3 ． sqlite3 ． simdjson ． simdutf ． ada-url ． hdr-histogram ．
  gtest ． icu(system-icu 通道) ． libffi ． lief ． perfetto ． abseil ． highway
  其中源码级 1:1：c-ares 1.34.8 ． zstd 1.5.7 ． ngtcp2 1.25.0 ． sqlite 3.53.4（宏需对齐）
  近似 1:1：libuv（4 处 backport 差异）． brotli（1 处补丁）

官方有通道但 vcpkg 无 port / 收益低（6 个）：
  merve · nbytes · uvwasi（node 主创，overlay 自建成本>收益，建议内嵌）
  LIEF 1.0.0 / perfetto 58.2 / libffi 3.8.0（vcpkg 版本落后 → overlay 或内嵌）

无 shared 通道、必须内嵌（6 个）：
  V8（及其 third_party：abseil/simdutf/highway/dragonbox/fast_float/fp16/rapidhash/
  jsoncpp/siphash/utf8-decoder/wasm-api/ittapi 等）· ncrypto · postject ·
  inspector_protocol · amaro(WASM) · crates(Rust)
  （v8 third_party 中 re2/cpu_features 在 gyp 构建未启用，无需处理）

JS/npm 生态（8 个）：undici · npm · acorn · minimatch · corepack(已移除) · amaro · typescript · crates
```

**推荐策略**：决策应基于"要追求什么"。若追求**与 node 官方二进制行为/安全一致** → 维持内嵌（推荐，Debian 的代价清单证明了外接的隐性成本）；若追求**供应链统一管理** → 参考 Debian 模式做"与 vcpkg baseline 锁版的混合外接"，但要同步接受：版本偏差导致的部分测试失败、CVE 加固差异（io_uring）、性能损失（zlib SIMD）、abandon 官方 CI 保障等。**不建议"全量外接"**——V8 树这一层使得该目标是伪命题。
