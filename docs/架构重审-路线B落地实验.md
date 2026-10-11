# 路线 B 落地实验（Windows 实机）

> 承接 `架构重审-路线抉择.md`（第三轮结论：路线 B = gyp → ninja → vcpkg 构建）。
> 本篇记录**第四轮**把路线 B 真正跑起来过程中的全部实测发现。
> 所有结论均为 **Windows + VS2022 + vcpkg** 上的实机结果，不是推断。
>
> 实验树：`%TEMP%\rtB\node-src`（node v24.21.0 完整源码树）。
> 依赖：`C:/work/vcpkg/packages/*_x64-windows-static-clang/`（各 port 的 install 结果）。

## 0. 一句话结论

**路线 B 已在 Windows 上完整跑通：`node_base.lib`（364 MB）159/159 步编译成功，零错误。**

要让 gyp→ninja 这条路在 Windows 上成立，**核心是必须让 gyp 用 clang-cl**
（P12，写进 `config.gypi` 的 `make_global_settings`），否则生成的 DevTools 协议头
在 `cl.exe` 下**无解**（C2244）。在此基础上另需 P1–P3、P6–P10、P13、P14 共一批
"工具链/清单层"补丁；这些补丁**都不改变任何编进 node 的源码语义**，test 侧使用者无感。

> **重大更正**：早先认为的 **P11（改 DevTools 模板）经复测证伪、已撤销** ——
> 上游原样写法在 clang-cl 下本就能编译（§11.6）。真正的问题是"gyp 没用上 clang-cl"。

---

## 0.1 里程碑：clang-cl 下 node_base 编译通过（本轮实机）

```
[159/159] LIB obj\node_base.lib
NINJA_RC=0
-rw-r--r-- 364678034  obj/node_base.lib      # 364 MB
warning 统计：56×nullability + 5×SQLITE 宏重复 + 1×未用变量 = 全部无害
```

编译覆盖：`src/**` 全部核心、`src/inspector/**`（含全部 DevTools 协议生成代码）、
`src/crypto/**`（OpenSSL 3.6.3 走 vcpkg）、`gen/node_javascript.cc`（JS2C）等。

**此前逐一卡死并解决的节点（按出现顺序）**：

| 次序 | 症状 | 根因 | 补丁 |
|---|---|---|---|
| 1 | `LNK1104 z.lib` | 库名错 | 库名对齐（§11.2） |
| 2 | `LNK4044 /LC:/...` | 裸 `-L` 进了 rsp | P6a+P6b |
| 3 | `LNK1104 libbrotlidec.lib` | brotli 无 `lib` 前缀 | 库名对齐 |
| 4 | `LNK2019 __imp_htons` | `--shared-*` 丢掉系统库 | P8 |
| 5 | `C1083 node_base.node_pch.h.pch` | 上游 gyp `map` bug | P7+P9 |
| 6 | `C1083 "tools/msvs/pch/node_pch.h"` | PCH 路径非 build 相对 | P10a/b/c |
| 7 | `error C2244`（协议头） | **gyp 退回了 cl.exe** | **P12** |
| 8 | `get_openssl_version` 探测失败 | clang-cl 忽略 `-dM` | P12a/d |
| 9 | `failed to get compiler predefines` | `shell=True` 拆路径 + `-dM` | P13 |
| 10 | `gen\node_javascript.cc: \u 非法转义` | JS2C 未处理 `\` 分隔符 | P14 |

---

## 1. gyp 的真实入口是 `tools/gyp_node.py`，不是 `gyp_main.py`

`tools/gyp_node.py` 是 node 官方入口（`Makefile:186` 用的就是它），它自动补上：

| 它替你做的事 | 值 |
|---|---|
| 位置参数 | `node.gyp` |
| `-I` | `common.gypi` + `config.gypi`（**顺序重要**） |
| `--depth` | `<node_root>` |
| `-D` | `component=static_library`、`library=static_library` |
| Windows | **不给** `--generator-output`（in-tree 输出到 `out/`） |

直接调 `gyp_main.py` 会缺 `config.gypi` → `gyp: name 'node_shared' is not defined`。

另外 `python` 变量必须由调用方传（`-Dpython=<解释器>`），否则 v8_gypfiles 报
`Undefined variable python`。

---

## 2. ★ `-D` 打不过 `-I`：`icu_gyp_path` 无法用 define 覆盖

`configure.py --with-intl=system-icu` 会把 `variables.icu_gyp_path = 'tools/icu/icu-system.gyp'`
写进 `config.gypi`，而 `gyp_node.py` 把它作为 `-I` 加载。

**gyp 里 `-I` 文件的优先级高于 `-D`**。实测：

```
-Dicu_gyp_path=C:/.../icu-vcpkg.gyp     ← 完全被忽略
→ gyp 仍去加载 tools/icu/icu-system.gyp
```

**推论**：本仓库已有的 `gyp2vcpkg/icu-vcpkg.gyp`（路线 A 为 `define_overrides` 写的）
**在路线 B 下用不上**。要覆盖 ICU 清单只有两条路：

1. 走 `--with-icu-path=<file>`（Chromium gyp 模式，configure.py:2214 那条分支）；
2. **patch node 自带的 `tools/icu/icu-system.gyp`**（见 P1，本轮采用）。

---

## 3. ★ P1 补丁：上游 `icu-system.gyp` 缺 `icudata` 目标

`tools/v8_gypfiles/v8.gyp:1315` 在 `OS=="win"` 分支里**无条件**依赖
`<(icu_gyp_path):icudata#target`：

```python
['OS=="win"', {
  'dependencies': [
    '<(icu_gyp_path):icudata#target',
  ],
}],
```

而 node 自带的 `tools/icu/icu-system.gyp` 只定义了 `icuuc` / `icui18n` 两个空壳目标：

```
gyp: Dependency '...\tools\icu\icu-system.gyp:icudata#target' not found
     while trying to load target ...\v8.gyp:v8_base_without_compiler#target
Error running GYP
```

→ **Windows + `--with-intl=system-icu` 是上游从未测过的组合**（Unix 上 `OS=="win"`
分支不进，所以上游 CI 永远碰不到）。

**修法**：补一个 `type: none` 的 `icudata` 空壳目标接住依赖边。
真正的 icudata 由 vcpkg 的 icu port 提供（pkg-config 的 `-licudt` 已在 `libraries` 里）：

```python
{
  'target_name': 'icudata',
  'type': 'none',
  'toolsets': ['host', 'target'],
},
```

实测补上后 `configure.py` **RC=0，零 warning**。

> 这与本仓库 `gyp2vcpkg/icu-vcpkg.gyp` 的做法完全一致（那个文件是为路线 A 写的
> `define_overrides` 版，注释里已解释过同一件事）。路线 B 下把它改为 patch 这个文件。

---

## 4. ICU 走 vcpkg 的官方路径 = `--with-intl=system-icu` + pkg-config

`configure_intl()` 的 `system-icu` 分支做的事：

1. `o['variables']['v8_enable_i18n_support'] = 1`
2. 调 `pkg_config(['icu-i18n', 'icu-uc'])` 取 libs / cflags / libpath / version
3. `o['libraries'] += libs.split()`、`o['include_dirs'] += ...`
4. `o['variables']['icu_gyp_path'] = 'tools/icu/icu-system.gyp'`（ICU 目标全变 `none`）

| 件 | 来源 |
|---|---|
| pkg-config 可执行 | vcpkg `vcpkg_find_acquire_program(PKGCONFIG)` → msys2 的 `pkgconf`，已缓存在 `downloads/tools/msys2/*/mingw64/bin/pkg-config.exe` |
| `.pc` 文件 | vcpkg 的 icu port **自带** `lib/pkgconfig/icu-i18n.pc` / `icu-uc.pc` / `icu-io.pc`（`prefix=${pcfiledir}/../..` 自相对，可移植） |
| 环境变量 | `PKG_CONFIG`（可执行路径）+ `PKG_CONFIG_PATH`（`.pc` 目录）；vcpkg 的 `z_vcpkg_setup_pkgconfig_path()` 是官方封装 |

实测：

```bash
PKG_CONFIG_PATH=<icu>/lib/pkgconfig pkg-config --libs-only-l icu-i18n icu-uc
# → -licuin -licuuc -licudt -lkernel32 -luser32 -lgdi32 -lwinspool -lshell32 \
#   -lole32 -loleaut32 -lcomdlg32 -ladvapi32
pkg-config --modversion icu-i18n icu-uc      # → 78.3
pkg-config --cflags-only-I icu-i18n icu-uc   # → -I<icu>/include
```

`config.gypi` 结果：

```
variables.icu_gyp_path  = tools/icu/icu-system.gyp
variables.icu_ver_major = 78
target_defaults.libraries = [..., '-LC:/work/vcpkg/packages/icu_.../lib',
                             '-licuin', '-licuuc', '-licudt', ...]
```

---

## 5. ★★ `CC` / `PKG_CONFIG` **必须**用正斜杠 + 双引号（shlex 吃反斜杠）

`configure.py` 里所有子进程调用都过 `shlex.split(...)`：

