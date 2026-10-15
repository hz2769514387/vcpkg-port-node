# 03 · Node 26.11.1 依赖 vs vcpkg(2026-07-29) 逐项对比

> 数据实测日期 2026-10-14。Node 26 相对 Node 24 的变化：新增 `libffi`（node:ffi）、`perfetto`（trace）、`crates`（Rust 清单）、LIEF 升级到 1.0.0、histogram 0.11.10→0.12.0、undici 7→8、simdjson 4.6.7→4.6.11、openssl 3.5.8→3.5.9、simdutf（v8 层）6.4.0→7.7.0；移除 corepack。

## 0. 总览表

| # | 依赖 | node26 版本 | vcpkg | vcpkg 版本 | 判定 |
|---|---|---|---|---|---|
| 1 | libuv | 1.52.1 | `libuv` | 1.52.1 | 🔶 版本一致 / node带4处backport |
| 2 | c-ares | 1.34.8 | `c-ares` | 1.34.8 | ✅ 完全一致 |
| 3 | brotli | 1.2.0 | `brotli` | 1.2.0 | 🔶 版本一致 / node带1处patch |
| 4 | zstd | 1.5.7 | `zstd` | 1.5.7 | ✅ 完全一致 |
| 5 | ngtcp2 | 1.25.0 | `ngtcp2` | 1.25.0 | ✅ 完全一致 |
| 6 | nghttp3 | 1.18.0 | `nghttp3` | 1.18.0 | ✅ 完全一致 |
| 7 | sqlite3 | 3.53.4 | `sqlite3` | 3.53.4 | ⚠️ 版本一致 / 特性需对齐 |
| 8 | icu | 78.3 (small) | `icu` | 78.3 | ⚠️ 版本一致 / 裁剪差异 |
| 9 | openssl | 3.5.9 | `openssl` | 3.6.3 | 🔶 vcpkg +2 minor |
| 10 | nghttp2 | 1.70.0 | `nghttp2` | 1.69.0 | 🔶 node 领先 |
| 11 | llhttp | 9.4.3 | `llhttp` | 9.3.1 | 🔶 node 领先 |
| 12 | simdjson | 4.6.11 | `simdjson` | 4.6.4 | 🔶 node 领先 |
| 13 | ada (ada-url) | 4.0.0 | `ada-url` | 3.4.4 | 🔴 node领先+simdutf feature缺失 |
| 14 | LIEF | **1.0.0** | `lief` | 0.17.6 | 🔶 node 领先 major |
| 15 | libffi | 3.8.0 | `libffi` | 3.7.1 | 🔶 node 领先 |
| 16 | perfetto | 58.2 | `perfetto` | 53.0 | 🔶 node 领先 |
| 17 | histogram | **0.12.0** | `hdr-histogram` | 0.11.10 | 🔶 node 领先 |
| 18 | zlib | 1.3.2.1-motley | `zlib`(madler) | 1.3.2 | 🔴 不同源 fork |
| 19 | googletest | Chromium fork | `gtest` | 1.17.0 | 🔴 不同源 fork |
| 20 | uvwasi | 0.0.23 | — | — | ❌ vcpkg 缺失 |
| 21 | inspector_protocol | rev 1b1bcbbe | — | — | ❌ vcpkg 缺失 |
| 22 | nbytes | 0.1.4 | — | — | ❌ vcpkg 缺失 |
| 23 | ncrypto | 0.0.1 | — | — | ❌ vcpkg 缺失 |
| 24 | merve | 1.2.2 | — | — | ❌ vcpkg 缺失 |
| 25 | amaro | 1.1.11 | — | — | ❌ WASM/npm |
| 26 | postject | — | — | — | ❌ vcpkg 缺失 |
| 27 | crates | Rust 清单 | — | — | ❌ cargo 生态 |
| 28 | npm | 11.20.0 | — | — | ❌ npm 生态 |
| 29 | undici | 8.11.2 | — | — | ❌ npm 生态 |
| 30 | acorn | 8.18.0 | — | — | ❌ npm 生态 |
| 31 | minimatch | 10.2.6 | — | — | ❌ npm 生态 |
| 32 | v8 | 14.6.202.34-node.37 | — | — | ❌ node 维护 fork |

---

## 1. 两组（修订后）

> ⚠️ **本节判定已按 [08](08-逐字节源码对照验证.md) 的逐字节 diff 复核**：原判"libuv/brotli 完全一致"不成立。
> 全部依赖均有官方 `--shared-*` 外接通道（v26 共 24 个，见 [07](07-官方shared机制与发行版实践.md)）。

