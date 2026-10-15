# 05 · 特性差异与 Node 侧 patch 深挖

> 核心命题：**「版本号一致」≠「库等同」**。Node 内置的每个依赖都可能带 Node 侧或上游 fork 侧的非标准修改；反过来 vcpkg port 也可能带 vcpkg 侧的修改。本章逐库拆解"源码/构建/特性"三个层面的差异，全部基于对 `deps/` 目录的实测。

## 1. 差异的三个层次

1. **源码层**：Node 用的是不是 upstream tag 的原始源码？（fork、submodule、cherry-pick、裁剪）
2. **构建层**：Node 的 gyp/GN 集成方式 vs vcpkg 的 CMake/Make 集成方式（RTL、静态/动态、宏定义）。
3. **特性层**：编译宏/feature 集合决定库暴露的功能面（如 sqlite 的 vtable、zlib 的 SIMD、icu 的 data 量）。

## 2. 逐库深挖

### 2.1 zlib —— 最典型的"同版本号不同库"

| 项 | Node 25+/26（deps/zlib） | vcpkg `zlib` |
|---|---|---|
| 来源 | **Chromium zlib fork**（`chromium.googlesource.com/.../third_party/zlib`） | madler/zlib 官方 |
| 版本号 | `1.3.2.1-motley-<sha>`（node24: 8002e91 / node26: 456ae73） | `1.3.2` |
| SIMD | ✅ crc32_simd / adler32_simd（x86 SSE4.2/AVX2、ARM NEON），运行期用 `deps/zlib/cpu_features.c/h` 探测 | ❌ 无 SIMD |
| 附加文件 | `chromeconf.h`、`cpu_features.*`、`zlib-crc32` 系列等 chromium 专用 | 无 |
| 行为 | 依赖 cpu_features 做 `inflate`/`deflate` 微调 | 标准实现 |
| node patch | node 不额外改源码，跟随 chromium fork 版本；`-motley-<sha>` 即 chromium fork 的 commit | vcpkg 侧仅带 OHOS 平台一个 patch |

**可行性影响**：
- 直接替换为 vcpkg zlib → **亏 SIMD 性能**（压缩/解压吞吐明显差异，且 `node` 的 HTTP/压缩基准会变差），且 `zlib` 的 ZIP `gzip` 头/`Z_SYNC_FLUSH` 行为在流式边界上存在细微差别风险。
- 等价替代：vcpkg `zlib-ng 2.3.3`（zlib ABI 兼容 + SIMD），但依然不是 chromium fork 的 exact 行为（api 函数名有 `zng_` 前缀需要 compat 开关）。
- **结论：维持内嵌（推荐）；或 overlay 自建 `chromium-zlib` port 做完整替代。** 若走 overlay，port 可参考 vcpkg 官方 `zlib` port 的骨架，REF 指向 chromium `third_party/zlib` 对应 commit。

### 2.2 openssl —— 官方源码 + Node 构建适配层

| 项 | 事实 |
|---|---|
| 上游 | openssl.org 官方 3.5.x（node26: 3.5.9 / node24: 3.5.8）；3.5 已合并 quictls 的 QUIC API（node 文档里 quictls 引用已过时，`maintaining-openssl.md` 直接拉官方 repo） |
| node 专属内容（非 upstream） | `deps/openssl/README.md`（gyp 适配说明）、`nodejs-openssl.cnf`（fips/provider 配置模板，被 node 编译进运行时）、`config/` 下的预生成平台文件（`configdata.pm` per-arch 生成 asm/头文件） |
| node 构建差异 | 不用 openssl 的 Makefile，由 `openssl.gyp` + 各架构 gypi 驱动；asm 依赖 nasm；默认静态内嵌；`--shared-openssl` 可用系统库 |
| vcpkg `openssl` | CMake 构建、版本 3.6.3、feature `fips/ssl3/tools/weak-ssl-ciphers` |
| 行为关注 | node:crypto 的错误码与算法行为跨 minor 升级需回归；vcpkg 3.6.3 不测 node 的特定用法 |

