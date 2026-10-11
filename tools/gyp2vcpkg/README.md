# gyp2vcpkg

把 **node 的 gyp 工程**翻成 CMake 片段的小工具。

它只提供"能力"，**不认识调用方是谁**：不写死任何项目专有的变量名、不写死调用方的目录、
不往调用方的工程里塞 CMake 逻辑。产物只有一种 —— 一堆**只 `set()` 变量**的 `.cmake`
片段；怎么把这些变量变成目标（`add_library` / `add_custom_command`）是调用方自己的事。
调用方用一份**自己的**配置文件（`--config`）告诉它：解析哪棵树、要哪些目标/动作、
生成的片段里该用什么变量名。

因为它不认项目，所以除了给 fe 用，也能给任何"要从 node 的 gyp 里取编译配置"的项目用。

## 三步管线

```
1. resolve  用 node 自带的 gyp（gyp-next 0.22.2）解析 .gyp  →  gyp_resolved.json
2. collect  收成编译配置数据集（路径归一，只留建 CMake 要用的字段）
3. generate 翻成 CMake 片段（只做"gyp 的写法 → CMake 的写法"）
```

为什么要分三步：**不自写 gyp 解析器**。gyp 的语义散在 `input.py` 三千行里 —— 合并
后缀、singleton 去重、路径相对化、early/late/latelate 三阶段、dependent settings、
static lib 调整、list filters、命令展开…… 自写解析器漏掉其中任何一条，都要到**链接期**
才暴露（踩坑-18 就是这么来的）。所以第一步直接用 node 自带的 gyp，写一个自定义
generator 把它跑完 14 步之后的 `target_dicts` dump 出来 —— 拿到的是最终、完整、正确的结果。

三步各自的接口**就是一个 JSON 文件**，所以能分开跑、分开查、分开测：

```bash
python <本目录>/gyp2vcpkg.py all      --config <调用方的配置.json> --env <label>=<变量环境.json> [...]
python <本目录>/gyp2vcpkg.py resolve  --config ... --env ...   # 只跑到第 1 步
python <本目录>/gyp2vcpkg.py collect  --config ... --env ...   # 只跑到第 2 步
python <本目录>/gyp2vcpkg.py generate --config ... --env ...   # 只跑到第 3 步
python <本目录>/gyp2vcpkg.py diff     --config ... --env ...   # 与已入库的片段粗比对
```

其它选项：`--node-root <path>`（覆盖配置里的 node_root）、`--out <dir>`、`--work <dir>`。
`--env <label>=<路径>`（可重复）把某平台的变量环境指给解析器 —— 每个平台一份，路径相对**当前
工作目录**（也会照这个样子记进片段文件头的指纹行，供调用方对账）。**变量环境不写在配置里**：
它由调用方产出并从中传进来。

## 配置文件

每个字段见同目录 **`example.json`**（配置模板 + 字段说明 + **产物契约**：每份片段会
`set()` 哪些变量）。调用方复制一份到自己工程里改。

要点：

* `node_root` 指向 node 源码树（里面要有 `tools/gyp/pylib`）；
* `entry_gyp` 一般只写一个（`node.gyp`）：它的 `dependencies` 会把 `v8.gyp`、
  `abseil.gyp`、`inspector_protocol.gyp` 一起拉进来；
* `platforms` 每平台跑一次（win 与 linux 求出来的集合不一样）；变量环境由 `--env` 传，
  不在配置里写死；
* `cmake` 段决定片段里用哪些变量名 —— 这是"不侵入调用方"的关键：
  `FE_V8_*` / `NODE_ROOT` 这类名字是 **fe 在自己的配置里配的**，不在本工具里。

## 文件

| 文件 | 职责 |
| --- | --- |
| `gyp2vcpkg.py` | CLI：派发三步、生成文件头（指纹行） |
| `resolve.py` | 调 node 自带 gyp；变量环境注入（标量 `-D`、非标量写进 `-I` 的 gypi；按 label 补 `OS`） |
| `_dump_generator.py` | 自定义 gyp generator：把 `target_dicts` dump 成 JSON；四个目录变量落成互不相同的值 |
| `collect.py` | 收数据集；路径归一（四类哨兵） |
| `generate.py` | 数据集 → CMake 片段（只 `set()` 变量） |
| `example.json` | 配置模板与产物契约 |

## 已踩过的坑（都写在调用方仓库的 `docs/踩坑记录/` 里）

* action 命令行里"像路径"的不都是路径 —— 见 fe 的 `踩坑-28`；
* 哨兵会被塞在路径中间 —— 见 fe 的 `踩坑-29`；
* gyp 的 `direct_dependent_settings` 会把**源**并进依赖方 —— 见 fe 的 `踩坑-30`。
