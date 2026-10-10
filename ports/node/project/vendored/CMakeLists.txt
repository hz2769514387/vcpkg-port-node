# 依赖层：vcpkg 上没有、从 node 树里搬过来的五个库（`9.0-P-2`）。
#
# **本文件不抄任何源/宏/include 清单** —— 它们都在
# `cmake/gyp2vcpkg/generated/<目标>.cmake` 里，由 gyp2vcpkg 从 node 自己的
# `deps/*/*.gyp` 实测解析出来（`NODE_PORT_V8_<目标>_*`）。手抄一份就等于自己发明事实
# （用户原话 2026-10-08 10点11分 第 4 条："尽可能利用生成的（更准确）而非手写"）：
# 这一轮之前这几个库的源/宏/include 是**逐条照 gyp 抄的**，现在全部改成消费生成物
# —— 连"哪个文件算源、宏叫什么"都不需要人盯着了。
#
# 目标名沿用 node gyp 里那一套（nbytes / merve / crdtp / uvwasi / ncrypto /
# ncrypto_engine），不另发明前缀 —— 这些名字在 vcpkg 里都不存在，不会撞。
# **源文件一个字都不动**（`9.0-T-3` 的校验器证明）。
#
# 本文件只剩三件"gyp 说了不算"的事（都是我们自己的决策）：
#   1. 这些库在 fe 侧用**哪个 vcpkg 包**替掉（libuv / OpenSSL）；
#   2. `merve` 用 **V8 自带那份 simdutf**（`调研-12`/`踩坑-19`）；
#   3. 把 node 自带副本的 include 目录摘掉（`踩坑-31`，它们是链 vcpkg 那份的）。

set(NODE_PORT_DEPS "${NODE_ROOT}/deps")

find_package(libuv CONFIG REQUIRED)      # uvwasi 链 libuv（`调研-1`：用 vcpkg 的）
find_package(OpenSSL REQUIRED)           # ncrypto / ncrypto_engine 链 vcpkg 的 OpenSSL

# ---------------------------------------------------------------------------
# nbytes —— 蓝图是 deps/nbytes/nbytes.gyp（一个源文件）。
# ---------------------------------------------------------------------------
node_port_add_v8_target(nbytes)

# ---------------------------------------------------------------------------
# merve —— 蓝图是 deps/merve/merve.gyp（一个源文件，C++20）。
#
# gyp 的 include_dirs 里那一条 `../v8/third_party/simdutf` 是 node 把 simdutf 放在
# v8 里的那份 —— **必须用那一份**（`调研-12`：全工程只用 V8 自带的 6.4.0；vcpkg 的
# 8.2.0 API 不兼容，而且两份同命名空间会让 node 链接期 duplicate symbol
# —— 实测 lld-link: duplicate symbol: simdutf::BOM::check_bom …，见 `踩坑-19`）。
# 那份 include 目录由生成物给（清单里就是 `${NODE_PORT_V8_ROOT}/third_party/simdutf`）✓，
# 所以这里**不用再手写**。
# ---------------------------------------------------------------------------
node_port_add_v8_target(merve)

# ---------------------------------------------------------------------------
# crdtp —— 蓝图是 deps/inspector_protocol/inspector_protocol.gyp（九个 .cc，不含
# *_test.cc）。include_dirs 是 ['.']，所以源码里写 `#include "crdtp/json.h"`。
# ---------------------------------------------------------------------------
node_port_add_v8_target(crdtp)

# ---------------------------------------------------------------------------
# uvwasi —— 蓝图是 deps/uvwasi/uvwasi.gyp（九个 .c）。
# `cflags: -fvisibility=hidden` 与 Linux 的 `_POSIX_C_SOURCE=200112` 都在生成物里 ✓；
# 只剩"链 vcpkg 的 libuv"这一条是我们自己的决定。
# ---------------------------------------------------------------------------
node_port_add_v8_target(uvwasi)
node_port_uv_lib(_node_uv)
target_link_libraries(uvwasi PUBLIC ${_node_uv})

# ---------------------------------------------------------------------------
# ncrypto —— 蓝图是 deps/ncrypto/ncrypto.gyp，走的是
#   `openssl_is_boringssl=="false" and openssl_version >= 0x3000000f` 那一支
#   （我们用的是 vcpkg 的 OpenSSL 3.6.3，不是 BoringSSL）。
#
# 那一支一共**两个 target**（ncrypto / ncrypto_engine）。gyp 把 NCRYPTO_* 那几个
# 宏（`NCRYPTO_BSSL_LIBDECREPIT_MISSING=1` / `OPENSSL_API_COMPAT=30000` /
# `OPENSSL_NO_DEPRECATED` / `NCRYPTO_ENGINE_COMPAT=1` …）放在 direct_dependent_settings
# 里，生成物已经按 PUBLIC 语义把它们放在 `_DEFINES` 上 ✓；这里只补"链 vcpkg 的 OpenSSL"。
# ---------------------------------------------------------------------------
node_port_add_v8_target(ncrypto_engine)
target_link_libraries(ncrypto_engine PUBLIC OpenSSL::Crypto OpenSSL::SSL)

node_port_add_v8_target(ncrypto)
target_link_libraries(ncrypto PUBLIC OpenSSL::Crypto OpenSSL::SSL)
# `ncrypto` 在 gyp 里依赖 `ncrypto_engine`（生成物的 `_DEPS` 里就有它），
# 但**链接方向要照 gyp 的语义**：`ncrypto` 只是编译期需要 engine 的头/宏 —— 见下。
target_link_libraries(ncrypto PRIVATE ncrypto_engine)

# ---------------------------------------------------------------------------
# 两个收尾（都只跟"我们链的是 vcpkg 那份"有关）：
#
#   1. **摘掉 node 自带副本的 include**（`踩坑-31`）：ncrypto 的生成清单里带着
#      `${NODE_ROOT}/deps/openssl/openssl/include`，而它链的 OpenSSL 是 vcpkg 的
#      —— 头用自带的、库用 vcpkg 的会**运行期堆损坏**（`fe -e` 那次就是这么炸的）。
#      名单与理由见 `cmake/gyp2vcpkg/consume.cmake` 的 `NODE_PORT_BUNDLED_INCLUDE_DROP`。
#   2. 这几个库**有 gyp 清单**，所以**不再打 `node_port_patch_own_target`**：编译选项一律
#      从清单来（`9.0-T-9` 的"编译配置从 gyp 拿"这才算真的落到了它们头上）。
# ---------------------------------------------------------------------------
foreach(_t nbytes merve crdtp uvwasi ncrypto ncrypto_engine)
  node_port_drop_bundled_include(${_t} ${NODE_PORT_BUNDLED_INCLUDE_DROP})
endforeach()