**可行性影响**：vcpkg 替换可行（版本更新）；但"node 内嵌的 openssl 与系统/vcpkg openssl 并存"在 `--shared-openssl` 模式下要注意 `libcrypto` 符号冲突（node 已有 `--shared-openssl` 官方支持路径可参考）。

### 2.3 libuv —— 版本一致但 node 带 4 处 backport（逐字节铁证）

- 版本号相同（1.52.1），node 与 libuv 同属 nodejs org，但 **node 并非直接同步上游 tag**——逐字节 diff（vcpkg 缓存包 vs node `deps/uv`）发现 **4 处源文件差异**（详见 [08 §1.2](08-逐字节源码对照验证.md)）：

| 文件 | 差异性质 | 影响 |
|---|---|---|
| `src/unix/fs.c` | preadv/pwritev 缓存 union 加固 | Unix 健壮性 |
| `src/uv-common.c` | model 释放强转 | 通用路径 |
| **`src/win/fs-event.c`** | **目录监视越界/短路径修复** | **Windows 安全/健壮性** |
| `src/win/tcp.c` | GetVersionEx 初始化 | Windows 兼容性 |

- 这些是 node 从 libuv **main 分支** backport 的修复，尚未进入 1.52.1 release tag。用 vcpkg libuv 1.52.1 外接将**丢失这些修复**，Windows 用户受影响最大（fs-event 越界修复）。
- 构建层也不同：node 用 gyp（`deps/uv/uv.gyp`）+ win 上 vcbuild 的特定 `UV_BUILD_*` 定义；vcpkg 用 CMake。
- **结论：不推荐外接 libuv；若坚持外接，需 overlay 到包含这些 backport 的 libuv 版本（或 cherry-pick 到自建 port）。**

### 2.3b brotli —— 版本一致但 node 带 1 处平台兼容补丁

- 逐字节 diff（vcpkg 缓存包 `brotli-1.2.0` vs node `deps/brotli`）：仅 **`c/common/platform.h`** 1 处差异。
- 差异内容 = **node 补丁**：新增 `BROTLI_TARGET_IA64` 宏定义，以及对 `model` / `cold` 函数属性的条件编译保护（`#ifdef BROTLI_TARGET_IA64` 等分支）。
- **影响评估**：x64 / ARM 主流平台行为无差异（补丁仅在新平台/IA64 上激活）；但严格意义上**非字节一致**。
- **结论：外接风险低，主流平台可直接用 vcpkg brotli 1.2.0；若目标含 IA64 等新平台则需 overlay 加补丁。**

### 2.4 V8 —— 最大的 fork

- `13.6.233.17-node.53` / `14.6.202.34-node.37`：版本号带 `-node.<n>` 后缀，是 nodejs 维护的 V8 分支（V8 官方上新版本号由 node 方控制）。
- node 对 V8 的修改遍布：Node 上下文集成（`node::Environment`）、`v8::Platform`（tracing）、snapshot/blob（`node_snapshot`）、Windows 构建支持、inspector 集成、以及做移考（backport）的补丁。
- **结论：V8 及它的 third_party（abseil/simdutf/highway/...）只能内嵌随 Node 源码树同步。** 这是"全量 vcpkg 化"不可能的根因之一。

### 2.5 icu（icu-small）—— 源码子集 + 完整数据（非"数据裁剪"）

- 版本 78.3 一致，但 node 用的是 **icu-small**。**"small"指源码子集，不是数据量**——实测 `deps/icu-small/README-FULL-ICU.txt` 原文："This directory contains ICU subset used by --with-intl=full-icu"。
- 裁剪内容：127 个**非代码文件**（Makefile.in / sources.txt / python 数据生成工具 / 测试输入），**data 完整保留**（`icudt78l.dat.bz2` 全量数据包）。
- node 官方二进制默认 `--with-intl=full-icu`（不是 small-icu）；"small-icu" 构建模式才裁数据，但官方不用。
- vcpkg `icu` 全量（含全部源码 + 全部 data + tools）。与 node icu-small **行为等价**（同一版本、同一数据），差异仅在构建产物面积与源码树体积。
- **可行性建议**：可替换（行为等价）；若要求体积受控，用 overlay-port 定制"icu-small"再喂给 node，vcpkg 全量 icu 不满足体积要求。

