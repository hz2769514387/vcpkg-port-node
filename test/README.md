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
├── CMakeLists.txt             # 主项目：find_package(unofficial-node)、enable_testing()、编排子目录
│
├── example_embed/             # 【示例】把 node 嵌进自己的可执行（自带 2 条测试）
├── example_coexist/           # 【示例】node 与 vcpkg 同名库共存（自带 3 条测试）
│
├── test_vcpkg_baseline/       # 【内部测试】vcpkg 那批库自身正常（不链 node）
├── test_node_coexist/         # 【内部测试】node 报的依赖 == vcpkg 装的那份（交叉核对）
├── test_official_suite/       # 【内部测试】node 官方测试套件
├── test_symbols/              # 【内部测试】符号审计（重复强符号）+ 它的 symbol_check.js
├── test_tools/                # 【内部测试】tools feature 的 npm/npx/corepack 冒烟
│
└── cmake/                     # 共享：本工程（消费端）自己拥有的 triplet / toolchain / 跳过清单
```

### 两组目录的区分（按前缀）

| 前缀 | 谁看 | 规矩 |
|---|---|---|
| `example_*` | **消费方** | 每个示例只演示**一种**使用场景；**必须自带测试**（示例要真能跑通，也顺带给消费方做个"项目该有测试"的样子）。以后可以加更多示例，一个场景一个目录 |
| `test_*` | **本仓库自己** | 验证这个 port 有没有做对；每个目录都有自己的 `CMakeLists.txt`（一眼看得出它是 ctest 目标），里面若要有脚本，脚本也放本目录 |
| `cmake/` | 共享 | triplet / toolchain / 跳过清单，不属于上面两组 |

两条纪律：**不重复**（示例演示"怎么用"，内部测试核对"对不对"，同一件事只在一处做）；
**不耦合**（任何 `example_*` / `test_*` 单独删掉，其它任何一个都照跑 —— 官方套件要 shell 时会优先用
`example_embed` 编出来的可执行，没有则退回端口装出来的 `node_EXECUTABLE`，而不是硬依赖示例）。

## ctest 用例（用 `-L` 选择）

| label | 用例 | 属于 |
|---|---|---|
| `example` | `example-embed-node-version`（版本断言）、`example-embed-run-js`（跑一段 JS 并断言输出） | example_embed 自带 |
| `example` | `coexist-node-runtime`、`coexist-openssl-surface`、`coexist-mutual-in-process` | example_coexist 自带 |
| `internal` | `test-vcpkg-baseline`（只链 vcpkg 库，不链 node） | 内部：库自身正常 |
| `coexist` | `test-node-coexist`（node 报的依赖 == vcpkg 装的那份） | 内部：端口一致性核对 |
| `node-suite` | `node-suite`（node 官方测试套件，`tools/test.py --shell=<可执行>`） | 内部 |
| `symbols` | `symbols-no-duplicate-strong`（重复强符号审计，Windows） | 内部 |
| `tools` | `tools-node-runs` / `tools-npm-version` / `tools-npx-version` / `tools-corepack-version` | 内部 |

其中两项值得单独说：

* `coexist-mutual-in-process`：**最硬的一层** —— 一个进程里同时链 `unofficial::node::node`
  与那批"可能和 node 依赖重复/冲突"的 vcpkg 库，C++ 侧与同进程的 node 运行时互相消费
  对方的产物并各自复核；
* `test-vcpkg-baseline` 与 `test-node-coexist` 故意分成两个可执行：一个只链 vcpkg 库、
  一个同时链 node ⇒ 失败时能立刻区分是"库自己有毛病"还是"共存有毛病"。

```sh
ctest --test-dir build/<preset> --output-on-failure            # 全部
ctest --test-dir build/<preset> -L unit --output-on-failure     # 只要单元测试
ctest --test-dir build/<preset> -L node-suite -j 4              # 官方套件（可并行）
ctest --test-dir build/<preset> -N                              # 只列用例
```

## 官方测试套件是怎么跑起来的

* 套件**不由 port 源码目录提供**，而是 port 的 `test-suite` feature 装到
  `<prefix>/share/node/test-suite/`（`test/` 全量 + `tools/` + `doc/` + `deps/{npm,corepack,acorn}`
  + `benchmark/` `lib/` `src/` `CHANGELOG.md`），消费端从**安装产物**里拿 ——
  依赖方向仍然只有"消费端 → port"。
  为什么要连那些兄弟目录一起装：官方用例是按"在源码树里跑"写的，有一批会读
  `doc/api/cli.md`、`deps/npm/package.json`、`benchmark/_cli.js` …，缺了就是
  ENOENT/MODULE_NOT_FOUND 的假失败（run #21 里 12 个失败属于这一类）。
* 驱动用 node 官方的 `tools/test.py`，`--shell=` 指向 `example_embed` 编出来的 `node`（没有它则退回端口装出来的 `node_EXECUTABLE`）。
  为什么不用 `node --test`：各套件下的 `*.status` 记录着上游标记的 SKIP / FLAKY 用例，
  **只有 test.py 会读**；`node --test` 会把这些状态全丢掉，于是满屏假失败。
* `example_embed/main.cpp` 因此要**忠实**：argv 原样交给 `node::Start`，Windows 上按上游用
  `wmain` 并把 argv 转成 UTF-8（官方 `src/node_main.cc` 就是这么写的）。
* 默认口径 = 上游的 `make jstest`：**一个 test.py 进程**（套件全列在位置参数上），
  并行度交给 `-j`（CI 里由 `$VCPKG_MAX_CONCURRENCY` 决定），并在 ctest 里标 `RUN_SERIAL`
  —— 不与其他用例并发。理由：
  * `test/common/tmpdir.js` 用 `.tmp.${TEST_SERIAL_ID||TEST_THREAD_ID}` 命名临时目录，这两个
    id 都是**每个 test.py 进程内部**从 0 起算的 ⇒ 两个并发 test.py 会撞同一个 `.tmp.1`，
    互相删掉对方的临时目录（EPERM / unlink ENOENT，run #21 实测 3 个）。
  * `sequential/` 的用例是"独占机器"写的（固定端口），并发跑就是 `EADDRINUSE`（run #21 实测）。
* 想分片也可以：`-DNODE_PORT_TEST_SHARDS=4` 会退回"套件 × 分片"的多个 ctest 用例；
  此时每个用例都会拿到自己的 `--temp-dir`（`build/<preset>/node-suite-tmp/<用例名>`），
  sequential 那几个分片会被标成 `RUN_SERIAL`（一次只跑一个）。
* 上游标记的 flaky 用例默认按 `dontcare` 处理（跑，但不拿它的失败点红灯）——
  我们不是上游 CI，用默认的 `run` 会让已知不稳定用例反复把红灯点亮。

常用开关（都是 CMake cache 变量）：

| 变量 | 默认 | 作用 |
|---|---|---|
| `NODE_PORT_TEST_NODE_SUITE` | `ON` | 是否注册官方套件用例 |
| `NODE_PORT_TEST_SUITES` | `parallel,sequential,message,abort,async-hooks,known_issues,module-hooks,es-module,report` | 要跑哪些套件（逗号分隔；留空 = test.py 默认集合） |
| `NODE_PORT_TEST_SHARDS` | 空 | 每个套件切几片（空 = 一个进程跑完，见上） |
| `NODE_PORT_TEST_SKIP` | 空 | **额外**的跳过表（逗号分隔）；长期有效的跳过要放进 `cmake/node-suite-skips.txt` |
| `NODE_PORT_TEST_JOBS` | `$env{VCPKG_MAX_CONCURRENCY}` | test.py 的 `-j` |
| `NODE_PORT_TEST_FLAKY_MODE` | `dontcare` | `--flaky-tests` 取值 |

### 跳过清单：`cmake/node-suite-skips.txt`

长期有效的跳过集中在**一个文件**里，格式是 `用例名 | 平台 | 理由`（平台 `all`/`windows`/`linux`/`macos`）。
这样做的原因有两条：

* 之前同一份列表在三个 preset 里各抄了一遍，改一条要在三处同步；
* 更要紧的是**理由**。跳过是最容易掩盖真 bug 的动作，可理由原本只写在提交信息里 ——
  现在它必须跟条目同行，而且**理由为空会在配置期就 FATAL_ERROR**（规则见文件顶部的判据，
  以及 `.workbuddy/个人工作流/docs/暂时还没做.md` §5b）。

`NODE_PORT_TEST_SKIP` 只是往这个清单**追加**临时条目，不要在那儿堆长期条目 —— 那样会绕过
"理由必须写清"的检查。

★ 配置期会打印一行 `node 官方套件额外跳过（<平台>）：…` —— **以它为准**，别以文件内容为准。
`NODE_PORT_TEST_SKIP` 是 cache 变量，改 preset **不会**清掉构建目录里的旧值（实测踩过：
preset 里删掉的两条旧条目被 cache 带着继续生效，而且因为整串是"逗号拼接的一个元素"，
去重也没去掉）。遇到这种情况用 `cmake --preset <名字> -DNODE_PORT_TEST_SKIP=` 显式清空。

## 共存是怎么被"证明"的

分四层，互相独立：

1. **能链接**：`unit_node_coexist` 同时链 `unofficial::node::node`（内含 V8 与 v8 内嵌的 abseil /
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