```python
CC = os.environ.get('CC', 'cc' if sys.platform == 'darwin'
                        else 'clang' if sys.platform == 'win32' else 'gcc')   # :24
proc = subprocess.Popen(shlex.split(CC) + args, ...)      # get_openssl_macros 等

pkg_config = os.environ.get('PKG_CONFIG', 'pkg-config')   # pkg_config():1207
proc = subprocess.Popen(shlex.split(pkg_config) + args, ...)
```

实测 `shlex.split` 对反斜杠路径的破坏：

```python
shlex.split(r'C:\work\vcpkg\...\pkg-config.exe')
# → ['C:workvcpkg...pkg-config.exe']      ← 反斜杠全被当转义符吃掉
shlex.split('C:/work/vcpkg/.../pkg-config.exe')
# → ['C:/work/vcpkg/.../pkg-config.exe']  ← 正确
```

后果：`OSError` → `pkg_config()` 静默返回 `(None, None, None, None)` → 上层报

```
ERROR: Could not load pkg-config data for "icu-i18n".
```

**规则**（写 portfile 时必须遵守）：

| 变量 | 正确写法 | 说明 |
|---|---|---|
| `CC` | `"C:/Program Files/.../clang.exe"` | **正斜杠 + 双引号**（引号让 shlex 合并含空格的路径） |
| `PKG_CONFIG` | `"C:/work/vcpkg/.../pkg-config.exe"` | 同上 |

**8.3 短名不可靠**：实测本机 C 卷**未启用 8.3**，`%~sI` 返回的还是长路径；
且 `PROGRA~1` 手拼不可移植。→ 只用"长路径 + 正斜杠 + 双引号"。

---

## 6. ★ `CC` 用 clang（不是 cl）才能探到 openssl 版本

`get_openssl_macros()` 执行：

```
CC -E -dM -include openssl/opensslv.h -include openssl/crypto.h -
                                                              ↑ 从 stdin 读
```

**MSVC 的 `cl.exe` 不接受 `-` 作 stdin**（实测 RC=3）。所以 `CC` 必须是支持
`-E -dM -` 的编译器。VS 自带 clang（`<VS>/VC/Tools/Llvm/x64/bin/clang.exe`）可用。

`openssl_version` 探测结果对照：

| `CC` 取值 | `openssl_version` | 说明 |
|---|---|---|
| 未设（PATH 无编译器） | `0x0` | 静默 fallback |
| `cl` | `0x0` | RC=3，MSVC 不吃 stdin |
| `clang.exe`（正斜杠 + 引号） | **`0x3060003f`** | = 3.6.3，与 vcpkg 精确一致 ✓ |

> **为什么这是硬门槛**：`openssl_version = 0` 会让 `deps/ncrypto/ncrypto.gyp` 的
> `openssl_version >= 0x3000000f` 判定为**假**，从而走错代码分支 —— 编出与 vcpkg
> 头文件不匹配的 ncrypto。这不是"少个可选优化"，是**正确性问题**。

---

## 7. ★★ P2 补丁：gyp 的 `QuoteForRspFile` 把 `key=value` 路径折叠掉

### 现象

`v8_inspector_headers` 的 `protocol_generated_sources` action，在生成的 ninja 里是：

```
"--config_value" "deps\v8\include\js_protocol.pdl"        ← 前缀 + ../../ 全丢
```

编译时报：

```
AttributeError: 'X' object has no attribute 'path'
  code_generator.py:365  self.generate_domains = self.read_protocol_file(config.protocol.path)
```

### 定位

`gyp -f gypd` dump 证明 **gyp 解析后的值完全正确**：

```
[8] '--config_value'
[9] 'protocol.path=../../deps/v8/include/js_protocol.pdl'
```

→ 崩在 **ninja generator 的 rsp 生成**。根因在
`tools/gyp/pylib/gyp/msvs_emulation.py` 的 `QuoteForRspFile()`
（由 `ninja.py:QuoteShellArgument` 调用）：

```python
# Use a heuristic to try to find args that are paths, and normalize them
if arg.find("/") > 0 or arg.count("/") > 1:
    arg = os.path.normpath(arg)
```

实测：

```python
os.path.normpath('protocol.path=../../deps/v8/include/js_protocol.pdl')
# → 'deps\\v8\\include\\js_protocol.pdl'
```

因为 `normpath` 把 `protocol.path=..` 当成一个**目录名**，随后的 `..` 用来弹出它 ——
`../../` 被整段抵消，连 `protocol.path=` 前缀一起消失。

### 修法（已实测生效）

含 `=` 的参数是 `key=value`，不是路径，跳过归一化：

```python
if "=" not in arg and (arg.find("/") > 0 or arg.count("/") > 1):
    arg = os.path.normpath(arg)
```

修复后 ninja 里为（**正确**）：

```
"--config_value" "protocol.path=../../deps/v8/include/js_protocol.pdl"
```

⚠ `gyp-win-tool` 是**生成物**（`win_tool.py` 被内联进脚本），改了 `msvs_emulation.py`
必须**重新跑 gyp** 才生效。

---

## 8. ★ P3 补丁：`win_tool.py` 的 5 处 `decode("utf-8")`

`tools/gyp/pylib/gyp/win_tool.py` 有 5 处硬编码 UTF-8 解码
（第 140 / 253 / 297 / 316 / 334 行，对应生成物 `gyp-win-tool` 的 141 / 254 / 298 / 317 / 335）：

```python
out = link.communicate()[0].decode("utf-8")
```

中文 Windows 上 link.exe 输出 GBK → 

```
UnicodeDecodeError: 'utf-8' codec can't decode byte 0xce in position 24
```

**`set VSLANG=1033` 缓解无效**：`gyp-win-tool` 的 `ExecLinkWrapper` 用
`env=self._GetEnv(arch)`（只带 VS 工具链环境），**不透传 `VSLANG`**。

**根治**：

```python
out = link.communicate()[0].decode("utf-8", errors="replace")
```

（5 处全改。`errors="replace"` 只在日志解码上兜底，不影响任何产物。）

这与上一轮发现的 `_FindDirectXInstallation`（`_dump_generator` 侧）是**同一类 locale 缺陷**。

---

## 9. ★ 19 个 `node_shared_*` 全都有对应选项；实际可替换 14 个

`configure.py` 为 **19 个库**都提供了 `--shared-<lib>`，包括容易被忽略的几个：

| 库 | 选项名 | 对应 vcpkg port |
|---|---|---|
| llhttp | `--shared-http-parser`（注意不是 `--shared-llhttp`） | ✓ `llhttp` |
| simdutf | `--shared-simdutf` | ✓ `simdutf` |
| nghttp3 | `--shared-nghttp3` | ✓ `nghttp3`（本次未装） |
| merve | `--shared-merve` | ✗ 无 port |
| nbytes | `--shared-nbytes` | ✗ 无 port |
| uvwasi | `--shared-uvwasi` | ✗ 无 port |
| gtest | `--shared-gtest` | ✓ 有 port，但 node 不编测试 |

实测打开 **14 个**（不含 nghttp3/gtest/merve/nbytes/uvwasi）后，`config.gypi` 里：

```
node_shared_* == 'true' (14):
  ada brotli cares hdr_histogram http_parser libuv nghttp2 ngtcp2
  openssl simdjson simdutf sqlite zlib zstd

node_shared_* == 'false' (5):
  gtest merve nbytes nghttp3 uvwasi
```

### `obj/deps/` 的变化（最有说服力的证据）

| 阶段 | `out/Release/obj/deps/` |
|---|---|
| 未打开 shared | 14 个目录（zlib / openssl / libuv / brotli / c-ares / nghttp2 / ngtcp2 / zstd / simdjson / simdutf / sqlite / ada / hdr-histogram / llhttp…） |
| 打开 14 个 shared 后 | **6 个**：`googletest inspector_protocol merve nbytes ncrypto uvwasi` |

- **ICU 目录整个消失** → `--with-intl=system-icu` 生效；
- **llhttp 目录消失** → `--shared-http-parser` 生效；
- 剩下的 6 个都是 node 独有、vcpkg 上没有对应 port 的。

### node 可执行链接行（实测）

```
/LIBPATH:C:/work/vcpkg/packages/zlib_x64-windows-static-clang/lib
/LIBPATH:C:/work/vcpkg/packages/libuv_x64-windows-static-clang/lib
... 共 14 条 LIBPATH ...

libs = z.lib uv.lib ada.lib simdjson.lib simdutf.lib brotlidec.lib
       brotlienc.lib cares.lib hdr_histogram.lib nghttp2.lib ngtcp2.lib
       sqlite3.lib zstd.lib crypto.lib ssl.lib Dbghelp.lib winmm.lib
       Ws2_32.lib AdvAPI32.lib User32.lib
```

即 **vcpkg 的静态库全部进了链接行**，正是 vcpkg 精神要求的形态。

---

## 10. 路线 B 的完整调用序列（Windows 实测跑通）