### 甲组 · 源码级完全一致（3 个 + nghttp3，可直接 `--shared-*` 对接 vcpkg）

### 1.1 c-ares 1.34.8 ✅（`--shared-cares`）
同 node24。vcpkg 缓存包 ↔ node `deps/cares`：除 `.gitignore` 外逐字节一致。**可 1:1 替换**。

### 1.2 zstd 1.5.7 ✅（`--shared-zstd`）
同 node24。0 个源文件差异。

### 1.3 ngtcp2 1.25.0 ✅（`--shared-ngtcp2`）/ nghttp3 1.18.0 ✅（`--shared-nghttp3`）
- **ngtcp2**：vcpkg 缓存包 `lib` 子集 ↔ node `deps/ngtcp2/ngtcp2/lib`：0 差异。
- **nghttp3**：版本一致（1.18.0）；node26 默认构建仍未启用 QUIC（`--experimental-quic`）。
- 注意：vcpkg `ngtcp2` 需选 TLS feature（openssl/gnutls/wolfssl），node 不需要 → **对接时必须 overlay 去 TLS 依赖**。

### 乙组 · 版本号一致但 node 带 patch（2 个，"声称一致"需降级）

### 1.4 libuv 1.52.1 🔶（`--shared-libuv`）
- **逐字节 diff 发现 4 处源文件差异**（详见 [08 §1.2](08-逐字节源码对照验证.md)）：`src/unix/fs.c`（preadv/pwritev 缓存 union 加固）、`src/uv-common.c`（model 释放强转）、`src/win/fs-event.c`（**目录监视越界/短路径修复**）、`src/win/tcp.c`（GetVersionEx 初始化）。
- 这些是 node 从 libuv main 分支 backport 的修复（安全/健壮性）。**用 vcpkg libuv 1.52.1 外接将丢失这些修复**。
- Windows 用户受影响最大（fs-event 越界修复）。**结论：不推荐外接 libuv；若坚持外接，需 overlay 到包含这些修复的 libuv 版本。**

### 1.5 brotli 1.2.0 🔶（`--shared-brotli`）
- 逐字节 diff：仅 `c/common/platform.h` 1 处差异 = **node 补丁**（新增 `BROTLI_TARGET_IA64`、`model/cold` 属性的条件编译保护）。
- x64/ARM 主流平台行为无差异，仅新平台兼容性。**外接风险低，但严格非字节一致。**

---

## 2. 版本一致但特性不同（2 个）

### 2.1 sqlite3 3.53.4 ⚠️（同 node24）
node 开启宏同 node24（详见 [02](./02-node24-vs-vcpkg.md) 2.1），vcpkg `sqlite3` feature 可全覆盖对齐，需显式列 feature 集合并验证行为。

### 2.2 icu 78.3 ⚠️（同 node24）
node26 仍用 icu-small 78.3。"small"指**源码子集**（裁掉 127 个非代码文件），**data 完整保留**（`icudt78l.dat.bz2` 全量）。vcpkg 全量 78.3 与之**行为等价**，差异在产物体积与 data 打包路径。详见 [02](./02-node24-vs-vcpkg.md) 2.2。

---

## 3. 版本偏移组（Node 26 特有变化重点关注）

### 3.1 openssl 3.5.9 vs vcpkg 3.6.3 🔶
- node26 继承 openssl.org 官方 3.5.9（比 node24 的 3.5.8 高一个 patch）。vcpkg 3.6.3 仍领先两个 minor。
- 与 node24 判断一致：vcpkg 更新、可用；若追求"与 node 官方完全一致"则 overlay 固定 3.5.9。

### 3.2 LIEF 1.0.0 vs vcpkg 0.17.6 🔶（node26 独有）
- **Node 26 把 LIEF 从 0.17.x 升级到 1.0.0**（`process.versions.lief = 1.0.0`）。vcpkg `lief` 停留在 0.17.6，**落后一个 major**。
- LIEF 1.0 有破坏性 API 变更（C++ API 重构），但 node 只走 LIEF C API（lief_create_*），实际影响需实测。
- vcpkg `lief` 默认依赖链较重（fmt/frozen/mbedtls/spdlog/tcb-span/tl-expected/utfcpp），node 内嵌的 LIEF 是一份精简源？——需注意 node 的 deps/LIEF 是完整拷贝 + node 的 BUILD.gn。**结论：倾向 overlay 固定 1.0.0，或维持内嵌。**

