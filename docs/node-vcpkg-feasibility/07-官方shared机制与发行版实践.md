# 07 · Node 官方 shared 机制 + 发行版共享依赖实践（实锤篇）

> 本章回答两个此前文档未覆盖的关键问题：**(1) Node 官方为"外接依赖"提供了哪些通道（参数名字未必带 "shared"）？(2) 社区（Debian/Ubuntu 等）为何选择 shared-deps、付出了什么代价、持什么观点？**
> 证据来源：node26 `configure.py` 实测、`BUILDING.md` 官方文档、Debian/Ubuntu `debian/rules` 实测抓取（salsa 挡爬虫，经 launchpad 取得 Ubuntu 同源 rules）。

## 1. Node 官方 externalize 机制全景

### 1.1 三条外部化通道（参数名不同，注意区分）

| 通道 | 参数形态 | 作用对象 | 说明 |
|---|---|---|---|
| **Shared libraries（动态库）** | `--shared-<lib>[{-includes,-libname,-libpath}]` | 有 native 代码的依赖 | 编译成共享库、运行时动态链接；另可指定头文件/库名/库路径 |
| **Shared builtins（JS 运行时加载）** | `--shared-builtin-<module>-path=...` | JS/WASM 依赖 | 不编进二进制，运行时从外部 JS 文件加载（如 undici、acorn） |
| **System ICU** | `--with-intl=system-icu`（不是 `--shared-icu`！） | ICU | 通过 `pkg-config icu-i18n icu-uc` 外接系统 ICU，Unix only |

> ⚠️ 误区澄清：
> - **ICU 没有 `--shared-icu`**，它的外接参数叫 `--with-intl=system-icu`（Unix/macOS 限定）。
> - **llhttp 的 shared 参数叫 `--shared-http-parser`**（沿用旧名 http-parser），不是 `--shared-llhttp`。
> - **libffi 的 shared 参数是 `--shared-ffi`**（configure）/<node.gyp>`node_shared_ffi`，不是 `--shared-libffi`。
> - **libuv 是 `--shared-libuv`**，不是 `--shared-uv`。
> - 还有一条通用开关 **`--shared`**：一键把"已登记为可外接的库"全部外部化（Debian 用了它）。

### 1.2 configure.py 实测：可 externalize 的库全集

**Node 26.11.1（configure.py `shared_optgroup`，每个库另有 -includes/-libname/-libpath 三连）**：

```
共 24 个：abseil · ada · brotli · cares · ffi · gtest · hdr-histogram · highway ·
            http-parser(=llhttp) · libuv · lief · merve · nbytes · nghttp2 ·
            nghttp3 · ngtcp2 · openssl · perfetto · simdjson · simdutf ·
            sqlite · uvwasi · zlib · zstd
另有 shared-builtin-* 通道（JS 层）：undici · acorn · acorn_walk · minimatch…
```

**Node 24.21.0（configure.py 实测）**：
```
共 21 个：ada · brotli · cares · gtest · hdr-histogram · http-parser(=llhttp) ·
            libuv · merve · nbytes · nghttp2 · nghttp3 · ngtcp2 · openssl ·
            simdjson · simdutf · sqlite · uvwasi · zlib · zstd
          + shared-builtin-*（undici/acorn 等）
```

**node24 → node26 差异**：node26 新增 externalize 支持 `abseil / ffi / highway / lief / perfetto`（与 deps 新增/扩展对应），且 `temporal_capi`（node.gyp 中的 `node_shared_temporal_capi`）也已支持外接。

> 结论：**"能否外接"的官方通道几乎覆盖全部 C/C++ 依赖，包括我上一版文档判为"必须内嵌"的 merve/nbytes/uvwasi/lief/ada/simdjson/simdutf**。真正没有 shared 通道的只剩：V8（无 `--shared-v8`，node 维护分支）、JS/WASM 层走 shared-builtin、system-icu 通道。**所以可行性问题的重心从"有没有通道"转移到"vcpkg 有没有对应 port / overlay port 成本"与"官方对 shared 模式的立场"。**

### 1.3 官方立场（BUILDING.md 原文要义，非转述）