```bat
:: 1) 环境
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
set CC="C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/Llvm/x64/bin/clang.exe"
set PKG_CONFIG="C:/work/vcpkg/downloads/tools/msys2/<hash>/mingw64/bin/pkg-config.exe"
set PKG_CONFIG_PATH=C:/work/vcpkg/packages/icu_x64-windows-static-clang/lib/pkgconfig
set GYP_MSVS_VERSION=2022
set GYP_MSVS_OVERRIDE_PATH=C:\Program Files\Microsoft Visual Studio\2022\Community
set DXSDK_DIR=C:\nonexistent      :: 绕过中文 locale 下 reg.exe 解码 bug

:: 2) configure.py（system-icu + 14 个 --shared-*）
python configure.py --with-intl=system-icu --shared-openssl ... --shared-hdr-histogram ...
::    → 写 config.gypi / config.mk，并**内部跑一次 gyp**；RC=0

:: 3) gyp → ninja（generator 名就是 `ninja`，**不是** `ninja-win`）
python tools/gyp_node.py -f ninja -Dpython=<py> -Dconfiguring_node=1 -Dbuild_type=Release
::    → out/Release/ 下 146 个 .ninja + gyp-win-tool

:: 4) 构建（用 vcpkg 的 ninja）
"<vcpkg>/downloads/tools/ninja-1.13.2-windows/ninja.exe" -C out/Release <target>
```

> ⚠ **更正（2026-10-11，本条原结论错误）**：原文写"不要用 `configure.py --ninja`，
> 它拼出 `-f ninja-win`，而 gyp 只有 `ninja` 这一个 generator 名，会解析失败"。
> 经逐行核对源码，`-f ninja-win` 是**合法**写法：`tools/gyp/pylib/gyp/__init__.py:89-90`
> 有
>
> ```python
> if "-" in format:
>     format, params["flavor"] = format.split("-", 1)
> ```
>
> 即 gyp 会把 `ninja-win` 拆成 `format=ninja` + `flavor=win`，然后正常 `import
> gyp.generator.ninja`。当初之所以得出"解析失败"，是因为用
> `importlib.import_module("gyp.generator.ninja-win")` 直接导入 —— 绕过了 gyp 自己的
> `Load()`，当然找不到 `gyp/generator/ninja-win.py`。走 gyp 的入口没有问题。
> 因此正式 portfile 用的是 `configure.py --ninja`（比"configure 走默认再手动 `-f ninja`"
> 少一步、也不依赖 `configure.py` 之外的调用约定）。

### 与 `vcpkg_build_ninja` 的接口

`vcpkg_build_ninja` 在 `${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-{dbg,rel}` 下
跑 `ninja -C`。而 gyp 的输出是 `out/{Debug,Release}`（gyp 口径），两者名称不同。

**两种接法**：

- **(a)** 让 gyp 输出到 vcpkg 期望的目录（`-Goutput_dir` / `--generator-output`），
  或生成后把 `out/Release` 映射到 `${...}-rel`；
- **(b)** 不用 `vcpkg_build_ninja`，直接用 `vcpkg_execute_build_process` +
  `vcpkg_find_acquire_program(NINJA)` 自己调。

（路线 B 的 portfile 实现待定，见 §12。）

---

## 11. 补丁清单与判据核对

用户给的判据：**"只要补丁不是改变原始库的行为、导致 test 的用户感觉奇怪或影响其他传递依赖，都可以 patch"**。

| # | 目标文件 | 补丁内容 | 是否改库行为 | 是否影响传递依赖 | 合规 |
|---|---|---|---|---|---|
| **P1** | `tools/icu/icu-system.gyp` | 补 `icudata` 空壳目标 | 否（只是接住依赖边） | 否 | ✅ |
| **P2** | `tools/gyp/pylib/gyp/msvs_emulation.py` | `QuoteForRspFile` 对含 `=` 参数跳过 normpath | 否（只修 rsp 文本） | 否 | ✅ |
| **P3** | `tools/gyp/pylib/gyp/win_tool.py` | 5 处 `decode("utf-8", errors="replace")` | 否（只影响日志解码） | 否 | ✅ |
| **P6a** | `tools/gyp/pylib/gyp/msvs_emulation.py` | `AdjustLibraries` 不再给 `-L<dir>` 拼 `.lib` | 否（只修工具链文本） | 否 | ✅ |
| **P6b** | `tools/gyp/pylib/gyp/generator/ninja.py` | win 分支把 `libraries` 里的 `-L<dir>` 转成 `/LIBPATH:<dir>` 并前置 | 否（只修工具链文本） | 否 | ✅ |
| **P7** | `tools/gyp/pylib/gyp/msvs_emulation.py` | `GetFlagsModifications` 把 `map(...)` 物化成 `list(...)` | 否（补全上游漏掉的消费） | 否 | ✅ |
| **P8** | `configure.py` | `configure_library()` 补回被跳过的 vendored 依赖的 Windows 系统库 | 否（补回本来就在链接行里的系统库） | 否 | ✅ |
| **P9** | `tools/gyp/pylib/gyp/ninja_syntax.py` | `variable()` 兜底消费非 str/int 的可迭代值 | 否（防同类 bug 复发） | 否 | ✅ |
| **P10a** | `tools/gyp/pylib/gyp/msvs_emulation.py` | `PrecompiledHeader._PchHeader()` 与 `MsvsSettings._GetPchFlags()` 把 PCH 头路径转成 build-dir 相对 | 否（只修工具链文本） | 否 | ✅ |
| **P10b** | `tools/gyp/pylib/gyp/generator/ninja.py` | 给 `GetCflagsC/CC` 传入 `self.GypPathToNinja` | 否（只修工具链文本） | 否 | ✅ |
| **P10c** | `tools/gyp/pylib/gyp/msvs_emulation.py` | 编 PCH 自身时剥掉 `/Yu`（只留 `/Yc`） | 否（对齐 MSVC 项目系统语义） | 否 | ✅ |
| ~~P11~~ | ~~`deps/inspector_protocol/templates/TypeBuilder_h.template`~~ | **经复测证伪，已撤销**：上游原样的过度限定写法在 **clang-cl 下可正常编译**（见 §11.6） | — | — | ✗ 不需要 |
| **P12a** | `configure.py` | `get_openssl_macros()`：CC 是 clang-cl 时改用同目录 `clang.exe --target=…-msvc` 做宏探针 | 否（只影响配置期探测） | 否 | ✅ |
| **P12b** | `configure.py` | 写 `make_global_settings` 时**剥掉** CC/CXX 两端的引号 | 否（gyp 自己会重新加引号） | 否 | ✅ |
| **P12c** | `tools/gyp/pylib/gyp/generator/ninja.py` | `endswith("clang-cl")` 同时接受 `clang-cl.exe` | 否（只影响工具链选择） | 否 | ✅ |
| **P13** | `tools/gyp/pylib/gyp/common.py` | `GetCompilerPredefines()`：`shell=False` + clang-cl→clang 探针 | 否（只影响配置期探测） | 否 | ✅ |
| **P12d** | `configure.py` | `get_openssl_version()` 防 `None[:2]` 崩溃 | 否（纯防御） | 否 | ✅ |
| **P14** | `tools/js2c.cc` | `GetFileId()` 把 `\` 归一成 `/`；`GetVariableName()` 把 `\` 也替换为 `_` | 否（只是让 Windows 路径也能生成合法标识符；POSIX 路径结果**逐字节不变**） | 否 | ✅ |
| **P16** | `deps/v8/src/torque/source-positions.cc` | `AddSource()`/`GetSourceId()` 归一化路径分隔符（`\`→`/`） | 否（只影响 torque 生成文件的归属查找；POSIX 下行为不变） | 否 | ✅ |
| **P17** | `tools/gyp/pylib/gyp/generator/ninja.py:1223` | win 分支的隐式 MASM 规则从 `.S` 收窄到仅 `.asm` | 否（`.S` 是 GAS 语法，MASM 结构上必然编不过；改动只把"必败构建"变成"按 MSBuild 语义忽略"） | 否 | ✅ |
| P4 | zlib | 见 `路线抉择.md` §4（19 个补丁中 8 个涉及 node 核心） | **待评估** | 待评估 | 待定 |
| P5 | openssl / sqlite / nghttp2 / ngtcp2 / brotli / c-ares / simdjson / zstd / ada / icu / hdr-histogram | 待普查 | 待评估 | 待评估 | 待定 |

**P1–P3、P6–P11 的性质**：都属于**工具链 / 清单层**的修补 —— 不改变任何一个会被编进 node 的
源码语义，也不改变任何被链接的库。test 侧使用者完全无感。**符合用户判据**。

### 11.3 ★ P8：`--shared-*` 会顺手丢掉依赖的 Windows 系统库（上游缺口）

`configure.py` 的 `configure_library()` 只往 `target_defaults.libraries` 里塞
**依赖自己的库**，完全不知道被跳过的 vendored `.gyp` 里还有 `link_settings.libraries`。
一旦 `--shared-libuv` / `--shared-cares`，那两段系统库就凭空消失：

| 被跳过者 | 丢失的系统库（来自其 .gyp） |
|---|---|
| `deps/uv/uv.gyp:204-215` | `advapi32 dbghelp ole32 iphlpapi psapi shell32 user32 userenv uuid ws2_32` |
| `deps/cares/cares.gyp:201-202` | `ws2_32.lib iphlpapi.lib` |

症状：`LNK2019: 无法解析的外部符号 __imp_htons / __imp_WSAGetLastError / __imp_socket`
（**libuv.lib 排在 ws2_32.lib 之前**，MSVC 从左到右解析）。

**修法**：在 `configure.py` 加一张 `shared_lib_windows_system_libs` 表，`configure_library()`
在写完依赖自己的库之后把它们**追加**在尾部（保证 MSVC 解析顺序）。

```python
shared_lib_windows_system_libs = {
  'libuv': ['advapi32','dbghelp','ole32','iphlpapi','psapi',
            'shell32','user32','userenv','uuid','ws2_32'],
  'cares': ['ws2_32','iphlpapi'],
}
# ...在 configure_library() 末尾：
if flavor == 'win':
  for syslib in shared_lib_windows_system_libs.get(lib, []):
    output['libraries'] += [f'-l{syslib}']
