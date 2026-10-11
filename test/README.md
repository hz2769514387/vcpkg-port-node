# 消费端示例（overlay-port 推荐姿势）

这个目录是一个**独立于 port 的示例工程**，用来演示"使用者该怎么接入本仓库的 node port"。
它本身就是 CI 的 L3 冒烟：用 vcpkg 装出 node，再 `find_package(node)`、链接 `node::node`、真跑一段 JS。

## 目录结构（主项目 + 子项目）

```
test/
├── vcpkg.json                 # 主项目清单：依赖 node（overlay 提供）
├── vcpkg-configuration.json   # overlay-ports / overlay-triplets 指向本仓库
├── CMakePresets.json          # 统一构建入口（各平台一个 preset）
├── CMakeLists.txt             # 主项目：find_package(node)
└── app/                       # 子项目：嵌入 node 的可执行
    ├── CMakeLists.txt
    └── main.cpp
```

## 使用

前置：环境变量 `VCPKG_ROOT` 指向 vcpkg 安装根。

```sh
# Windows
cmake --preset windows-clang-cl
cmake --build --preset windows-clang-cl
./build/windows-clang-cl/app/smoke -e "console.log(process.versions.node)"

# Linux
cmake --preset linux && cmake --build --preset linux

# macOS
cmake --preset macos && cmake --build --preset macos
```

只要 `vcpkg-configuration.json` 在，vcpkg manifest 模式会把 `../ports`、`../triplets`
当作 overlay 自动纳入，**不需要**再手敲 `--overlay-ports=`。这就是"给使用者带个好头"的接入方式。

## 平台口径

| preset | triplet | 说明 |
|---|---|---|
| `windows-clang-cl` | `x64-windows-static-clang` | clang-cl + 静态 CRT + 静态库（node 24+ Windows 官方口径） |
| `linux` | `x64-linux-ci` | gcc，release-only |
| `macos` | `arm64-osx-ci` | clang，release-only |