1. **默认**：所有依赖打进单一二进制（"This provides a single binary that includes the correct versions of all dependencies"）。
2. **shared 模式的定位**：为"一些发行版偏好自行管理依赖"而设（"Some Node.js distributions, however, prefer to manage dependencies"）——即官方默认不支持、只给通道。
3. **分发者责任（原文直译）**：
   - *ensure that the shared dependencies available at runtime match what is expected by the Node.js binary. A mismatch may result in crashes or unexpected behavior.*（运行时共享库必须匹配；不匹配可能崩溃或行为异常）
   - *fully test that Node.js operates as expected with the external dependencies. There may be little or no test coverage within the Node.js project CI for these non-default options.*（必须全量自测；Node CI 对这些非常规选项几乎没有测试覆盖）
4. **ABI 红线**：对外分发的构建必须与官方构建依赖**ABI 兼容**的依赖版本（`NODE_MODULE_VERSION` 见 `src/node_version.h`、`doc/abi_version_registry.json`）；若依赖版本 ABI 不兼容，**必须申请自定义 `NODE_MODULE_VERSION`**。这是 native addon 兼容性的法律线。

### 1.4 Windows 上的第一手冲突证据（BUILDING.md 原文）

> *"You may need to disable vcpkg integration if you encounter a link error about symbol redefinition related to zlib.lib(zlib1.dll)... vcpkg is part of CLion and Visual Studio now."*

即：**在 Visual Studio / CLion 环境中，vcpkg 的集成可能把 zlib（或其它库）的 .lib 注入链接路径，与 node 内嵌 vendored 库产生符号重定义冲突**（issue #24448、vcpkg #37518）。这意味着"node 内嵌库 + vcpkg 已装同名库"同时存在时，Windows 构建存在**链接期冲突**的实锤风险——做 vcpkg 化时必须处理（关闭 vcpkg integration 或确保依赖一致）。

## 2. Debian / Ubuntu 的 shared-deps 实践（debian/rules 实测）

### 2.1 Debian 实际使用的 externalize 全集

```makefile
DEB_CONFIGURE_EXTRA_FLAGS = \
  --verbose \
  --without-npm --without-corepack --without-amaro \
  --shared \
  --shared-ada --shared-ada-libname=ada-url0 \
  --shared-zlib --shared-zstd --shared-cares \
  --shared-http-parser --shared-ngtcp2 --shared-nghttp3 \
  --shared-nghttp2 --shared-brotli --shared-simdjson \
  --shared-sqlite --shared-simdutf --shared-hdr-histogram \
  --shared-gtest --shared-libuv --shared-openssl \
  --openssl-use-def-ca-store \
  --with-intl=system-icu \
  --shared-builtin-undici/undici-path=/usr/share/nodejs/undici/undici-fetch.js \
  --shared-builtin-acorn-path=/usr/share/nodejs/acorn/dist/acorn.js \
  --shared-builtin-acorn_walk-path=/usr/share/nodejs/acorn-walk/dist/walk.js \
  --prefix=/usr ...
```

提炼出来的 Debian 决策：
- **C/C++ 层全部系统化**：openssl、zlib、zstd、cares、llhttp、ngtcp2/nghttp3/nghttp2、brotli、simdjson、simdutf、hdr-histogram、gtest、libuv、sqlite、ada（且显式 `--shared-ada-libname=ada-url0` 对应系统包 `libada-url0`）。
- **JS/WASM 层**：去掉 npm、corepack、amaro；undici/acorn/acorn-walk 走 `--shared-builtin-*`（运行时从 `/usr/share/nodejs` 加载）；minimatch 用 esbuild 现场 bundle 系统包；typescript 软链系统包。
- **ICU**：`--with-intl=system-icu`（Debian 特有通道，vcpkg 也可照做）。
- **openssl**：加 `--openssl-use-def-ca-store`（用系统 CA store，而非内置 Mozilla 根证书）。

### 2.2 Debian 明确付出的代价（rules 注释逐条列举 —— 这是社区最硬核的观点）

测试被跳过/降级的原因注释就是 Debian 对 shared-deps 缺点的"亲身总结"：