```

> 这类"`--shared-*` 丢链接设置"是一个**通用缺口**，不止 libuv/cares；后续每开一个
> `--shared-<dep>` 都要照此核对一遍它的 `.gyp` 里有没有 `link_settings.libraries`。

### 11.4 ★ P7 = node v24.21.0 **原生存**的 gyp bug（已用官方 tarball 逐字节证实）

`tools/gyp/pylib/gyp/msvs_emulation.py:1073/1079`：

```python
return (
    [("cflags_cc", map(expand_special, cflags_cc + pch_output))],   # ← map 没被消费
    self.output_obj,
    [],
)
```

而消费端 `ninja_syntax.py:31 variable()` 只处理 `None` 和 `list`：

```python
if value is None: return
if isinstance(value, list):
    value = " ".join(filter(None, value))
self._line(f"{key} = {value}", indent)      # ← map 直接 f-string 化
```

→ 生成的 ninja 里出现
**`cflags_cc = <map object at 0x000001A6688E4760>`**
→ PCH 编译命令丢掉 `/Yc` → `node_pch.h.pch` 从未生成
→ 所有依赖 PCH 的 `.cc` 报
`fatal error C1083: 无法打开预编译头文件 "node_base.node_pch.h.pch"`。

**为何上游 CI 不中招**：node 官方 Windows CI 走 **MSBuild（`.sln`）**，不走 `ninja`
生成器。`ninja` + PCH 的组合只有路线 B 会踩到 —— 所以这是**路线 B 自己的坑，不是
node 的回归**。

**已用官方 tarball 证实**（`/tmp/upcheck`，`nodejs-node-v24.21.0.tar.gz`）：
`msvs_emulation.py:1073/1079` 与 `ninja_syntax.py:31-36` **与实验树逐字节一致**，
即该 bug 是 v24.21.0 原生的，与本次重构无关。

**修法**：`list(map(...))`（P7）+ `variable()` 兜底（P9）。

### 11.5 ★ P10：PCH 头路径是"源根相对"，但 ninja 命令从 build 目录跑

`node.gypi:76-77` 写的是**源根相对**路径：

```python
'msvs_precompiled_header': 'tools/msvs/pch/node_pch.h',
'msvs_precompiled_source': 'tools/msvs/pch/node_pch.cc',
```

MSBuild 生成器没问题（VS 会把工程目录加进 include 路径）。但 ninja 的命令在
`out/Release` 下执行，`/FItools/msvs/pch/node_pch.h` 解析不到 →
`fatal error C1083: 无法打开包含文件 "tools/msvs/pch/node_pch.h"`。

> **对照**：v8 自己写的是 `<(V8_ROOT)/../../tools/msvs/pch/v8_pch.h`
> （`deps/v8` 下的相对路径），展开后**恰好**能同时从 `tools/v8_gypfiles/` 和
> `out/Release` 解析，所以 v8 的 PCH 一直没暴露这个问题 —— **纯属侥幸**。

**修法**：`PrecompiledHeader` 本来就存了 `gyp_to_build_path`（`__init__` 第 1043 行
用它转 `pch_source`），把 `_PchHeader()` 也走同一个转换即可：

- **P10a**：`_PchHeader()` 与 `_GetPchFlags()` 都转成 build-dir 相对；
- **P10b**：`ninja.py` 调 `GetCflagsC/CC` 时把 `self.GypPathToNinja` 传进去；
- **P10c**：编 PCH **自身**那一次要剥掉 `/Yu`（`cflags_cc` 里带的），只留 `/Yc` ——
  否则 cl 同时看到 `/Yu` 与 `/Yc`，PCH 建不出来。
  MSVC 自己的工程系统也会对这一个文件替换 usage 标志，这里只是对齐其语义。

修后（实测）：

```
cflags_cc = /TP /FI..\..\tools\msvs\pch\node_pch.h $
    /Fp${pchprefix}.node_pch.h.pch $
    /Yc..\..\tools\msvs\pch\node_pch.h
```

### 11.6 ★★ 决定性结论：clang-cl 是路线 B 在 Windows 上的唯一正解（P11 被证伪）

这是本轮**最重要**的发现。**`x64-windows-static-clang` 这个 triplet 名字里的 `-clang`
不是装饰 —— 它字面要求用 clang-cl 编译整套 node**，而 gyp 走 ninja 时**默认根本不会用 clang-cl**
（会退回 MSVC 的 `cl.exe`），于是踩上一串 cl.exe 独有的坑。

#### 证据链

| 场景 | 上游原样模板（`TypeBuilder_h.template:201`） | 结果 |
|---|---|---|
| **`cl.exe`**（gyp 的默认 win 行为） | `inline StorageId::StorageIdBuilder<STATE \| StorageId::StorageIdBuilder<STATE>::IsLocalStorageSet>&` | **`error C2244`**（纯 cl.exe 无解，v2–v11 复现实验全失败） |
| **`clang-cl.exe`** | 同一行、逐字节相同 | **编译通过（EXIT=0）** |

最小复现 `v12.cpp`（`%TEMP%\rtB\pchrepro\`）逐字抄上游写法，用 clang-cl `/c` 编译：

```
EXIT=0        ← clang-cl 完全接受上游原样写法
```

→ **P11（改模板）是伪需求，已撤销**。真正需要的是**让 gyp 用上 clang-cl**。

#### gyp 里"用 clang-cl"的唯一官方开关 = `make_global_settings`

`ninja.py:2285-2288`：

```python
if key == "CC":
    cc = os.path.join(build_to_root, value)
    if cc.endswith("clang-cl"):
        clang_cl = cc
...
if clang_cl:
    # 把 cl_<arch> 从 cl.exe 换成 clang-cl，并补 -m32/-m64
    master_ninja.variable("cl_" + arch, command)