### 2.6 sqlite —— 编译宏决定功能面

- 版本一致（3.53.4 amalgamation）。
- node 的宏集（实测自 gyp 配置）：
  `SQLITE_ENABLE_COLUMN_METADATA / DBSTAT_VTAB / FTS / GEOPOLY / MATH_FUNCTIONS / PERCENTILE / PREUPDATE_HOOK / RBU / RTREE / SESSION` + `SQLITE_DEFAULT_MEMSTATUS` 等。
- vcpkg `sqlite3` 对应 feature 全覆盖（dbstat/fts*/geopoly/math/percentile/rtree/session/rbu/dbpage-vtab），**可用 feature 精确对齐**。
- 差异：node 是**单文件编译**（sqlite3.c 直接进 node 编译单元，静态无 DLL），vcpkg 是库；需要把 node 对 `sqlite3_open`/vfs 的定制（node 注册了自己的 VFS 并截获某些调用）纳入验证。**结论：特性可对齐、产物需专项测试。**

### 2.7 ngtcp2 / nghttp3 —— 内嵌方式不同

- 版本一致（1.25.0 / 1.18.0）。但 node 只保留两个仓库的 `lib` 子集（ngtcp2 还取 `crypto` 目录）且**不启用其 TLS 后端**（node 闭源接入 openssl）。
- vcpkg `ngtcp2` port 强制选一 TLS feature（openssl/gnutls/wolfssl），`nghttp3` 额外依赖 `sfparse`。
- 结论：**不能直接装官方 vcpkg port**，需 overlay port 去掉 TLS 依赖 + 关闭 sfparse（node 内嵌有 sfparse 源码）。

### 2.8 llhttp —— node 自家项目

- `nodejs/llhttp` 由 node 组织维护，node 是主要消费者；deps/llhttp 与其 tag 同步。vcpkg `llhttp` 从同一个 upstream 构建，但落后两个 patch。
- node 对 llhttp 无外部 patch（它自己就是上游）。

### 2.8b ada-url —— 内嵌 idna + simdutf 加速（vcpkg port 缺 simdutf feature）

- **node 的 ada 内嵌了 idna 代码**：`deps/ada/ada.cpp` 是单文件 amalgamation，含 `/* begin file src/ada_idna.cpp */`、`namespace ada::idna`、`unicode_transcoding.h`、`mapping.h` 等——ada-url 仓库本身包含 idna 子目录，node 把它全部内联。
- **node 启用了 `ADA_USE_SIMDUTF=1`**（`deps/ada/ada.gyp:16`），用 simdutf 做 IDNA unicode transcoding（`utf8_length_from_utf32` / `convert_utf32_to_utf8` 等）。
- **node 的 simdutf 来自 v8 内嵌**：`ada.gyp:11` include 路径 = `deps/v8/third_party/simdutf`，依赖 `v8.gyp:simdutf` target。完整依赖链：`node:ada → ADA_USE_SIMDUTF=1 → v8:third_party/simdutf`。
- **vcpkg `ada-url` port 没有 simdutf feature**：`ports/ada-url/vcpkg.json` 只有 `tools` feature；portfile 不传 `ADA_USE_SIMDUTF`，CMake 默认 OFF。用 vcpkg ada-url 替换 node 的 ada 会**丢失 SIMD 加速的 IDNA 转码**（退回纯 C++ 实现）。
- **vcpkg `ada-idna` port 有 simdutf feature**（`ports/ada-idna/vcpkg.json` features.simdutf 依赖 `simdutf` port），但 ada-idna 是独立库（`ada-url/idna` 仓库），node 不单独使用它——node 用的是 ada-url 内含的 idna。
- **修复方案**：自建 overlay 给 ada-url 加 simdutf feature（参照 ada-idna portfile 的 `ADA_USE_SIMDUTF` 选项处理），但此时 simdutf 版本又成为新问题：vcpkg simdutf 8.2.0 vs node v8 内嵌 simdutf 7.7.0（node26）。
- **结论**：ada-url 的 vcpkg 化风险**高于此前文档评估**。不仅版本落后（4.0.0 vs 3.4.4），还有 simdutf feature 缺失导致的性能/行为差异。**建议维持内嵌，或 overlay 时必须同时加 simdutf feature + 固定 simdutf 版本。**