| rules 中的注释 | 版本差异证据 |
|---|---|
| `# Test will fail when external dependency is upgraded`（跳过 `test-process-versions`） | **版本偏差是既定事实**：系统库升级后 process.versions 与 node 内置不一致，官方测试直接不可用 |
| `# CVE-2024-22017 shared libuv cannot guarantee io_uring is disabled`（跳过 test-process-uid-gid 等一组） | **安全语义差异**：系统 libuv 构建未保证禁用 io_uring（node 内置 build 禁用以规避 CVE）——共享库可能引入 node 官方已规避的安全面 |
| `# problem with openssl 3.6.4`（跳过 test-crypto-authenticated） | 系统 openssl 比 node 内置新（3.6.x vs 3.5.9）时**行为差异 → 测试失败** |
| `# Skip test broken by openssl 3.6` / `# Skip test broken by openssl 4.0`（test-tls-ocsp-callback、test-tls-*） | openssl 大版本升级破坏 node 的 TLS 测试 |
| `# missing sqlite rbu geopoly extensions`（跳过 test-sqlite） | **特性缺口**：Debian 的 libsqlite3 未开 `SQLITE_ENABLE_RBU/GEOPOLY`，与 node 期望特性集不符 —— 直接印证本文档"sqlite 宏集需对齐"判断，且 Debian 选择了"跳过测试"而非补齐特性 |
| `# This is testing system icu - it might fail when icu is upgraded`（test-icu-env 标 flaky） | 系统 ICU 升级时 Intl 行为不确定 |
| `# without-amaro needs ...` | 去 amaro 后一批 TS/strip-types 测试被跳过 |

> 核心观点：**Debian 对 shared-deps 的取舍是"接受版本/行为/特性偏差，用跳过测试换取不进二进制"**。它没有试图与 node 官方内置版本严格对齐。这与"vcpkg 化追求与 node 官方一致"的目标**互相矛盾**——做权衡前必须想清楚到底追求哪个。

### 2.3 其它社区信号（未抓取到文件的补充说明）

- **Fedora / Arch / Nix / Alpine 等同样走"系统共享库 + 各种 shared 标志"路线**，Nix 还在 nixpkgs 中维护 `sharedLibDeps` 集合（BUILDING.md 的 Nix 集成节可见：`use nix --arg sharedLibDeps '{ inherit (import ./tools/nix/sharedLibDeps.nix {}) openssl zlib; }'`——nixpkgs 中 node 默认用系统库，且**注明用 vendored 依赖产出的二进制"更接近官方"**）。nix 注释原文：*"Using the vendored-in dependencies result in a result closer to the official binaries, the tradeoff being the build will take longer"* —— 社区自己也承认 vendored（内置）更接近官方。

## 3. 对 vcpkg 化可行性的重估（修正上一版结论）

### 3.1 官方通道 → 外接能力矩阵（node26）

| 依赖 | 官方 shared 通道 | vcpkg port | 新结论 |
|---|---|---|---|
| openssl | ✅ `--shared-openssl` | ✅ `openssl` | 通道+port 齐备；版本/行为差异见 07§1.3、Debian 教训 |
| zlib | ✅ `--shared-zlib` | ✅ `zlib`(madler) | 通道在但**同源问题不变**（chromium fork vs madler，Debian 直接接受了系统 zlib） |
| libuv | ✅ `--shared-libuv` | ✅ `libuv` | 通道在；**node 含 main 分支 backport**（见 08 逐字节证据），Debian 已接受（且吃了 io_uring 教训） |
| sqlite | ✅ `--shared-sqlite` | ✅ `sqlite3` | 通道在；特性宏集需对齐（Debian 干脆跳测试） |
| icu | ✅ `--with-intl=system-icu` | ✅ `icu` | 官方推荐通道即 system-icu（Unix）；vcpkg icu 可用作 system-icu |
| llhttp | ✅ `--shared-http-parser` | ✅ `llhttp` | 通道在；node 领先 2 patch，overlay 即可 |
| ngtcp2/nghttp3 | ✅ | ✅（需去 TLS feature） | 通道+port 在 |
| cares/brotli/zstd | ✅ | ✅ | 通道+port 在，c-ares/zstd 源码级一致 |
| ada/simdjson/simdutf | ✅ | ✅ | 通道在；版本差用 overlay |
| merve/nbytes/uvwasi | ✅（v26 node.gyp 有 node_shared_*） | ❌ | **上一版"只能内嵌"结论修正**：官方给了外接通道，但 vcpkg 无 port → 需 overlay-port 自建；收益仍低（无外部消费场景），维护成本高于内嵌 |
| LIEF/perfetto/libffi/abseil/highway | ✅（仅 v26） | ✅ | 通道新开放；port 版本落后，perfetto 与 v8 共享 ⇒ 仍建议内嵌 |
| gtest | ✅ `--shared-gtest` | ✅ | 仅测试；Debian 也 externalize 了 gtest |
| V8 | ❌ 无通道 | ❌ | **唯一真正"不可外接"的运行时核心** |