```

而 `make_global_settings` 必须**对所有 target 一致**（`ninja.py:2809` 有
`assert make_global_settings == this_make_global_settings`），所以**不能写进 `node.gyp`**
（那样 v8 的子 gyp 会缺这一项而 `AssertionError`）——
**只能写进 `config.gypi`，因为所有 gyp 文件都 `-I` 它**。这也解释了
`configure.py:2612-2627` 为什么早就留了 `output['make_global_settings']` 的口子却从未被填充：
**上游压根没打算在 Windows 上用 ninja 生成器**。

#### P12 的三个子补丁（缺一不可）

| # | 位置 | 内容 | 为什么必须 |
|---|---|---|---|
| **P12b** | `configure.py` 写 `make_global_settings` | 值**剥掉两端引号** | gyp 会 `os.path.join(build_dir, value)` 再 `QuoteShellArgument`。带引号 → 得到 `..\..\"C:/…clang-cl.exe"`（畸形），且 `endswith("clang-cl")` 因 `.exe` 而**不成立** → `clang_cl` 仍为 None |
| **P12c** | `ninja.py:2287` | `endswith(("clang-cl","clang-cl.exe"))` | 同上：`.exe` 后缀让严格 `endswith("clang-cl")` 漏判 |
| **P12a/d** | `configure.py` `get_openssl_macros`/`_version` | clang-cl→`clang.exe --target=…-msvc` 做宏探针；防 `None[:2]` | clang-cl **静默忽略 `-dM`**（只发 warning），宏 dump 为空 → `openssl_version` 取不到 |

修后实测 `config.gypi`：

```json
"openssl_version": 811597887          // 0x3060003F = OpenSSL 3.6.3 release ✅
"make_global_settings": [ ["CC", "C:/…/clang-cl.exe"], ["CXX", "C:/…/clang-cl.exe"] ]
```

`out/Release/build.ninja` 头部实测：

```ninja
cl_x64 = "C:\…\Llvm\x64\bin\clang-cl.exe" -m64      ← 已从 cl.exe 切换 ✅
cl_x86 = "C:\…\Llvm\x64\bin\clang-cl.exe" -m32
cc  = C:/…/clang-cl.exe
cxx = C:/…/clang-cl.exe
ld  = link.exe                                       ← 链接仍走 MSVC link.exe（正确）
```

#### P13：gyp 自己的"预定义宏探测"也在 cl.exe/clang-cl 上踩坑

`tools/gyp/pylib/gyp/common.py:443-460`（`GetCompilerPredefines`）：

```python
stdout = subprocess.run(real_cmd, shell=True, capture_output=True, check=True).stdout
```

**两个 bug 叠加**：

1. `real_cmd` 已是 token 列表，`shell=True` 又把带空格的 exe 路径
   （`C:/Program Files/…`）**重新按空格拆开** → `status: 1`；
2. 即使路径没空格，clang-cl 也**忽略 `-dM`** → 返回 0 个宏。

实测（日志头两行）：

```
Warning: failed to get compiler predefines
cmd: ['C:/Program', 'Files/Microsoft', 'Visual', 'Studio/.../clang-cl.exe', '-dM', ...]
status: 1
```

**影响面**：`GetCompilerPredefines()` **只**被 `GetFlavor()` 用来判 Emscripten/WASI，
Windows 上纯属"白跑一趟"；但它的失败会污染配置日志、掩盖真问题。**P13** 顺手修掉：
`shell=False` + clang-cl→clang 探针。

#### 复测结论（后续所有 Windows 构建的前提）

> **Windows 上走 ninja 生成器时，必须让 gyp 用 clang-cl**（靠 P12 写
> `make_global_settings`），否则：(a) 生成的 DevTools 协议头**编译不过**（C2244，无解），
> (b) 与 triplet 名义（`-clang`）不符。**链接仍由 MSVC `link.exe` 完成，不需要改。**

### 11.7 ★ 库名对齐补充：vcpkg zlib 静态库在 Windows 上叫 `zs.lib`

这不是推测，是 vcpkg 官方 port 的**显式行为**（`ports/zlib/portfile.cmake`）：

```cmake
if(VCPKG_TARGET_IS_WINDOWS AND VCPKG_LIBRARY_LINKAGE STREQUAL "static")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/lib/pkgconfig/zlib.pc" " -lz" " -lzs")
endif()
```

即 **Windows + static → 库文件名固定为 `zs.lib`（debug 为 `zsd.lib`）**。
`--shared-zlib-libname` 必须写 `zs`，写 `zlib` 会 `LNK1104: 无法打开文件"zlib.lib"`。
（§11.2 的表格已含此项，此处补上**依据**。）

### 11.8 ★ P14：JS2C 生成的 C 标识符吃了 Windows 反斜杠

卡在第 7 步之后（`gen/node_javascript.cc`）：

```c
static const uint8_t deps\acorn\acorn_walk\dist\walk_raw[] = { ... };
```

`\a` `\u` `\w` 都是非法转义 → clang-cl 报
`error: redefinition of 'deps'`、`warning: \u used with no following hex digits`。

**根因**（`tools/js2c.cc`）：

```cpp
// GetFileId()  —— 前缀匹配写死成 POSIX 形式
constexpr std::string_view libPrefix  = "lib/";     // ← 收到的是 "lib\internal\..."
// GetVariableName()  —— 只替换了 . - /
if (result[i] == '.' || result[i] == '-' || result[i] == '/') result[i] = '_';
//                                                 ↑ 没有 '\\'
```

gyp 的 ninja 生成器传的是 **Windows 原生反斜杠路径**；MSBuild 生成器会归一成 `/`，
所以**上游 CI 走 MSBuild 时永远看不到这个问题** —— 又一个"路线 B 独有"的坑。

**修法**（P14，`tools/js2c.cc`）：

```cpp
std::string GetFileId(const std::string& filename) {
  std::string path = filename;
  for (char& c : path) if (c == '\\') c = '/';   // ← 先归一
  size_t end = path.size();                       // ... 下面全部改用 path
  ...
}

std::string GetVariableName(const std::string& id) {
  for (size_t i = 0; i < length; ++i)
    if (result[i] == '.' || result[i] == '-' || result[i] == '/' || result[i] == '\\')
      result[i] = '_';                            // ← 补上 '\\'
}
```

> **行为等价性**：POSIX 路径下 `GetFileId`/`GetVariableName` 的结果**逐字节不变**
> （`\` 从不出现）；Windows 下才生效。符合用户判据。

### 11.1 ★ P6 = 一个补丁拆成两半才正确（本轮实测教训）

`configure.py:1949` 在 `pkg_config()` 拿到 `--libs-only-L` 结果时，把它**加进了
`output['libraries']`**（而不是 `output['library_dirs']`）：

```python
elif pkg_libpath:
    output['libraries'] += [pkg_libpath]      # 形如 "-LC:/work/vcpkg/.../lib"
```

这条 `-L<dir>` 于是流进了 `libraries` 列表，而 `libraries` 在 Windows 上：
1. 先过 `msvs_emulation.AdjustLibraries()` → 被无条件拼上 `.lib`
   → `-LC:/work/vcpkg/.../lib.lib`（**P6a 修的**）；
2. 再过 ninja 的 rsp 写入器 → `-L` 被当作"缺省 `/` 前缀的选项"写成 `/LC:/...`
   → `link.exe` 报 `LNK4044: 无法识别的选项 "/LC:/..."` 并忽略，ICU 搜不到
   （**P6b 修的**）。

**关键结论：Windows 上所有链接都走 `@$binary.rsp`**（`rule link` / `link_embed` /
`solink` 的 `rspfile_content="$libs ..."`），所以 `$libs` 里**不能出现裸 `-L`**；
必须是 `/LIBPATH:`。因此 P6b 放在 `ninja.py` 构造 `libs` 处，把 `-L<dir>` 转成
`/LIBPATH:<dir>` 并**前置**（保证在它解释的库名之前）。

> 这条也解释了为什么只看 `node.ninja` 的 `libs` 行会误判"已修好"——
> 行文本里 `-L` 确实原样保留了，但它**注定要进 rsp**，所以那其实还是坏的。

### 11.2 ★ 库名对齐（实测逐条核对）

`--shared-<lib>-libname` 必须写 vcpkg 包里**真实的 .lib 文件名**（不带 `.lib`）：

| configure 选项 | 写对的值 | 易错点 |
|---|---|---|
| `--shared-zlib-libname` | `zs` | 不是 `z` / `zlib` |
| `--shared-brotli-libname` | `brotlidec,brotlienc` | **不是** `libbrotlidec,...`（vcpkg 去掉了 `lib` 前缀） |
| `--shared-openssl-libname` | `libcrypto,libssl` | 这个**有** `lib` 前缀 |
| `--shared-http-parser-libname` | `llhttp` | node 的选项叫 http-parser，实际库是 llhttp |
| `--shared-hdr-histogram-libname` | `hdr_histogram_static` | 有 `_static` 后缀 |
| `--shared-libuv-libname` | `libuv` | 有 `lib` 前缀 |
| 其余 | `cares` / `nghttp2` / `ngtcp2` / `zstd` / `simdjson` / `simdutf` / `sqlite3` / `ada` | 与包名一致 |

---

### 11.9 ★★ P16：torque 的类归属在 Windows 上整批丢失（`SourceId::Invalid()` 孤儿桶）

**症状**：`node.exe` 全量构建在 v8 `compiler.cc` 上炸出 13 个 `incomplete type`：
`SmiPair` / `SmiBox` / `InternalClass` / `SortState` / `ExportedSubClass*` /
`AbstractInternalClassSubclass*` / `InternalClassWithStructElements` /
`WasmFastApiCallData` / `WasmStringViewIter` / `StrongDescriptorArray`。

**误导性表象**：`gen/torque-generated/src/objects/torque-defined-classes-tq.inc`
**是 0 字节**（245 个 `-tq-inl.inc` 里 173 个为空），且强制重跑 torque 依然 RC=0 ——
torque "成功"地什么都没生成。

**根因**（`deps/v8/src/torque/`）：

1. `types.cc:1052-1059` `ClassType::AttributedToFile()`：所有**非 extern、非 `@export`**
   的 torque 类统一归属到一个虚拟文件 `src/objects/torque-defined-classes.tq`
   （v8 里绝大多数类是 `extern class`，只有 torque-defined-classes.tq 自身和
   test-torque.tq 里的"纯 torque 类"走这条路径）。
2. `source-positions.cc` 的 `GetSourceId()` 是**逐字节字符串匹配**。gyp/ninja 在
   Windows 上传给 torque 的文件参数是反斜杠（`src\objects\torque-defined-classes.tq`），
   而 `AttributedToFile()` 用**正斜杠**查找 → 匹配失败 → 返回 `SourceId::Invalid()`。
3. `GeneratedPerFile(Invalid())` 仍然开了一个"孤儿桶"，所有这些类的
   `TorqueGenerated*` 定义全部写进桶里；而 `GenerateImplementation()` 的写出循环
   遍历的是 `AllSources()`（合法 SourceId），孤儿桶**永远不被写出**。

**为什么 `ExportedSubClassBase` 能生成**：`@export` 类走
`return GetPosition().source;` 分支（按原文件归属），恰好绕开了坏掉的查找。

**修法（P16）**：`source-positions.cc` 的 `AddSource()` 存入前归一化 `\`→`/`，
`GetSourceId()` 匹配前同样归一化。POSIX 路径不受影响（本来就没有 `\`）。

**实测**：torque.exe 重编（1 个 CXX）→ 重跑 run_torque RC=0 →
`torque-defined-classes-tq.inc` 0 字节 → **64,144 字节**（28 个
`TorqueGenerated*` 类，含 `SmiPair`/`SortState`），`-tq-inl.inc` 0 → 38,274 字节。

**与 P14 同源**：JS2C（P14）、torque（P16）两个"文件名→标识符/查找"机制都在
Windows 反斜杠上栽跟头。这是路线 B 在 Windows 上的**第三类系统性问题**
（第一类=工具链引号/rsp 文本，第二类=C++20/PCH 标志丢弃）。

### 11.10 ★ P17：ninja 生成器把 GAS 语法的 `.S` 交给 MASM（结构必败）

**症状**：P16 解锁后又前进了 ~400 步，在 `v8_snapshot.embedded_asm.obj` 上炸出
上百个 `error A2008: syntax error`——mksnapshot 生成的 `embedded.S`（**GAS 语法**：
`.text`、`//` 注释、`.` 指令）被 **ml64.exe（MASM）** 汇编。

