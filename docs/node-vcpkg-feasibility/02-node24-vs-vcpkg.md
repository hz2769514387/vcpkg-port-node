# 02 · Node 24.21.0 依赖 vs vcpkg(2026-07-29) 逐项对比

> 数据实测日期 2026-10-14。版本一致性判定 = "完全一致 / 版本差 / 来源不同 / 特性不同 / vcpkg 缺失"五档。

## 0. 总览表

| # | 依赖 | node24 版本 | vcpkg | vcpkg 版本 | 判定 |
|---|---|---|---|---|---|
| 1 | libuv | 1.52.1 | `libuv` | 1.52.1 | 🔶 版本一致 / node带4处backport |
| 2 | c-ares | 1.34.8 | `c-ares` | 1.34.8 | ✅ 完全一致 |
| 3 | brotli | 1.2.0 | `brotli` | 1.2.0 | 🔶 版本一致 / node带1处patch |
| 4 | zstd | 1.5.7 | `zstd` | 1.5.7 | ✅ 完全一致 |
| 5 | ngtcp2 | 1.25.0 | `ngtcp2` | 1.25.0 | ✅ 完全一致 |
| 6 | nghttp3 | 1.18.0 | `nghttp3` | 1.18.0 | ✅ 完全一致 |
| 7 | sqlite3 | 3.53.4 | `sqlite3` | 3.53.4 | ⚠️ 版本一致 / 特性需对齐 |
| 8 | icu | 78.3 (small) | `icu` | 78.3 | ⚠️ 版本一致 / 裁剪差异 |
| 9 | hdr-histogram | 0.11.10 | `hdr-histogram` | 0.11.10 | ✅ 完全一致 |
| 10 | openssl | 3.5.8 | `openssl` | 3.6.3 | 🔶 vcpkg +2 minor |
| 11 | nghttp2 | 1.70.0 | `nghttp2` | 1.69.0 | 🔶 node 领先 |
| 12 | llhttp | 9.4.3 | `llhttp` | 9.3.1 | 🔶 node 领先 |
| 13 | simdjson | 4.6.7 | `simdjson` | 4.6.4 | 🔶 node 领先 |
| 14 | ada (ada-url) | 4.0.0 | `ada-url` | 3.4.4 | 🔴 node领先+simdutf feature缺失 |
| 15 | LIEF | 0.17.0 | `lief` | 0.17.6 | 🔶 vcpkg 领先 |
| 16 | zlib | 1.3.2.1-motley | `zlib`(madler) | 1.3.2 | 🔴 不同源 fork |
| 17 | googletest | Chromium fork | `gtest` | 1.17.0 | 🔴 不同源 fork |
| 18 | uvwasi | 0.0.23 | — | — | ❌ vcpkg 缺失 |
| 19 | inspector_protocol | rev 69d69ddf | — | — | ❌ vcpkg 缺失 |
| 20 | nbytes | 0.1.4 | — | — | ❌ vcpkg 缺失 |
| 21 | ncrypto | 0.0.1 | — | — | ❌ vcpkg 缺失 |
| 22 | merve | 1.2.2 | — | — | ❌ vcpkg 缺失 |
| 23 | amaro | 1.1.11 | — | — | ❌ WASM/npm |
| 24 | postject | — | — | — | ❌ vcpkg 缺失 |
| 25 | corepack | 0.36.0 | — | — | ❌ npm 生态 |
| 26 | npm | 11.19.0 | — | — | ❌ npm 生态 |
| 27 | undici | 7.29.1 | — | — | ❌ npm 生态 |
| 28 | acorn | 8.18.0 | — | — | ❌ npm 生态 |
| 29 | minimatch | 10.2.6 | — | — | ❌ npm 生态 |
| 30 | v8 | 13.6.233.17-node.53 | — | — | ❌ node 维护 fork |

---

> ⚠️ **本节判定已按 [08](08-逐字节源码对照验证.md) 的逐字节 diff 复核**：原判"libuv/brotli 完全一致"不成立。
> 全部依赖均有官方 `--shared-*` 外接通道（v24 共 21 个，见 [07](07-官方shared机制与发行版实践.md)）。

## 1. 两组（修订后）

### 甲组 · 源码级完全一致（4 个 + nghttp3，可直接 `--shared-*` 对接 vcpkg）

### 1.1 c-ares 1.34.8 ✅（`--shared-cares`）
- vcpkg 缓存包 `c-ares-c-ares-v1.34.8` ↔ node `deps/cares`：**除 `.gitignore` 外逐字节一致**（node-only 8 个构建文件、up-only 12 个文档/测试）。
- vcpkg feature `tool` 不需要。**可 1:1 替换**。