### 3.2 修正后的结论框架

1. **"不可 vcpkg 化"清单从 15 项收缩**：真正不可外接的 = V8（含其 third_party）+ 少数无 port 又无收益的 node 主创库（merve/nbytes/uvwasi/amaro 等，但其中 3 个官方其实已给 shared 通道）。
2. **障碍转移**：从"没有 shared 参数"变为 **(a) vcpkg port 缺失/版本落后 → overlay 成本；(b) 官方不兜底 shared 模式（无 CI 覆盖、分发者全责）；(c) fork 不同源（zlib）；(d) 版本/行为偏差必然导致测试失败（Debian 经验）**。
3. **Debian 模式可以作为 vcpkg 化的"行为模板"**：它证明了"用系统库构建 node 并在生产中运行"是可行的，但同时给出了完整的代价清单（跳过测试、接受安全语义差异、接受特性缺口）。若企业采纳"node 全部 vcpkg 化"，本质是复刻 Debian 模式、但把"系统包"换成"vcpkg 包"；要接受的是同一份代价，而不是零代价。

## 4. 隐性担忧清单（需求提出者可能关心，逐条给出证据）

| 隐性担忧 | 证据/结论 |
|---|---|
| **供应链安全：CVE 响应节奏** | node 内置库版本跟随 node 官方平衡（如 openssl 每月同步）；vcpkg 化后安全更新责任转交库维护者+构建链。libuv io_uring（CVE-2024-22017）例子表明：系统库构建可能丢失 node 官方的安全加固 |
| **行为一致性 / 测试保障** | 官方"分层责任"明文：shared 模式 CI 不覆盖、崩溃风险由分发者承担；Debian 用 30+ 条 skip/flaky 测试注解佐证了偏差规模 |
| **性能** | zlib SIMD（chromium fork）与 openssl asm 是内置构建的隐性收益；Debian 系统 zlib 无 SIMD。vcpkg 化同样会失去（除非 vcpkg 换 zlib-ng） |
| **ABI / native addon 兼容** | NODE_MODULE_VERSION 是硬约束；依赖版本换 ABI 即破坏第三方 addon，需自定义 ABI 版本 |
| **供应链可追踪性** | "全 vcpkg 化"反而把几层版本映射（overlay+baseline+vendor）复杂化；内嵌+vendor 清单更易追溯 |
| **Windows 上 vcpkg 与 node 冲突** | BUILDING.md 明示 zlib.lib 符号重定义问题（vcpkg 集成进入 VS/CLion）——攻击面一旦 externalize 在 Windows 上会显著放大 |
| **成本/维护** | overlay-port 需要持续跟版本；Debian 的 rules + patches 是数年人力沉淀（debian/patches 有大量补丁）——企业自建需同样投入 |
| **合规/许可** | 库 LICENSE 基本一致；chromium fork（zlib/abseil）的 NOTICE 需保留；OSV/vcpkg 的 license 元数据可辅助审计 |
| **发布节奏控制** | node 内置依赖"锁版上线"，vcpkg 化后库版本可被 vcpkg baseline 更新牵动 → 需固定 baseline（2026-07-29） |