# 消费端验证工程（不只是冒烟）

这个目录是**独立于 port 的验证工程**，站在"使用者"视角回答两件事：

1. **node port 能不能正常接入？**（overlay-port + manifest + CMake preset，主项目 + 子项目结构）
2. **把 node port 和一批 vcpkg 库一起链进同一个使用者工程会不会出问题？**
   尤其是与 **v8 内嵌第三方同名**的那些（abseil / highway / simdutf / zlib）——
   这类"同一个库的两份拷贝"最容易出符号冲突、COMDAT 静默折叠、行为漂移。

它同时是 CI 的验证入口：`cmake --preset ... && cmake --build --preset ... && ctest`。

## 目录结构

```
test/
├── vcpkg.json                 # 依赖：node[test-suite,tools] + 一批"共存候选"库（显式声明）
├── vcpkg-configuration.json   # overlay-ports -> ../ports；overlay-triplets -> cmake/triplets
├── CMakePresets.json          # 六个平台的构建入口
├── CMakeLists.txt             # 主项目：find_package(node)、enable_testing()、编排子目录
├── app/                       # 子项目：node 嵌入可执行（产物名故意叫 node）
├── unit/                      # 子项目：gtest 单元测试（vcpkg 库自身 + 与 node 共存）
├── coexist/                   # 子项目：行为级共存（一段 JS 把各库提供的能力全跑一遍）
├── tests/                     # ctest 胶水：node 官方套件 + 符号审计
└── cmake/                     # 本工程（消费端）自己拥有的 triplet / toolchain
```

## 四组 ctest 用例（用 `-L` 选择）

| label | 内容 | 说明 |
|---|---|---|
| `smoke` | `node -e "process.stdout.write(process.versions.node)"` == `24.21.0` | 最小"链接成功 + 跑得起来 + 版本对得上" |
| `unit` | gtest：`unit_vcpkg_baseline`（只链 vcpkg 库）与 `unit_node_coexist`（同时链 node::node） | 两个可执行分开，失败时能立刻区分"库自己有毛病"还是"共存有毛病" |
| `coexist` | ① `coexist.js`（zlib/brotli/crypto/ICU/IDN/sqlite/http/http2/worker/wasm 全走一遍）② **`mutual_roundtrip`（一个进程里同时链 node 与那批可能重复的 vcpkg 库，C++ 侧与同进程的 node 运行时互相消费对方产物、双向复核）** ③ 符号审计 | 行为级证据，② 是最硬的一层 |
| `node-suite` | **node 官方测试套件**，由官方 `tools/test.py --shell=<本工程的可执行>` 驱动 | 见下 |
| `tools` | port 的 `tools` feature 产物：`node_EXECUTABLE` 跑版本断言 + `npm/npx/corepack --version` | 只从 `find_package(node)` 导出的变量拿路径 |

```sh
ctest --test-dir build/<preset> --output-on-failure            # 全部
ctest --test-dir build/<preset> -L unit --output-on-failure     # 只要单元测试
ctest --test-dir build/<preset> -L node-suite -j 4              # 官方套件（可并行）
ctest --test-dir build/<preset> -N                              # 只列用例
```

## 官方测试套件是怎么跑起来的

* 套件**不由 port 源码目录提供**，而是 port 的 `test-suite` feature 装到
  `<prefix>/share/node/test-suite/`（`test/` 全量 + `tools/test.py`），
  消费端从**安装产物**里拿 —— 依赖方向仍然只有"消费端 → port"。
* 驱动用 node 官方的 `tools/test.py`，`--shell=` 指向本工程编译出来的 `app/node`。
  为什么不用 `node --test`：各套件下的 `*.status` 记录着上游标记的 SKIP / FLAKY 用例，
  **只有 test.py 会读**；`node --test` 会把这些状态全丢掉，于是满屏假失败。
* `app/main.cpp` 因此要**忠实**：argv 原样交给 `node::Start`，Windows 上按上游用
  `wmain` 并把 argv 转成 UTF-8（官方 `src/node_main.cc` 就是这么写的）。
* 分片：test.py 原生支持 `--run=<第几片>,<总片数>`，本工程把它映射成多个 ctest 用例，
  交给 `ctest -j` 并行：`-DNODE_PORT_TEST_SHARDS=4`。
* 上游标记的 flaky 用例默认按 `dontcare` 处理（跑，但不拿它的失败点红灯）——
  我们不是上游 CI，用默认的 `run` 会让已知不稳定用例反复把红灯点亮。