**根因**（`tools/gyp/pylib/gyp/generator/ninja.py:1223-1231`）：

```python
elif (
    self.flavor == "win"
    and ext in ("asm", "S")          # ← ".S" 和 ".asm" 混为一谈
    and not self.msvs_settings.HasExplicitAsmRules(spec)
):
    command = "asm"                   # → ml64.exe
```

- `.S` = GAS/unix 汇编（clang/gcc 体系）；`.asm` = MASM 语法（ml64）。两者语法
  不兼容，win 下把 `.S` 交给 ml64 **结构上永远失败**。
- 上游 node Windows 走 **MSBuild 生成器**从不踩它：MSBuild 项目里 `.S` 不进
  `ClCompile`，自然被忽略；而 win+clang 下的 `embedded.S` 本来就由
  `asm_to_inline_asm.py`（v8.gyp:508，`OS=="win" and clang==1` 条件）转换成
  `embedded.cc` 编译——`.S` 自身**不需要也不应该**被汇编。
- `HasExplicitAsmRules` 只查 `.asm` 扩展，`.S` 没有逃生门。

**修法（P17）**：把 `ext in ("asm", "S")` 收窄为 `ext == "asm"`。`.S` 落入
`# Ignore unhandled extensions` 兜底（与 MSBuild 行为一致）；MASM 语法的 `.asm`
（v8 的 `push_registers_masm.asm`）不受影响，实测 ninja 目标保留。

**同批实测**：gyp 重生成后 `embedded_asm` 目标消失（0 处），`embedded.cc` 编译目标
保留，构建继续推进。

## 12. 未决与下一步



### 12.1 simdutf 双份 COMDAT 仍未解决 ★

`--shared-simdutf` **只让 node 层链 vcpkg 的 8.2.0**，但 **v8.gyp 内部的 `simdutf`
目标仍然编内嵌的 6.4.0**：

```
tools/v8_gypfiles/v8.gyp:2423   'target_name': 'simdutf'
tools/v8_gypfiles/v8.gyp:2433   '<(V8_ROOT)/third_party/simdutf/simdutf.cpp'
```

→ 链接行里同时出现
`obj\tools\v8_gypfiles\simdutf.lib`（6.4.0）与 `simdutf.lib`（vcpkg 8.2.0），
两份符号**完全同名**且都是 `selection 2 (pick any)` 的 COMDAT
（如 `??_7implementation@haswell@simdutf@@6B@`）→ 链接器任意挑一份。

v8 的 3 个文件真的调用 simdutf（`builtins-typed-array.cc`、`objects/string.h`、
`strings/unicode-inl.h`），用的是 base64 / UTF 转换 API。**两个大版本差**下，
枚举值与结构布局有变化风险 → **不稳定行为**。

**可选方案**：

| 方案 | 做法 | 代价 |
|---|---|---|
| S1 | patch v8.gyp：删掉内部 `simdutf` 目标，让 v8 用 vcpkg 的头/库 | 需给 v8 的 target 加 include + libraries；改清单（可能改变 v8 的编译口径） |
| S2 | 保留 v8 内嵌，node 层也不链 vcpkg 的 simdutf | 退回"内嵌"，与 vcpkg 精神相悖 |
| S3 | 让 vcpkg 的 simdutf 保持 6.4.0（改 vcpkg port 版本） | 影响其他依赖 simdutf 的库，**不可取** |

→ 需专门实验决定（S1 最符合 vcpkg 精神，但要先确认 v8 的 simdutf 用法与 8.2.0 兼容）。

### 12.2 其它

- `--shared-nghttp3` 未打开（vcpkg 有 port 但本次未装）；打开后 QUIC 侧少一个内嵌库。
- `--shared-gtest` 无意义（node 不编测试）。
- **全量编译尚未跑完**：`ninja` 编译路径本身已验证可用（llhttp 目标 RC=0）；
  `node_base`（899 个文件）在修完 P2/P3 后继续推进中。
- **增量构建**：ninja 天然支持（改了源文件只重编它）。portfile 侧要保证
  `CURRENT_BUILDTREES_DIR` 在重复构建间复用（vcpkg 本身会清 buildtrees，
  需要时用 `VCPKG_KEEP_ENV_VARS` / 单独的工作目录策略）。

## 13. ★★ 依赖替换综合方案（node 直接依赖 + v8 内嵌第三方）

用户指令：node 的直接依赖和 v8 的第三方依赖都要综合评估，**尽量都用 vcpkg 上的**；
`ports/` 下允许为需要打补丁的 vcpkg 库新建独立 port 目录（允许 ≠ 必须）。

### 13.1 node 直接依赖：已 100% 走 vcpkg

实测（cfg12.bat）：**16 个可替换依赖全部已用 `--shared-*` 指向 vcpkg**，
`obj/deps/` 下不再编译任何 vendored 副本：

| 依赖 | vcpkg port | 状态 |
|---|---|---|
| openssl | openssl | ✅ 已替换 |
| zlib | zlib（静态库名 `zs.lib`，见 §11.7） | ✅ 已替换 |
| libuv | libuv | ✅ 已替换（P8 补回系统库） |
| c-ares | c-ares | ✅ 已替换（P8 补回系统库） |
| brotli | brotli | ✅ 已替换 |
| nghttp2 | nghttp2 | ✅ 已替换 |
| ngtcp2 | ngtcp2 | ✅ 已替换 |
| llhttp (http_parser) | llhttp | ✅ 已替换 |
| zstd | zstd | ✅ 已替换 |
| simdjson | simdjson | ✅ 已替换 |
| simdutf | simdutf | ✅ node 层已替换（v8 层未，见 13.2） |
| sqlite3 | sqlite3 | ✅ 已替换 |
| ada | ada-url | ✅ 已替换 |
| hdr-histogram | hdr-histogram | ✅ 已替换 |
| icu | icu (full) | ✅ 已替换 |
| undici/uvwasi 等 | 纯 JS / 无 gyp 编译 | 不适用 |

### 13.2 v8 内嵌第三方：按"是否真的参与编译"分类（实测 obj 产物）

对 `out/Release/obj/**/third_party/*.obj` 的实测统计：**只有 4 个库真正编译**——
abseil-cpp(110 obj)、zlib(17)、highway(7)、simdutf(1)。其余全部不参与 node 构建：

| 目录 | 性质 | 是否编译 | vcpkg 替换判断 |
|---|---|---|---|
| **zlib** (45 文件) | chromium 补丁版 zlib + google/compression_utils_portable | ✅ 17 obj（`v8_zlib` 目标，v8.gyp:2298） | **必须换**：与 node 的 vcpkg zlib **符号重复**（同一份符号两个实现）。v8 用的是 chromium fork（insert_string 优化 + compression_utils_portable）→ 方案见 13.3 |
| **abseil-cpp** (180 文件) | v8 src/ 里 10+ 处 `absl::`（mutex、condition-variable、cache、flat_hash_map 等） | ✅ 110 obj | **可换但性价比低**：vcpkg abseil 版本更新，v8 用法是稳定 API；但 110 obj 编译量不大、且 abseil 命名空间隔离好（`absl::`），与用户库**无符号冲突风险**（C++ namespace 天然隔离）。**建议：暂缓，列为后续项** |
| **highway** (80 文件) | SIMD 库，v8 wasm 用 | ✅ 7 obj | vcpkg 有 highway port。v8 用 `HWY_BROKEN_TARGETS` 等按架构定制 define，直接换 vcpkg 版会丢失这些口径 → **需 patch v8.gyp 目标转发到 vcpkg；性价比中等** |
| **simdutf** | v8.gyp:2423 内嵌 6.4.0 | ✅ 1 obj | **必须换**（即 §12.1 的双份 COMDAT 问题），方案 S1 |
| jinja2 / markupsafe / colorama | 构建期 Python 模板引擎（torque 用） | ✗（纯构建期） | **不适用** vcpkg（不是链接产物） |
| inspector_protocol / jsoncpp | 生成器模板 + 协议代码生成 | ✗（构建期生成） | 不适用 |
| googletest | v8 单测 | ✗（node 不编 v8 测试） | 不适用 |
| vtune / ittapi / perfetto | 性能分析（默认关闭） | ✗ | 不适用 |
| re2 | 目录已空（v8 已移除） | ✗ | 无 |
| glibc / valgrind / llvm-libc | 平台兼容头 | ✗ | 不适用 |
| siphash / rapidhash-v8 / utf8-decoder / fast_float / fp16 / wasm-api | 头文件库（fp16 是 include-only 目标） | ✗（或仅头文件） | 头文件库无符号冲突，**可保留** |