### 1.2 zstd 1.5.7 ✅（`--shared-zstd`）
- vcpkg 缓存包 `facebook-zstd-v1.5.7` ↔ node `deps/zstd`：**0 个源文件差异**（仅构建文件与文档差异）。

### 1.3 ngtcp2 1.25.0 ✅（`--shared-ngtcp2`）/ nghttp3 1.18.0 ✅（`--shared-nghttp3`）
- **ngtcp2**：vcpkg 缓存包 `ngtcp2-ngtcp2-v1.25.0/lib` ↔ node `deps/ngtcp2/ngtcp2/lib`：**0 差异**（node 只取 lib+crypto 子集，唯一多出的是编译生成的 version.h）。
- **nghttp3**：版本一致（1.18.0）；本机 vcpkg 缓存是 1.16.0（旧产物），字节级对照未完成，风险低。
- 注意：vcpkg `ngtcp2` 需选 TLS feature（openssl/gnutls/wolfssl），node 用的是无 TLS 后端实现 → **对接时必须 overlay 去 TLS 依赖**。

### 1.4 hdr-histogram 0.11.10 ✅（`--shared-hdr-histogram`）
- node24 与 vcpkg 一致（0.11.10）。vcpkg port 带 `zlib` 依赖（log feature），按需 overlay。

### 乙组 · 版本号一致但 node 带 patch（2 个，"声称一致"需降级）

### 1.5 libuv 1.52.1 🔶（`--shared-libuv`）
- **逐字节 diff 发现 4 处源文件差异**（详见 [08 §1.2](08-逐字节源码对照验证.md)）：`src/unix/fs.c`（preadv/pwritev 缓存 union 加固）、`src/uv-common.c`（model 释放强转）、`src/win/fs-event.c`（**目录监视越界/短路径修复**）、`src/win/tcp.c`（GetVersionEx 初始化）。
- 这些是 node 从 libuv main 分支 backport 的修复（安全/健壮性）。**用 vcpkg libuv 1.52.1 外接将丢失这些修复**。
- Windows 用户受影响最大（fs-event 越界修复）。**结论：不推荐外接 libuv；若坚持外接，需 overlay 到包含这些修复的 libuv 版本。**

### 1.6 brotli 1.2.0 🔶（`--shared-brotli`）
- 逐字节 diff：仅 `c/common/platform.h` 1 处差异 = **node 补丁**（新增 `BROTLI_TARGET_IA64`、`model/cold` 属性的条件编译保护）。
- x64/ARM 主流平台行为无差异，仅新平台兼容性。**外接风险低，但严格非字节一致。**

---

## 2. 版本一致但特性有差异（需对齐后可用）

### 2.1 sqlite3 3.53.4 ⚠️
- 版本一致（都是 3.53.4，node 的 `deps/sqlite` 是 amalgamation 源码）。
- **node 编译时开启的宏（实测自 node24 gyp 配置）**：
  `SQLITE_ENABLE_COLUMN_METADATA / DBSTAT_VTAB / FTS / GEOPOLY / MATH_FUNCTIONS / PERCENTILE / PREUPDATE_HOOK / RBU / RTREE / SESSION`
- **vcpkg `sqlite3` 对应 feature**：`dbstat / fts3 / fts4 / fts5 / geopoly / math / percentile / rtree / session / dbpage-vtab / json1 / ...` —— **全部可通过 feature 对齐**。
- 差异点：vcpkg 默认不带上述 feature（默认只开 json1 等基础项），需要显式 `--x-feature=...` 开启；且 node 还设置了 `SQLITE_DEFAULT_MEMSTATUS` 等基础配置。**结论：用 vcpkg sqlite3 + features 对齐可行，但需要固定 feature 集合并做行为验证**。

### 2.2 icu 78.3 ⚠️
- 版本一致（U_ICU_VERSION 78.3）。
- **关键差异**：node 使用 **icu-small**（`deps/icu-small`），但"small"指**源码子集**而非数据量。实测 `deps/icu-small/README-FULL-ICU.txt` 明确说明"This directory contains ICU subset used by --with-intl=full-icu"：裁掉的是 127 个非代码文件（Makefile.in / sources.txt / python 工具 / 数据生成输入），**data 完整保留**（`icudt78l.dat.bz2` 全量数据包）。node 官方二进制默认 `--with-intl=full-icu`（不是 small-icu）。
- vcpkg `icu` 是**全量 ICU 78.3**（含全部源码 + 全部 data + tools）。与 node icu-small **行为等价**（同一版本、同一数据），差异仅在构建产物面积与源码树体积。
- **结论：可替换，行为等价；vcpkg 全量 ICU 产物体积 ≥400MB vs node icu-small 源码树（data 约 30MB），产物体积与构建行为（data 打包路径）需专项处理**。