### 2.9 googletest —— chromium fork 布局

- node deps/googletest 与 v8 third_party/googletest 都是 **chromium fork**（`src/`+`include/` 平铺、gyp/BUILD.gn 驱动、README.chromium 标注 `1.8.0.git-9518a5`），持续并入 upstream 改动但有自己的补丁维护。
- vcpkg `gtest` 是官方 CMake 版。
- 仅测试用途 → **不参与运行时；不建议为此 vcpkg 化**。

### 2.10 其它 v8 third_party 特性要点

| 库 | 版本 | 特性说明 |
|---|---|---|
| abseil-cpp | chromium fork（node24: fd39cfa4 / node26: 6d5ac0f7） | chromium 在其上维护 BUILD.gn 与切分；vcpkg `abseil` 20260107.1 是官方 LTS 快照，**两者源码不同源**（行为近似但微有差异） |
| simdutf | node24 6.4.0 / node26 7.7.0 | v8 引用的是 single-header 版（node24 注释"single header"）；vcpkg 8.2.0 领先。node 的 simdutf 版本由 v8 决定，**拆不出去** |
| highway | chromium fork（commit 8295336d） | 用于 wasm SIMD 实验；vcpkg 1.4.0 较新。v8 内嵌使用 |
| rapidhash-v8 | chromium fork（commit 5889784） | v8 内置哈希；vcpkg `rapidhash` 3 是上游 single-header，**方法与 API 面不同** |
| fp16 | 2022 commit | header-only；vcpkg port 版本更旧 |
| fast_float | 7.0.0 | header-only；vcpkg 8.2.10 领先 |
| dragonbox | 1.1.3（v26） | v8 源码自带，vcpkg 无 port |
| jsoncpp | chromium commit | v8 测试用的 JSON 解析；vcpkg 1.9.6 可用但无必要 |

### 2.11 JS 层（undici/npm/acorn/minimatch/amaro/corepack）

- 均以源码或 npm 包形式内嵌；版本按 node 节奏更新，无 vcpkg 相关。
- undici/node 定制：node 对 undici 有裁剪（去掉不需要的套件）与 Node 专属集成（fetch 全局、`node:undici`）。

## 3. "版本一致"清单的复查结论

> ⚠️ 本表已按 [08](08-逐字节源码对照验证.md) 逐字节 diff 复核。libuv / brotli 从原"源码一致"降级。

| 依赖 | 源码层 | 构建层 | 特性层 | 替换后风险 |
|---|---|---|---|---|
| c-ares 1.34.8 | **逐字节一致**（仅 .gitignore） | 不同（gyp vs cmake） | 一致 | 低 |
| zstd 1.5.7 | **逐字节一致**（0 源文件差异） | 不同 | 一致 | 低 |
| ngtcp2/nghttp3 1.25.0/1.18.0 | **逐字节一致**（lib 子集） | 不同 | node 无 TLS 后端 | 中（需 overlay 去 TLS） |
| hdr-histogram 0.11.10（v24） | 一致 | 不同 | vcpkg 带 zlib/log 依赖 | 低 |
| **libuv 1.52.1** | **🔴 4 处 backport 差异** | 不同（gyp vs cmake） | 一致 | **中（Win fs-event 越界修复丢失）** |
| **brotli 1.2.0** | **🔶 1 处 platform.h 补丁** | 不同 | 一致 | **低（仅 IA64 等新平台）** |
| icu 78.3 | node 裁源码子集（**data 完整**） | 不同 | **行为等价** | 低（体积/打包差异） |
| sqlite 3.53.4 | 一致（amalgamation） | 不同 | **宏集需对齐** | 中 |