**结论**：v8 侧真正需要动手的是 **zlib、simdutf 两个**（符号重复/双份 COMDAT，
直接危害"与其他 vcpkg 库共存"）；highway、abseil 为第二梯队（无冲突，纯"精神"问题）。

### 13.3 v8_zlib 替换方案（新增，比 simdutf 更优先）

`v8_zlib`（v8.gyp:2298）编的是 **chromium fork 的 zlib**（含 `contrib/optimizations/`
和 `google/compression_utils_portable.cc`），与 node 层 vcpkg `zs.lib` **同名符号双份实现**
——这是比 simdutf 更隐蔽的重复（C 符号，无命名空间）。

- v8 用途：`src/snapshot` 压缩 + wasm，入口是 `compression_utils_portable.cc` 的
  `Compression` 工具函数（chromium 自有 API，不是 zlib API）。
- **方案 Z1（推荐）**：patch `v8_zlib` 目标——保留 `compression_utils_portable.cc`
  （单独编），其余 zlib 核心 .c 全部删除，链接改指 vcpkg `zs.lib`；
  `compression_utils_portable` 只调 zlib 公共 API，chromium 补丁（insert_string 优化）
  是性能优化，不影响行为。
- **方案 Z2**：保留内嵌（回退项）。chromium fork 与上游 zlib 有 ABI 差异风险较小，
  但 C 符号重复对静态链接是**实打实的 ODR 违规**。

### 13.4 `ports/` 多 port 策略判断

原则：**能不新建就不新建**。只有"必须改 vcpkg 库本身源码"时才值得新建 fork port。

| 需求 | 是否要新建 port | 结论 |
|---|---|---|
| node port 自己的 P1–P16 补丁 | 否 | 全部落在 node 源码树（gyp/configure/v8 源），属 node port 的 `patches/` |
| v8 用 vcpkg zlib/simdutf | 否 | 改的是 **node 的源码树**（v8.gyp 目标定义），不是 zlib/simdutf 库本身 |
| vcpkg zlib/simdutf 库本身要改？ | **否** | 当前方案不需要动这两个库的源码 |
| 若未来某库必须改库源码 | 是 | 届时新建 `ports/<lib>-node/`（copy port + patch），并显式 version-avoid 与上游冲突 |

**当前结论：`ports/` 下保持单一 `node/` 目录即可**，P16 等全部作为
`ports/node/patches/` 内的 patch 文件交付，无需为 zlib/simdutf 建 fork port。

### 13.5 实施顺序（下一步）

1. **P16 收尾**：node.exe 全量构建跑通（进行中，183/1629）。
2. **S1（simdutf）+ Z1（v8_zlib）**：patch v8.gyp 两个目标，复用现有构建做增量验证。
3. **highway / abseil**：第二梯队，列 TODO（不阻塞 port 正确性）。
4. 把 P1–P16 全部落成 `ports/node/patches/` 正式文件 + 新 `portfile.cmake`。

## 14. triplet 支持策略：分层支持模型（路径 3）

用户问题：triplet 走哪条路——(1) 对齐 node 默认（win clang / linux gcc / mac clang +
static MT，x64+arm64），其余封死报错；还是 (2) 保持现状，只实测 CI 默认路径，其余留给
高级用户。

### 14.1 两条路径的关键缺陷

**路径 1（封死）的核心矛盾**：CRT linkage 必须全图一致。vcpkg 最主流的默认 triplet
是 `x64-windows`（MSVC + **动态** CRT）；消费方项目一旦用它，node port 强制 static MT
就直接**无法共存**。封死静态 MT 之外的口径，等于把 node port 排除在最常见的消费场景
之外——这与"test 作为用户会怎么用"的目标自相矛盾。另外：vcpkg 生态里 triplet 是用户
主权，port 自造"triplet 白名单报错"会被社区抵制，且检测逻辑本身是维护负担。
还有个事实修正：node 上游 Windows 默认是 **MSVC** 而非 clang；"win clang" 是路线 B
的实测结论（P12/P15 系列只打通了 clang-cl），不是上游对齐。

**路径 2（只测默认）的缺陷**：对用户预期管理太弱。V8 的 Windows 编译对工具链高度
敏感（P12/P15 的经历就是证据），"其他路径理论上能过"其实没有把握，但用户无从知道
哪些测过、哪些没测——隐性知识。

### 14.2 推荐路径 3：分层支持模型

= 路径 2 的"不封死" + 结构性限制用 vcpkg 惯用机制守门 + 支持矩阵明示三档。

| 层 | 内容 | 机制 |
|---|---|---|
| **Tier 1（CI 保证）** | win: `x64-windows-static-clang`（clang-cl + 静态 CRT + 静态库，路线 B 实测口径）；linux: `x64-linux`（gcc，release）；mac: `arm64-osx`（clang，release） | CI 只跑这三个（现有 3 个 CI triplet 已就位，win 的 CI triplet 需从 MSVC 切到 clang） |
| **Tier 2（声明可过，不测）** | MSVC 口径、debug 构建、`x64-osx`、`arm64-linux`、动态 CRT 变体 | 不封死、不报错；README 矩阵标注"未实测" |
| **Tier 3（结构性不支持）** | 动态库交付、32 位、mingw、android/ios/freebsd | `vcpkg_check_linkage(ONLY_STATIC_LIBRARY)`（vcpkg 标准报错）+ `supports` 字段收紧 |

### 14.3 具体落地项

1. **`portfile.cmake` 加 `vcpkg_check_linkage(ONLY_STATIC_LIBRARY)`** —— node 的交付物
   是静态库，请求 `VCPKG_LIBRARY_LINKAGE=dynamic` 时由 vcpkg 给出标准报错。
   这是"封死"的唯一正确姿势：只封**结构性不可能**，不封"没测过"。
2. **CI triplet 切换**：`x64-windows-ci` 当前是 MSVC+动态 CRT+动态库（路线 A 遗产）。
   路线 B 落地后改为指向 clang-cl 静态口径（或直接改用 `x64-windows-static-clang`
   的 release-only 变体）；`x64-windows-static-clang` 里的 `VCPKG_BUILD_TYPE release`
   已经符合 CI 省盘需求。
3. **debug 不封死**：gyp 支持 debug；CI 保持 release-only（§ 已有决策）；README 说明
   V8 debug 构建体积/时长翻倍。
4. **CRT linkage 不封死**：静态/动态 CRT 都允许（依赖图一致即可用）；CI 只保
   static-clang 一档。P12/P15 是 clang-cl 特定补丁，MSVC+ninja 需单独验证后才可
   升 Tier 1——这正是"分层数据驱动升级"的好处。
5. **README 支持矩阵**：三档明示（实测保证 / 声明可过未实测 / 不支持），替代隐性知识。
6. **arm64 节奏**：arm64-osx 已在 CI；arm64-linux 与 arm64-windows 从 Tier 2 起步，
   等路线 B 在 x64 全绿后再升级（gyp 的 arm64 分支 expect 上游本来就是支持的）。

### 14.4 ★ 更正：win=clang-cl 就是 node 上游官方口径（vcbuild.bat 铁证）

**用户指正并经源码证实**：node 24 起 Windows **官方强制 ClangCL**，
`vcbuild.bat:281-287`：

```bat
@REM Forcing ClangCL usage for version 24 and above
set NODE_MAJOR_VERSION=
for /F "tokens=1 delims=." %%i in ("%NODE_VERSION%") do set "NODE_MAJOR_VERSION=%%i"
if %NODE_MAJOR_VERSION% GEQ 24 (
  echo ClangCL is required because the Node.js version being compiled is ^>= 24.
  set clang_cl=1
)
```

且随后 `set configure_flags=%configure_flags% --clang-cl=%clang_version%`
（`vcbuild.bat:394`）—— 与本实验 cfg12.bat 传的 `--clang-cl=19.1.5` **逐字一致**。

结论：
- §11.6 的"clang-cl 是路线 B 在 Windows 上的唯一正解"不仅是实验结论，
  **正是 node 上游的官方决定**（网上资料/部分文档仍说 MSVC，是误导）。
- §14.2 的 Tier 1 win 口径（clang-cl + 静态 CRT）因此**就是对齐 node**，
  "对齐上游"与"路线 B 正解"完全重合。
- MSVC 是 node ≤23 的遗产口径，自然落在 Tier 2。

### 14.5 debug 的定位：CI 实测是必做项（列入"暂时还没做"）

用户决定：debug 不封死且**必须 CI 实测**，但会撞 6 小时 CI 超时——发版前通过
**两次 push 配置不同**（一次 release 矩阵、一次 debug 矩阵）等方式绕过。
该事项与其它"欠账"统一记录在 `docs/暂时还没做.md`，发版前逐项清零。



---

## 15. 消费端验证升级（真跑 node 官方套件 + vcpkg 库共存）——2026-10-11

此前 test/ 只做"能不能链接 + 能不能跑一行 JS"的冒烟。本轮把它升级成真正的验证工程，
并借它做了一件之前只停留在文档里的事：**把 node 官方测试套件真跑一遍**。

### 15.1 ★ 官方套件可以被"别人的 node"驱动 —— 关键在 `tools/test.py --shell=`