---

## 3. 版本有偏移（12 个，可用 vcpkg 版本控制 fixed/overlay）

### 3.1 openssl 3.5.8 vs vcpkg 3.6.3 🔶
- node24 用 openssl.org 官方 **3.5.8**（3.5 系已合并 QUIC API；node 文档中 quictls 的引用已过时）。
- vcpkg 是 **3.6.3**，领先两个 minor。
- 风险：**安全修复级别**（用 3.6.3 不低于 3.5.8 ✓），但 **node 的 `node:crypto` 依赖 openssl 具体行为/错误消息**，跨 minor 更新属于"换新版本"，需完整测试。node 官方 `--shared-openssl` 也不要求精确版本，但 LTS 行为验证以官方内置版本为准。
- vcpkg 的 openssl feature 有 `fips / ssl3 / tools / weak-ssl-ciphers`；node 不需要 fips/ssl3（node 无 SSLv3），静态链接时建议 feature=off。
- **结论：可替换（vcpkg 更新），或 overlay 固定 3.5.9；生产环境建议跟随 node LTS 验证的版本。**

### 3.2 nghttp2 1.70.0 vs 1.69.0 🔶
- node 领先一个小版本。vcpkg 可用 `--x-package-nghttp2@1.70.0` overlay 或等 vcpkg 跟进。差异小（patch 级）。

### 3.3 llhttp 9.4.3 vs 9.3.1 🔶
- llhttp 是 **nodejs 组织维护的项目**，node 与其同版本节奏极快。vcpkg 的 llhttp 落后。
- **注意**：llhttp 使用 C API 且 node 直接内嵌其生成代码（`deps/llhttp` 是源码 + node 的 BUILD.gn/gyp）。vcpkg 的 llhttp 由 cmake 构建，提供 `libllhttp`。**替换需 overlay 固定 9.4.3**。

### 3.4 simdjson 4.6.7 vs vcpkg 4.6.4 🔶
- node 领先 3 个 patch。vcpkg `simdjson` 有 feature：`deprecated / exceptions / threads / utf8-validation`。node 编译 simdjson 时关闭 exceptions/threads/deprecated？需与 node 现有 DOM 行为验证。**倾向 overlay 固定**。

### 3.5 ada 4.0.0 vs vcpkg ada-url 3.4.4 🔴
- **node 的 `deps/ada` 就是 ada-url 项目**（`github.com/ada-url/ada`）。vcpkg 里注意名字不同：`ada-url`（不是 `ada`，也不是 `ada-idna`——ada-idna 是独立 IDNA 库，node 不单独使用）。
- 版本差：node 领先 **1 个 major**。node 的 `url` 模块强依赖 ada 的 exact 行为，**必须用 overlay 固定 4.0.0**。
- **⚠️ simdutf feature 缺失（重要遗漏）**：node 的 ada 内嵌了 idna 代码且**启用了 `ADA_USE_SIMDUTF=1`**（`ada.gyp:16`），用 v8 内嵌的 simdutf 做 IDNA 转码。vcpkg `ada-url` port **没有 simdutf feature**（只有 tools），CMake 默认 `ADA_USE_SIMDUTF=OFF`。用 vcpkg ada-url 替换会**丢失 SIMD 加速的 IDNA 转码**。修复需 overlay 加 simdutf feature（参照 `ada-idna` portfile），但 simdutf 版本又成问题（vcpkg 8.2.0 vs v8 内嵌 6.4.0）。详见 [05 §2.8b](05-特性差异与node-patch深挖.md)。
- **结论：风险高于此前评估。建议维持内嵌；若 overlay 必须同时加 simdutf feature + 固定 simdutf 版本。**

### 3.6 LIEF 0.17.0 vs vcpkg 0.17.6 🔶
- node24 用 0.17.0，vcpkg 0.17.6 略新（patch 级，行为兼容概率高）。
- LIEF 在 node 中服务于 **node:sea（Single Executable）**，构建时可选。vcpkg `lief` feature 很多（c-api / dex / oat / vdex / enable-json ...），node 需要 **C API + PE/ELF/Mach-O 解析**，vcpkg 默认 feature 集需调整。
- **结论：可替换但需裁剪 vcpkg feature 集**，或 overlay 到 0.17.0。

### 3.7 zlib 1.3.2.1-motley vs vcpkg zlib 1.3.2（madler）🔴
- **此差异最重要**：node24 的 zlib 是 **Chromium zlib fork**，版本字符串自带 `-motley-<sha>`（node24: 8002e91）。
- Chromium fork 相对 madler 1.3.2 的改进：
  - **SIMD crc32 / adler32（x86 SSE/AVX + ARM NEON）**，压缩/解压吞吐提升明显；
  - 依赖 `cpu_features` 做运行时 CPU 检测；
  - 若干 inflate/deflate 微优化。
