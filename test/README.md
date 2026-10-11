# 消费端示例（overlay-port 推荐姿势）

这个目录是一个**独立于 port 的示例工程**，用来演示"使用者该怎么接入本仓库的 node port"。
它本身就是 CI 的冒烟：用 vcpkg 装出 node，再 `find_package(node)`、链接 `node::node`、真跑一段 JS。

## 目录结构（主项目 + 子项目）

```
test/
├── vcpkg.json                 # 主项目清单：依赖 node（overlay 提供）
├── vcpkg-configuration.json   # overlay-ports -> ../ports；overlay-triplets -> cmake/triplets
├── CMakePresets.json          # 统一构建入口（各平台一个 preset）
├── CMakeLists.txt             # 主项目：find_package(node)
├── cmake/                     # 本工程（消费端）自己拥有的构建配置
│   ├── toolchains/            # clang-cl + MSVC 命令行环境
│   └── triplets/              # 六个平台的 triplet
└── app/                       # 子项目：嵌入 node 的可执行
    ├── CMakeLists.txt
    └── main.cpp
```

## 依赖方向（只有一条）

```
test  ──(overlay-ports)──>  ports/node
```

* `ports/node/` 是**自包含**的 port：只有 `portfile.cmake` / `vcpkg.json` / `patches/` / `usage`，
  不含 triplet / toolchain，也不引用 port 目录外的任何文件 —— 这样它才能被别人拿去用、
  将来也才能提交到 vcpkg registry。
* triplet 与 toolchain 属于**使用者的构建配置**，所以放在本工程（消费端）的 `cmake/` 下。
* Windows 需要 clang-cl 时，triplet 用 vcpkg 的标准变量 `VCPKG_CHAINLOAD_TOOLCHAIN_FILE`
  把工具链交给 port —— port 只读这个变量，不关心它从哪来。换成你自己的 clang-cl 工具链同样能工作。

## 使用

前置：环境变量 `VCPKG_ROOT` 指向 vcpkg 安装根。

```sh
# Windows x64（clang-cl + 静态 CRT，node 24+ 官方口径）
cmake --preset windows-clang-cl
cmake --build --preset windows-clang-cl
./build/windows-clang-cl/app/smoke -e "console.log(process.versions.node)"

# Linux x64
cmake --preset linux && cmake --build --preset linux

# macOS arm64
cmake --preset macos && cmake --build --preset macos
```

只要 `vcpkg-configuration.json` 在，vcpkg manifest 模式会把 `../ports`、`cmake/triplets`
当作 overlay 自动纳入，**不需要**再手敲 `--overlay-ports=`。这就是"给使用者带个好头"的接入方式。

## 平台口径（六个 triplet）

| preset | triplet | 编译器 | CI 保证 |
|---|---|---|---|
| `windows-clang-cl` | `x64-windows-static-clang` | clang-cl + 静态 CRT | ✅ 实测保证 |
| `windows-clang-cl-arm64` | `arm64-windows-static-clang` | clang-cl + 静态 CRT | ⚠️ 未实测（Tier 2） |
| `linux` | `x64-linux` | gcc，静态库 | ✅ 实测保证 |
| `linux-arm64` | `arm64-linux` | gcc，静态库 | ⚠️ 未实测（Tier 2） |
| `macos` | `arm64-osx` | clang，静态库 | ⚠️ 未实测（Tier 2） |
| `macos-x64` | `x64-osx` | clang，静态库 | ⚠️ 未实测（Tier 2） |

全部 release-only（triplet 里设 `VCPKG_BUILD_TYPE release`，省盘省时）。
详细的 Tier 1/2/3 分层见仓库根 `README.md` 的支持矩阵。