- `tools/test.py`（node 官方用例驱动）自带 `--shell=<可执行>`：**用别人的 node 跑官方用例**。
  我们只要提供一个忠实的嵌入可执行即可。
- **为什么不能直接 `node --test`**：各套件目录下的 `*.status` 记录着上游标记的
  SKIP / FLAKY 用例，**只有 test.py 会读**。用内置 runner 会把这些状态全丢掉 ——
  于是满屏"失败"，而其中绝大多数是**上游本来就跳过**的环境相关用例。
  这种红没有信息量，会把真问题淹掉。这是"测试要先信得过，才谈得上发现问题"。
- 忠实度的两个具体点（照抄上游 `src/node_main.cc`）：
  1) argv 一字不改交给 `node::Start`；
  2) Windows 用 `wmain` 并把 argv 转 UTF-8 —— 不是 ANSI 代码页。很多用例会传
     非 ASCII 路径/参数，`main(char**)` 会按系统代码页解释而错乱。
- 套件**不由 port 源码目录提供**：port 加了 `test-suite` feature，把 `test/` 全量 +
  `tools/test.py`/`utils.py` 装到 `share/node/test-suite/`，消费端从安装产物取。
  依依赖方向仍然只有"消费端 → port"，也符合"port 目录自包含"。
  test.py 按 `dirname(sys.argv[0])/..` 推 workspace，所以 `tools/` 与 `test/` 必须同层。
- 分片：test.py 原生支持 `--run=<第几片>,<总片数>`。把它映射成多个 ctest 用例，
  交给 `ctest -j` 并行 —— 比在一个进程里靠 test.py 自己调度更好利用 runner 的核。
- 上游标为 flaky 的用例按 `--flaky-tests=dontcare` 处理：跑，但不拿它的失败点红灯。
  我们不是上游 CI，用默认的 `run` 会让已知不稳定用例反复点亮红灯。

### 15.2 ★★ clang-cl 不实现 MSVC 的 `/MP`，而 gtest 会在 `if(MSVC)` 下加它

- 现象（加 gtest 依赖后立刻暴露）：
  ```
  clang-cl: error: argument unused during compilation: '/MP' [-Werror,-Wunused-command-line-argument]
  ```
- 根因：gtest 的 CMake 里 `if(MSVC) add_compile_options(/MP)`。clang-cl 因为是
  MSVC 兼容前端，`MSVC` 变量为真 → 加了 `/MP`；而 clang-cl **不实现** `/MP`，
  把它报成"未使用的参数"；gtest 自己又开了 `/WX`（warnings as errors）→ 警告升级为错误。
- 修法（写在 **triplet** 里，对所有依赖 port 生效）：
  `-Wno-unused-command-line-argument`。
  用 `-Wno-`（彻底关掉）而不是 `-Wno-error=`：工程自己的 `/WX` 排在后面会把
  `-Wno-error=` 重新打开，而 `-Wno-` 关掉的警告不会被通用 `-Werror` 复活。
  只关这一条，不做"把 `/W4` 降成 `/W0`"那种大扫除 —— 那会把真问题一起盖掉。

### 15.3 ★ `VCPKG_C_FLAGS` / `VCPKG_CXX_FLAGS` 必须是空格分隔的**单个字符串**

- 我一开始写了 `list(APPEND VCPKG_CXX_FLAGS "-Wno-a")`，结果编译行里出现的是
  **一个**参数：
  ```
  -Wno-error=incompatible-pointer-types;-Wno-unused-command-line-argument
  ```
  分号没被拆开 → clang-cl 只认第一个，第二个报 "argument unused"。
- 正确写法是 `set(VCPKG_CXX_FLAGS "-Wno-a -Wno-b")`（空格在内）。这两个变量会被直接
  拼进编译命令行，vcpkg 不替你做列表展开。

### 15.4 共存是怎么被"证明"的（四层，互相独立）

1. **能链接**：`unit_node_coexist` 同时链 `node::node`（内含 V8 与 v8 内嵌的
   abseil / highway / v8_zlib）与同一批 vcpkg 库。重复的**强**符号会让链接器直接报错 ——
   链接成功本身就是证据。
2. **是同一份**：把 `node -p process.versions.X` 与我方进程里直接调用库得到的版本比对。
   `uv` / `zlib` / `brotli` 在 node 里是**运行期**取值（`uv_version_string()` /
   `zlibVersion()` / `BrotliEncoderVersion()`，见 `src/node_metadata.cc`），所以这条能
   证明"node 用的就是我们链的这份"；其余是编译期宏，比对它们证明**头文件**也是同一份
   （头不一致同样会踩 ABI）。另加一条行为级旁证：同输入同参数下，node 的
   `zlib.deflateSync` 与我们 `compress2` 的字节必须完全一致 —— 版本号相同但实现不同
   也能被它抓出来。
3. **行为对**：`coexist.js` 把 zlib / brotli / openssl / ICU / ada(IDN) / sqlite /
   llhttp / nghttp2 / libuv / V8 提供的 node 能力逐个真跑（h2c 不需要证书，正好用来
   验 nghttp2）。
4. **符号审计**：`tools/symbol_check.py` 扫 node 自带库与 vcpkg 库的**强符号**交集。
   链接成功 ≠ 没隐患 —— 同名 **COMDAT**（inline/template、同名第三方库的不同版本）
   会被静默折叠，运行时用哪一份由链接器决定。这个只能扫符号发现。
   新增 `--fail-on-duplicates` 让它能当闸门（默认仍是只报告）。

> 注意 `tools/symbol_check.py` 目前是 Windows/dumpbin 专用；Linux 的 `nm` 版本还没写
> （已记在 `docs/暂时还没做.md`）。ctest 里 `--dumpbin` 由 CMake 在**配置期**解析绝对
> 路径传进去 —— ctest 进程不在 vcvars 环境里，光靠 PATH 找不到。

### 15.5 ★★ vcpkg 2026.07.29 的脚本要求 **CMake 4.x**，而 portfile 的解释器就是 PATH 上的 cmake

- 现象（run #13 的 linux-arm job，4 秒就死）：
  ```
  CMake Error at scripts/cmake/z_vcpkg_spdx.cmake:15 (string):
    string sub-command JSON got an invalid mode 'STRING_ENCODE',
    expected one of GET, TYPE, MEMBER, LENGTH, REMOVE, SET, EQUAL.
  Call Stack: vcpkg_from_github.cmake:135 (z_vcpkg_add_spdx_resource) <- ports/zstd
  ```
- 根因：`string(JSON ... STRING_ENCODE)` 是 **CMake 4.x** 才有的子命令。实测：
  - CMake 3.31.6 → `invalid mode 'STRING_ENCODE'`（vcpkg 的脚本当场炸）
  - CMake 4.3.3 → `ok: "a"`
  而 **vcpkg 执行 `portfile.cmake` 用的就是 PATH 上的 cmake**（不是它给 port 构建下载的
  那份 `downloads/tools/cmake-4.4.0-*`）—— Windows runner 上 PATH 里的
  `C:/Program Files/CMake` 恰好是 4.4 所以能过；ubuntu / macos 镜像是 3.31 → 装依赖的
  第一个用 `vcpkg_from_github`/`vcpkg_download_distfile` 的 port（zstd）就挂。
- 而且这个路径**没有开关可以关**：`z_vcpkg_add_spdx_resource` 在 `vcpkg_from_github.cmake`
  与 `vcpkg_download_distfile.cmake` 里都是无条件调用的（我们自己的 portfile 也用后者）。
- 修法：CI 里**先钉一个 CMake 4.4.0**（按平台下 Kitware 的官方包、塞进 PATH），
  再断言主版本 ≥ 4 —— 报错要报在"CMake 版本不够"这一步，而不是藏在某个 port 的构建里。
- 教训：**"哪个 CMake 在跑 portfile"是一个必须显式管的依赖**，不能指望 runner 镜像的版本。
  镜像哪天从 4.4 退回 3.x，Windows 也会跟着挂。

### 15.6 arm64-windows 交叉构建：try_compile 不能运行 arm64 的 exe

- 现象（run #13 的 win-arm job，zstd 的编译器检查）：
  ```
  FAILED: [code=4294967295] cmTC_0ffd6.exe ... unknown error
  ```
  顺着看编译行，`--target=aarch64-pc-windows-msvc` 是对的（架构参数化生效），
  但 CMake 的 `try_compile` 默认会**运行**产出的可执行来验证 —— x64 宿主跑不了 arm64 的 exe。
- 修法（只加在 arm64-windows 这个**交叉** triplet 上）：
  `-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY`，让 try_compile 只编译不运行。
- 注意 `VCPKG_CMAKE_CONFIGURE_OPTIONS` 是用 `vcpkg_list` 展开的，所以多个 `-D` 用 `;` 分隔是
  安全的 —— **与 `VCPKG_C_FLAGS`/`VCPKG_CXX_FLAGS` 相反**（那两个必须是空格分隔的单个字符串，
  见 15.3）。
- 但这条**只是**让 zstd 之类的依赖能过；node 自己在交叉构建下还有更硬的障碍
  （构建期工具 mksnapshot/torque 必须在宿主上**运行**），见 `docs/暂时还没做.md` 第 2 项。
