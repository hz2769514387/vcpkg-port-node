# vcpkg-port-node

把 **Node.js v24.21.0 整棵源码树（含 V8）** 用 node 官方的 **gyp → ninja** 路径编成
**可链接的静态库**，以 vcpkg **overlay port** 的形式交付。

```
find_package(node CONFIG REQUIRED)
target_link_libraries(你的目标 PRIVATE node::node)
```

* node **直接依赖**的 14 个第三方库（openssl / zlib / libuv / icu / sqlite3 / brotli / zstd /
  simdjson / simdutf / ada / ngtcp2 / nghttp2 / c-ares / llhttp / hdr-histogram）**全部走 vcpkg**，
  作为传递依赖自动带上；node 内嵌的 v8_zlib / simdutf 也换成了 vcpkg 版本（避免符号重复）。
* 交付物是**静态库**：请求 `VCPKG_LIBRARY_LINKAGE=dynamic` 会被 vcpkg 直接报错（结构性不支持）。
* 为什么不用上游 CMake：上游没有自研 CMake（`BUILD.gn` 明确 GN 不用于官方二进制），
  官方入口就是 `configure.py` + gyp；gyp 自带的 cmake generator 被上游标注为
  experimental / 仅 Linux / 不可依赖。详见 `docs/架构重审-路线抉择.md`。

## 支持矩阵

| 档 | 含义 | 平台 / 口径 |
|---|---|---|
| **Tier 1** | CI 每个 push 都跑，**实测保证** | Windows `x64-windows-static-clang`（clang-cl + 静态 CRT，node 24+ 官方口径）；Linux `x64-linux`（gcc，静态库） |
| **Tier 2** | 进了 CI 矩阵但**允许失败**；声明可过、未保证 | `arm64-windows-static-clang`、`arm64-linux`、`arm64-osx`；MSVC 口径、debug 构建、动态 CRT 变体 |
| **Tier 2（不在 CI）** | 配置留着、可自己跑，但 CI 不覆盖 | `x64-osx`（macos-13 runner 资源紧张，已从 CI 移除，见 `docs/暂时还没做.md` 2b） |
| **Tier 3** | **结构性不支持**（vcpkg 直接报错或 `supports` 字段挡掉） | 动态库交付、32 位、mingw、android / ios |

全部 release-only（triplet 里 `VCPKG_BUILD_TYPE release`）。
未做与待办逐项列在 `docs/暂时还没做.md`。

**一个已知限制**：v8 自带的 **abseil / highway 不能替换、也不能在同一可执行里与 vcpkg 的那两份共存**——
v8 用到它们的内部符号（实测：换用 vcpkg 的 abseil 会在链接期 LNK2019），所以 port 保留 v8 自带的那份并让它优先。`simdutf` / `zlib` 没有这个问题（v8 只用公开接口，已换成 vcpkg 那份）。
细节见 `docs/架构重审-路线B落地实验.md` §15.11 与 `docs/暂时还没做.md` 5g。

## 目录结构

```
ports/node/          自包含的 port：只有 portfile.cmake / vcpkg.json / patches/ / usage
                     不引用 port 目录外的任何文件，不含 triplet / toolchain
                     （可选 feature test-suite 会额外装 node 官方测试套件到 share/）
test/                消费端验证工程（主项目 + 子项目），同时是 CI 的验证入口
├── app/              node 嵌入可执行（产物名故意叫 node，兼作官方套件的 shell）
├── unit/             gtest：vcpkg 库自身 + 与 node 共存（版本交叉核对）
├── coexist/          行为级共存：zlib/brotli/openssl/ICU/IDN/sqlite/http/http2/worker/wasm
├── tests/            ctest 胶水：node 官方套件 + 符号审计
├── cmake/triplets/   六个平台的 triplet      ← 属于消费端
└── cmake/toolchains/ clang-cl + MSVC 命令行环境 ← 属于消费端
tools/               维护工具：version_tree.py（版本表）、gyp2vcpkg/
                     （符号审计已搬到 test/tools/symbol_check.js，由编出来的 node 自己跑）
versions/            vcpkg 版本表（versions/n-/node.json）
docs/                调研与决策记录（架构重审、路线抉择、落地实验）
```

依赖方向只有一条：`test ──(overlay-ports)──> ports/node`。
Windows 需要 clang-cl 时，triplet 用 vcpkg 的标准变量 `VCPKG_CHAINLOAD_TOOLCHAIN_FILE`
把工具链**交接**给 port —— port 只读这个变量，换成你自己的 clang-cl 工具链同样能工作。

## 接入方式

1. 在你的 `vcpkg.json` 旁边放一个 `vcpkg-configuration.json`，把本仓库的 `ports` 指为 overlay：

   ```json
   {
     "overlay-ports": ["path/to/vcpkg-port-node/ports"]
   }
   ```

2. 用 triplet 指定口径（例如 Windows 用本仓库 `test/cmake/triplets/x64-windows-static-clang.cmake`）。
3. 清单模式配置你的工程：`cmake --preset ...` / `find_package(node CONFIG REQUIRED)`。

完整可运行的例子（含 CMakePresets、主项目 + 子项目结构）见 **`test/`**，
在 `test/` 下 `cmake --preset windows-clang-cl && cmake --build --preset windows-clang-cl` 即可。

## port 安装了哪些东西