### 3.3 libffi 3.8.0 vs vcpkg 3.7.1 🔶（node26 新增）
- node26 引入 `node:ffi`（实验性），内嵌 libffi 3.8.0。vcpkg `libffi` 3.7.1 落后 0.0.9。
- libffi 是 3.x 稳定系列，patch 级差异，ABI 稳定。可用 vcpkg 或 overlay 到 3.8.0。

### 3.4 perfetto 58.2 vs vcpkg 53.0 🔶（node26 新增）
- node26 用于 trace（`--trace-http` 等），内嵌 perfetto **58.2**（v8 侧也要 perfetto，node 与 v8 共用一份 deps/perfetto）。vcpkg `perfetto` 53.0 落后 5 个版本。
- perfetto 版本节奏超快（按月发版），vcpkg 永远追不上。**建议维持内嵌**（与 v8 共享源码树，拆出去反而增加同步成本）。

### 3.5 histogram 0.12.0 vs vcpkg hdr-histogram 0.11.10 🔶（node26 独有）
- node26 把 HdrHistogram_c 升到 **0.12.0**；vcpkg `hdr-histogram` 0.11.10（与 node24 一致）。
- patch 级差异。**overlay 固定 0.12.0 即可**；注意 vcpkg port 带 zlib 依赖（log feature）。

### 3.6 nghttp2 1.70.0 / llhttp 9.4.3 / simdjson 4.6.11 / ada-url 4.0.0
均同 node24 判断（node 领先，需 overlay 或等 vcpkg 跟进）。其中 **simdjson：node26 已用 4.6.11**，与 vcpkg 4.6.4 的差距进一步拉大。**ada-url 额外风险**：vcpkg port 缺 simdutf feature（node 启用 `ADA_USE_SIMDUTF=1` 做 IDNA 转码），详见 [02 §3.5](02-node24-vs-vcpkg.md) 和 [05 §2.8b](05-特性差异与node-patch深挖.md)。

---

## 4. 不同源 fork（2 个）

### 4.1 zlib 1.3.2.1-motley-456ae73 🔴
- node26 的 chromium zlib fork 更新到 commit `456ae73`（node24 为 8002e91），版本字符串 1.3.2.1-motley 不变。
- 与 vcpkg madler zlib 1.3.2 的差异及替代分析同 [02](./02-node24-vs-vcpkg.md) 3.7。**推荐维持内嵌**。

### 4.2 googletest（Chromium fork）🔴
- 仅测试用；同 node24。

---

## 5. vcpkg 缺失组（Node 26 特有变化）

| 依赖 | node26 版本 | 说明 | 建议 |
|---|---|---|---|
| uvwasi | 0.0.23 | 无变化 | 内嵌 |
| inspector_protocol | rev 1b1bcbbe | 随 v8 14.6 更新 | 内嵌 |
| nbytes / ncrypto / merve / postject / amaro | 同 node24 | node 主创 | 内嵌 |
| crates | Rust 清单 | node26 新增（WASI 构建可选） | cargo 生态，不属 vcpkg |

## 6. Node 26 汇总

| 判定档 | 数量 | 明细 |
|---|---|---|
| ✅ 可直接 vcpkg（1:1） | 4 | c-ares、zstd、ngtcp2、nghttp3（去 TLS feature） |
| 🔶 版本一致但 node 带 patch | 2 | libuv（4 处 backport）、brotli（1 处 platform.h 补丁） |
| ⚠️ 版本一致但特性需对齐 | 2 | sqlite3、icu（源码子集 vs 全量，行为等价） |
| 🔶 版本偏移可 vcpkg/overlay | 9 | openssl、nghttp2、llhttp、simdjson、ada-url、LIEF、libffi、perfetto、hdr-histogram |
| 🔴 不同源 fork 需评估 | 2 | zlib、googletest |
| ❌ vcpkg 缺失/生态外 | 13 | uvwasi、inspector_protocol、nbytes、ncrypto、merve、amaro、postject、crates、npm、undici、acorn、minimatch、v8 |

> 注：node26 的 histogram 已升到 0.12.0（vcpkg 仍 0.11.10），故归入"版本偏移"组而非"完全一致"组。

**node26 可直接替换 4/32，版本一致但需关注 patch 2/32，特性对齐 2/32，版本偏移 9/32，不同源 fork 2/32，不可/不建议 13/32。** 由于新增 libffi/perfetto/LIEF 三个"node 领先"依赖，node26 相对 node24 的 vcpkg 化难度**略升**。