> 结论：**版本一致 ≠ 可无脑替换**。真正"零成本"逐字节一致替换的只有 **c-ares / zstd / ngtcp2（lib 子集）/ hdr-histogram** 四个；libuv 带 4 处 backport（不推荐外接）、brotli 带 1 处补丁（低风险可外接）、icu 行为等价但体积差异、sqlite 需 feature 对齐。
## 4. 补丁传播与依赖图冲突（"选边站"问题）

> 核心命题：如果把 node 的补丁打到 vcpkg 的库上，node 行为一致了，但 vcpkg 中**其他依赖该库的 port** 会被迫使用补丁版——如果它们的行为依赖未补丁版本，就会出现"选边站"。

### 4.1 vcpkg 依赖图枢纽节点量化

| 被打补丁的库 | vcpkg 中依赖它的 port 数 | 公开 API/ABI 变化 | 补丁性质 | 传播风险 |
|---|---|---|---|---|
| **libuv** | 14 个（libwebsockets, usockets, uvw, luv, getdns, ...） | **uv.h 0 差异**（ABI 不变） | 纯 bugfix（fs-event 越界→优雅回退，`uv__relative_path` 是 static 内部函数） | **极低** |
| **brotli** | 9 个（curl, freetype, qtbase, arrow, libjxl, ...） | **encode.h/decode.h/port.h 0 差异** | 内部平台兼容（IA64/LOONGARCH64 属性保护，x64/ARM 不激活） | **极低** |
| **zlib**（若 overlay chromium fork） | **248 个** | API 兼容但行为不同（SIMD crc32/adler32） | **行为性改变**（非纯 bugfix） | **高** |
| **openssl**（若 overlay 3.5.9） | **198 个** | ABI 可能跨 minor 变化 | 版本回退 | **高** |

### 4.2 两种补丁传播场景

**场景A：补丁是纯 bugfix + ABI 不变（libuv/brotli）**
- 其他库不太可能依赖"assert 崩溃"或"越界行为"做 workaround，所以传播安全。
- 但**不能一概而论**：未来 node 的 backport 若含行为性改变（非纯 bugfix），就会出现"选边站"。
- libuv 补丁实测：`uv__relative_path` 从 `void` 返回改为 `int`（增加错误码），但是 `static` 内部函数，不改变公开 API；调用方增加错误处理分支（短路径回退），正常路径行为不变。

**场景B：补丁是行为性改变（zlib chromium fork）**
- 248 个 port 依赖 zlib，overlay chromium-zlib 会让 freetype/curl/libpng/qtbase 等全部切换到 chromium fork。
- 这些库**未在 chromium zlib 上测试过** → 真正的"选边站"：要么 node 用 chromium zlib + 其他库也被迫用，要么其他库用 madler zlib + node 内嵌 chromium zlib（两份并存，N-API 场景可能符号冲突）。

### 4.3 最现实的"选边站"场景

用户的 C++ 项目同时链接 node（通过 N-API addon）和 vcpkg 的 curl/freetype：
- 若 node 外接 vcpkg libuv（打补丁版）→ curl/freetype 也用补丁版 libuv → 通常安全（纯 bugfix + ABI 不变）。
- 若 node 外接 chromium-zlib → curl/freetype 也被迫用 chromium-zlib → **未测试的组合**，可能出现压缩/解压行为差异。
- 若 node 外接 openssl 3.5.9 → 198 个 port 被回退 → 安全修复丢失。

### 4.4 结论

- **libuv/brotli 补丁传播风险极低**（ABI 不变 + 纯 bugfix/平台兼容），可以安全 overlay。
- **zlib/openssl 是依赖图枢纽节点**（248/198 个消费者），overlay 它们等于"绑架"整个 vcpkg 依赖图 → **不推荐 overlay，维持内嵌**。
- **通用原则**：overlay 打补丁前，必须检查该库在 vcpkg 中的依赖者数量和补丁性质（bugfix vs 行为改变）。vcpkg 不支持同一 port 的多版本共存，所以"选边站"是结构性约束，无法绕过。