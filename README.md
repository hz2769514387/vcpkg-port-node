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
| **Tier 2** | 进了 CI 矩阵但**允许失败**；声明可过、未保证 | `arm64-windows-static-clang`、`arm64-linux`、`x64-osx`、`arm64-osx`；MSVC 口径、debug 构建、动态 CRT 变体 |
| **Tier 3** | **结构性不支持**（vcpkg 直接报错或 `supports` 字段挡掉） | 动态库交付、32 位、mingw、android / ios |

全部 release-only（triplet 里 `VCPKG_BUILD_TYPE release`）。
未做与待办逐项列在 `docs/暂时还没做.md`。

## 目录结构

```
ports/node/          自包含的 port：只有 portfile.cmake / vcpkg.json / patches/ / usage
                     不引用 port 目录外的任何文件，不含 triplet / toolchain
test/                消费端示例（主项目 + 子项目），同时就是 CI 的冒烟
├── cmake/triplets/   六个平台的 triplet      ← 属于消费端
├── cmake/toolchains/ clang-cl + MSVC 命令行环境 ← 属于消费端
└── app/              真正嵌入 node 的可执行
tools/               维护工具：version_tree.py（版本表）、symbol_check.py、gyp2vcpkg/
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

`.github/workflows/ci.yml`：`lint` 做静态校验（JSON、换行符、git-tree、port 自包含），
`build` 在六个平台上用清单模式编译 `test/` 并真跑 `smoke -e "process.stdout.write(process.versions.node)"`，
`logs` 把六个平台的日志合成**一个** `ci-logs` 归档（下载一次即可）。
失败的"首错"会直接写进 run 页面的 job summary，不必下载也能看。

CI 固定用 vcpkg `2026.07.29`（不是 runner 预装的那个）。