常用开关（都是 CMake cache 变量）：

| 变量 | 默认 | 作用 |
|---|---|---|
| `NODE_PORT_TEST_NODE_SUITE` | `ON` | 是否注册官方套件用例 |
| `NODE_PORT_TEST_SUITES` | `parallel,sequential,message,abort,async-hooks,known_issues,module-hooks,es-module,report` | 要跑哪些套件（逗号分隔；留空 = test.py 默认集合） |
| `NODE_PORT_TEST_SHARDS` | 空 | 每个套件切几片 |
| `NODE_PORT_TEST_SKIP` | 空 | 追加跳过表（只该放环境相关、非库问题的用例） |
| `NODE_PORT_TEST_JOBS` | 空 | test.py 的 `-j` |
| `NODE_PORT_TEST_FLAKY_MODE` | `dontcare` | `--flaky-tests` 取值 |

## 共存是怎么被"证明"的

分四层，互相独立：

1. **能链接**：`unit_node_coexist` 同时链 `node::node`（内含 V8 与 v8 内嵌的 abseil /
   highway / v8_zlib）与同一批 vcpkg 库。重复的**强**符号会让链接器直接报错 ——
   链接成功本身就是一条证据。
2. **是同一份**：`node -p process.versions.X` 与我方进程里直接调用库得到的版本号比对。
   `uv` / `zlib` / `brotli` 在 node 里是**运行期**取值（`uv_version_string()` /
   `zlibVersion()` / `BrotliEncoderVersion()`），所以这条能证明"node 用的就是我们链的这份"；
   其余是编译期宏，比对它们证明**头文件**也是同一份（头不一致同样会踩 ABI）。
   还加了一条行为级旁证：同输入同参数下，node 的 `deflateSync` 与我们 `compress2` 的
   字节必须完全一致。
3. **行为对**：`coexist.js` 把 zlib / brotli / openssl / ICU / ada / sqlite / llhttp /
   nghttp2 / libuv / V8 提供的 node 能力逐个真跑。
4. **符号审计**：`tools/symbol_check.js` 扫 node 自带库与 vcpkg 库的**强符号**交集
   （COMDAT / 弱符号重复是允许的，单独评估）。有交集即红。
   Windows 走 `dumpbin /symbols`、其它平台走 `nm -g --defined-only`；
   由**本工程自己编出来的 node**（`node_embed`）执行 —— ctest 里跑的都是 C / JS，
   工具也该一致，顺带还是一次自检。
   **只扫 node 自己装的那几个库**：`<prefix>/lib` 在 manifest 模式下是整个工程共用的，
   里面还混着本工程自己声明的 gtest / fmt；不区分就会"自己比自己"、满屏假阳性。
   清单来自 `node-config.cmake` 导出的 `node_INSTALLED_LIBRARIES`。
5. **openssl 行为面**：`coexist/openssl_surface.js`（标签 `openssl`）——
   node 自带 openssl 换成 vcpkg 那份后的能力核对，见根 `docs/暂时还没做.md` §5h。

## 依赖方向（只有一条）

```
test ──(overlay-ports)──> ports/node
```

* `ports/node/` 自包含：不含 triplet / toolchain，也不引用 port 目录外的任何文件。
* triplet / toolchain 属于**消费端**，放在本工程 `cmake/` 下；Windows 需要 clang-cl 时，
  triplet 用 vcpkg 标准变量 `VCPKG_CHAINLOAD_TOOLCHAIN_FILE` 把工具链**交接**给 port。
* 官方套件这类"消费端需要的内容"，走 port 的**安装产物**（`share/`）输出，而不是让
  消费端去 port 源码目录里拿。

## 平台口径（六个 triplet；CI 跑其中五个）

| preset | triplet | 编译器 | CI |
|---|---|---|---|
| `windows-clang-cl` | `x64-windows-static-clang` | clang-cl + 静态 CRT | Tier 1（硬门） |
| `linux` | `x64-linux` | gcc，静态库 | Tier 1（硬门） |
| `linux-arm64` | `arm64-linux` | gcc，静态库 | Tier 2（允许失败） |
| `windows-clang-cl-arm64` | `arm64-windows-static-clang` | clang-cl + 静态 CRT | Tier 2 |
| `macos` | `arm64-osx` | clang，静态库 | Tier 2 |
| `macos-x64` | `x64-osx` | clang，静态库 | 不在 CI（macos-13 资源紧张，见欠账清单 2b） |

全部 release-only。分层含义见仓库根 `README.md`。