| 路径 | 内容 |
|---|---|
| `<prefix>/include/node/` | node 嵌入头（`node.h`、`node_api.h` …） |
| `<prefix>/include/` | V8 公开头 |
| `<prefix>/lib/` | `libnode`（或 `libnode.a`）+ `node_base` + `v8_*` + uvwasi / merve / nbytes / ncrypto / crdtp / abseil / highway / v8_zlib |
| `<prefix>/share/node/node-config.cmake` | `node::node` 及其全部传递依赖的导入目标 |
| `<prefix>/share/node/node.exe.extra.manifest` | Windows 平台兼容性清单（变量 `node_NODE_SOURCE_MANIFEST`） |
| `<prefix>/share/node/test-suite/` | **可选 feature `test-suite`**：node 官方测试套件（`test/` 全量 + `tools/test.py`），消费端可用它跑官方用例（变量 `node_TEST_SUITE_DIR`）。约 80 MB |
| `<prefix>/tools/node/` | **可选 feature `tools`**：node 可执行 + npm / npx / corepack（官方发行版布局：可执行 + `node_modules/{npm,corepack}` + 垫片；垫片有 POSIX sh 与 Windows `.cmd` 两套）。变量 `node_EXECUTABLE` / `node_TOOLS_DIR` / `node_NPM` / `node_NPX` / `node_COREPACK`。约 25 MB |

## 怎么验证它能用（不只是冒烟）

`test/` 是一个真正的验证工程，用 ctest 分四组：

```sh
cd test
cmake --preset windows-clang-cl          # 或 linux / macos / …（六个 preset，CI 跑其中五个）
cmake --build --preset windows-clang-cl
ctest --test-dir build/windows-clang-cl --output-on-failure
```

| label | 验证什么 |
|---|---|
| `smoke` | 链接成功 + 跑得起来 + `process.versions.node` 对得上 |
| `unit` | gtest：一批 vcpkg 库自身可用；**同时链 `node::node`** 后仍可用；node 报告的依赖版本与我方直接调用得到的版本一致 |
| `coexist` | 行为级三层：① `coexist.js` 把 zlib / brotli / openssl / ICU / IDN / sqlite / llhttp / nghttp2 / libuv / V8 提供的 node 能力逐个真跑；② **`mutual_roundtrip`：一个进程里同时链 node 与那些可能重复的 vcpkg 库，让 C++ 侧与同进程的 node 运行时互相消费对方产物并各自复核（双向）**；③ 符号审计 `test/tools/symbol_check.js`（Windows 用 dumpbin、其它用 `nm`；由本工程编出来的 node 自己执行） |
| `openssl` | **openssl 行为面**：node 自带 openssl 换成 vcpkg 那份之后，算法面（getHashes/getCiphers/getCurves）与端到端功能（sha256/HMAC 已知向量、aes-256-gcm 往返、ed25519 验签、secp256k1 ECDH、`tls.createSecureContext()`、TLS 1.3 套件）是否还对得上。见 `docs/暂时还没做.md` §5h 的逐项比对 |
| `node-suite` | **node 官方测试套件**：官方 `tools/test.py --shell=<本工程编译出的可执行>`，上游 `*.status` 里的 SKIP/FLAKY 会被尊重 |
| `tools` | port 的 `tools` feature 输出：用 `node_EXECUTABLE` 跑版本、`npm/npx/corepack --version`（生产者→产物→消费者这条链是通的） |
| `symbols` | 符号审计（Windows）：node 自带库与 vcpkg 库之间有没有重复强符号 |

用 `-L` 只跑其中一组，例如 `ctest --test-dir build/<preset> -L unit --output-on-failure`。
细节（分片、跳过表、为什么不用 `node --test`）见 `test/README.md`。

## 维护约定（会被 CI 强制）

* **改了 `ports/node` 里任何一个字节，就要更新版本表**：

  ```sh
  python3 tools/version_tree.py          # 写入
  python3 tools/version_tree.py --check   # 校验（CI 用同一个脚本）
  ```

  `versions/n-/node.json` 里的 `git-tree` 是 **`ports/node` 整个目录的 Git tree 对象哈希**
  （不是 commit id）—— 它是"某个版本号对应哪一份 port 内容"的指纹。
  该脚本用与 vcpkg `x-add-version` 相同的方式计算（临时索引 + `git write-tree`，
  并强制 `core.autocrlf=false`），所以任何机器算出来都一样，也不需要先提交。

* **换行符统一 LF**（`.gitattributes` 里 `* text=auto eol=lf`）。
  被跟踪文件里出现任何 CR，CI 的 lint 会直接红 —— 这样"某台机器 git 配置不同"不会再
  影响 `git apply` 补丁或 `git-tree` 哈希。
* **port 必须自包含**：`ports/node/` 下只允许 `portfile.cmake` / `vcpkg.json` / `usage` / `patches/`，
  且不得引用 port 目录外的路径（CI 有对应检查）。

## CI

`.github/workflows/ci.yml`：

* `lint`：静态校验四条红线（JSON 合法、无 CR、git-tree 与 `ports/node` 一致、port 自包含）。
* `build`：**五个**平台 × 清单模式编译 `test/`，然后 `ctest` 跑全部四组
  （smoke / unit / coexist / node 官方套件）。每个 job 加了 `timeout-minutes`，
  被超时取消时 `if: always()` 的收集步骤仍会把日志带走。
* `logs`：把各平台的日志合成**一个** `ci-logs` 归档（下载一次即可），
  里面还带 `ctest.log` 与用例清单；每个 job 的"首错"和 ctest 摘要直接写进 run 页面的
  job summary，不必下载就能看。

CI 固定用 vcpkg `2026.07.29`（不是 runner 预装的那个）。