- vcpkg `zlib` = madler 官方 1.3.2（**无 SIMD**），port 仅带 `0001-no-version-script-on-ohos.patch`。
- **替代选项**：vcpkg `zlib-ng` 2.3.3 提供 zlib 兼容层（`zlib-ng.h` + compat），带 SIMD 且性能接近 chromium fork；但 **node 倾向直接使用 chromium fork**（与 V8 的 SingleClassificationTable? 不，是 Node 与 Chromium 共享优化）。
- **结论：node 的 zlib 不能直接 vcpkg 化（会损失 SIMD 性能与行为差异）；要么 overlay 自建 chromium-zlib port，要么接受 zlib-ng 替代并做压缩/解压兼容性全量回归，要么维持内嵌。推荐维持内嵌（node 官方行为）。**

### 3.8 googletest（Chromium fork）vs vcpkg gtest 1.17.0 🔴
- node deps/googletest 是 **Chromium fork 布局**（src/ + include/ 平铺，gyp 构建），README.chromium 标注 1.8.0.git-9518a5（该 fork 长期停留在 "1.8.0.git" 代号，但内容持续并入上游最新）。
- vcpkg `gtest` = 官方 googletest 1.17.0（CMake 构建）。
- **影响面**：仅测试（node 的 cctest/unit test）。运行时无影响。
- **结论：不替换（测试工具 fork 无需 vcpkg 化），或替换为 vcpkg gtest 并在 CI 上跑全量测试验证。**

---

## 4. vcpkg 缺失组（9 个，必须内嵌或自制 overlay）

| 依赖 | node24 版本 | 本质 | vcpkg 化建议 |
|---|---|---|---|
| uvwasi | 0.0.23 | nodejs org 维护（基于 libuv 的 WASI 实现），社区热度低 | **维持内嵌**；自制 overlay port 收益低 |
| inspector_protocol | rev 69d69ddf | chromium 的代码生成器（生成 v8inspector C++ 代码），与 v8 版本强绑定 | 必须内嵌（随 v8 同步） |
| nbytes | 0.1.4 | nodejs org 维护的 C++ 字节解析库（webcrypto 用） | 维持内嵌 |
| ncrypto | 0.0.1 | nodejs org 从 openssl 抽出的 C++ 封装层 | 维持内嵌 |
| merve | 1.2.2 | nodejs 内部 C++ 项目（ESM named export 探测） | 维持内嵌 |
| amaro | 1.1.11 | SWC 的 WASM 封装（JS/WASM 二进制，npm 分发） | 不走 vcpkg（WASM + npm） |
| postject | （工具集） | node SEA 注入工具 + C++ API | 维持内嵌 |
| corepack | 0.36.0 | JS 工具，npm 生态 | 不走 vcpkg |
| npm/acorn/minimatch/undici | 见 2.2 | JS 生态 | 不走 vcpkg |

---

## 5. Node 24 特有依赖决策

- **undici 7.29.1**：nodejs org 主创，JS 源码直接内嵌在 deps/undici；npm 分发同名包。**不 vcpkg 化**（node 对 undici 有大量"定制裁剪"）。
- **v8 13.6.233.17-node.53**：结论见 [01 全景](./01-依赖全景与版本总表.md)，不可外接。

## 6. Node 24 汇总

| 判定档 | 数量 | 明细 |
|---|---|---|
| ✅ 可直接 vcpkg（1:1） | 5 | c-ares、zstd、ngtcp2、nghttp3（需去 TLS feature）、hdr-histogram |
| 🔶 版本一致但 node 带 patch | 2 | libuv（4 处 backport，含 Win fs-event 越界修复）、brotli（1 处 platform.h IA64/model/cold 属性补丁） |
| ⚠️ 版本一致但特性需对齐 | 2 | sqlite3（feature 对齐）、icu（源码子集 vs 全量，行为等价） |
| 🔶 版本偏移可 vcpkg/overlay | 6 | openssl、nghttp2、llhttp、simdjson、ada-url、LIEF |
| 🔴 不同源 fork 需评估 | 2 | zlib（chromium fork）、googletest（测试用） |
| ❌ vcpkg 缺失/生态外 | 13 | uvwasi、inspector_protocol、nbytes、ncrypto、merve、amaro、postject、corepack、npm、undici、acorn、minimatch、v8 |

**node24 可直接替换 5/30，版本一致但需关注 patch 2/30，特性对齐 2/30，版本偏移 6/30，不可/不建议 15/30。**