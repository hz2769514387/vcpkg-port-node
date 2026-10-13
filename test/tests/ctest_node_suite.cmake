# 把 node 官方测试套件注册成 ctest 用例。
#
# 为什么用官方 tools/test.py，而不是 `node --test`：
#   各套件目录下的 *.status 记录着上游自己标记的 SKIP / FLAKY 用例，**只有 test.py 会读**。
#   直接 `node --test` 会把这些状态全丢掉 —— 于是满屏"失败"，其中绝大多数是上游本来
#   就跳过或不稳定的环境相关用例。那种红没有信息量，会把真问题淹掉。
#
# test.py 的 `--shell=<可执行>` 就是"用别人的 node 跑官方用例"的官方入口，
# 我们的 node_embed 正是为它准备的（同一份 argv 语义 + Windows 上 wmain/UTF-8）：
#   它按 dirname(sys.argv[0])/.. 推 workspace，所以 tools/ 与 test/ 必须同层。
#
# ★ 默认口径 = 上游的 `make jstest`：**一个 test.py 进程**，把要跑的套件全列上，
#   并行度交给 test.py 自己的 `-j`（Makefile:322 `tools/test.py … $(PARALLEL_ARGS) $(JS_SUITES)`）。
#   为什么不能拆成多个并发进程（run #21 的教训）：
#     * test/common/tmpdir.js 用 `.tmp.${TEST_SERIAL_ID||TEST_THREAD_ID}` 命名临时目录，
#       而这两个 id 都是**每个 test.py 进程内部**从 0 起算的 ⇒ 两个并发 test.py 会撞同一个
#       `.tmp.1`，于是 snapshot-warning / report-* 这类用例互相把对方的临时目录删掉
#       （EPERM / unlink ENOENT，run #21 里 3 个失败）。
#     * sequential/ 下的用例是"独占机器"写的（固定端口等），4 片并发跑就是
#       `bind EADDRINUSE :::12346`（run #21 的 sequential-shard3）。
#   想分片也可以（NODE_PORT_TEST_SHARDS>0，仍按 suite×分片注册成多进程），但那时
#   每个进程必须有自己的 --temp-dir，下面已经按用例名生成，避免再踩同一个坑。

if(NOT NODE_PORT_TEST_NODE_SUITE)
  message(STATUS "node 官方套件：已关闭（-DNODE_PORT_TEST_NODE_SUITE=OFF）")
  return()
endif()

if(NOT node_TEST_SUITE_DIR)
  message(WARNING
    "找不到 node 官方套件目录。请给 node 依赖打开 test-suite feature"
    "（见 test/vcpkg.json 里 node 的 features），本次不注册官方套件用例。")
  return()
endif()

if(NOT Python3_Interpreter_FOUND)
  message(WARNING
    "找不到 python3。node 官方套件要靠 tools/test.py 驱动，本次不注册官方套件用例。")
  return()
endif()

set(_node_suite_runner "${node_TEST_SUITE_DIR}/tools/test.py")
set(_node_suite_testroot "${node_TEST_SUITE_DIR}/test")
if(NOT EXISTS "${_node_suite_runner}" OR NOT IS_DIRECTORY "${_node_suite_testroot}")
  message(WARNING "套件目录不完整，跳过：${node_TEST_SUITE_DIR}")
  return()
endif()

# ---------------------------------------------------------------------------
# 红线：套件里"在源码树里就带执行位"的 fixture 脚本，装出来必须还是可执行的。
#
# 为什么值得单独立一条（run #29 的教训）：CMake 的 `file(INSTALL)` **默认按 0644**
# 落盘（文档里"默认 USE_SOURCE_PERMISSIONS"那句只适用 file(COPY)），源码树里的执行位
# 会被悄悄抹掉。而 node 官方套件的 `test/fixtures/run-script/node_modules/.bin/*`
# 正是靠执行位工作的：`node --run <script>` 让 shell 去执行它们，掉位之后
# **子进程 stdout 为空、真正的报错进 child.stderr（用例不打印）**，
# 于是 test-node-run 的 6 个子用例全红，而日志里完全看不出是权限问题。
# Windows 不受影响（走 `.bat`），所以这个坑只在 Linux/macOS 的 CI 上现形。
# 断言点放在这里：配置期就红，不用等二十多分钟的官方套件跑完。
# ---------------------------------------------------------------------------
if(UNIX)
  file(GLOB _node_suite_fixture_bins
       "${_node_suite_testroot}/fixtures/run-script/node_modules/.bin/*")
  foreach(_node_suite_fixture IN LISTS _node_suite_fixture_bins)
    if(_node_suite_fixture MATCHES "\\.bat$")
      continue()
    endif()
    execute_process(COMMAND test -x "${_node_suite_fixture}" RESULT_VARIABLE _node_suite_x)
    if(NOT _node_suite_x EQUAL 0)
      message(FATAL_ERROR
        "套件 fixture 脚本丢了执行位：${_node_suite_fixture}\n"
        "node 官方套件会拿它当命令执行（node --run …），掉位会让 test-node-run 整片假红。\n"
        "处置：ports/node/portfile.cmake 里装 test-suite 的 file(INSTALL) 必须带"
        " USE_SOURCE_PERMISSIONS（file(INSTALL) 的默认是 0644，不是源码权限）。")
    endif()
  endforeach()
  unset(_node_suite_fixture_bins)
endif()

# test.py 的通用参数
set(_node_suite_args
    "${_node_suite_runner}"
    "--shell=$<TARGET_FILE:node_embed>"
    "--test-root=${_node_suite_testroot}"
    "--time"
    # 被上游标成 flaky 的用例：跑，但失败不计入结果。我们不是上游 CI，
    # 用默认的 run 会让已知不稳定用例反复把红点亮，把真问题淹掉。
    "--flaky-tests=${NODE_PORT_TEST_FLAKY_MODE}")
if(NODE_PORT_TEST_JOBS)
  list(APPEND _node_suite_args "-j" "${NODE_PORT_TEST_JOBS}")
endif()

# ★ Windows 上 `-j` 默认压到 2（写在 test/CMakePresets.json 的两个 windows preset 里）。
#
# 为什么：run #32 判读时发现 Windows 两档各有 2~5 条用例以 **0xC0000409** 静默退出
# （零输出、非 crash 非 timeout），本机复现后拿到 V8 自己打印的那一行：
#     [low_level_alloc.cc : 554] RAW: Check new_pages != nullptr failed: VirtualAlloc failed
# 那个文件是 **V8 自带的 abseil**，失败点是
#     VirtualAlloc(nullptr, new_pages_size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE)
# 即 **提交量（commit charge）耗尽**，不是内存踩踏。
#
# 于是"为什么只有 Windows、为什么每轮换一批用例"全都对上了：
#   * Linux/macOS 默认 overcommit ⇒ 提交失败几乎不会发生；
#   * Windows 的提交量是**硬限制**（RAM + 页面对换文件），4 个并发 node 进程
#     （V8 每个进程的老生代上限按机器内存自动放大到 GB 级）叠起来就可能摸到上限，
#     于是"谁是那一刻最倒霉的那个进程"就崩 —— 所以失败集合逐轮变化；
#   * macOS 那一档本来就跑 -j 2，从来没出过这个码。
# 压到 2 之后峰值提交量大约减半（约 5~9 GB，16 GB 的 runner 有足够余量）。
# 代价：套件墙钟时间约翻倍（x64-windows 实测 8:42 → 15 分钟量级），远小于 job 超时。
#
# 这不是"把失败藏起来"：crash 码、根因与缓解依据都记在这里，且 -j 只影响**并行度**，
# 用例一条都不少跑、一条都不跳过。
if(NODE_PORT_TEST_NODE_ARGS)
# 典型用法（CI 的 Windows 档）：--report-on-fatalerror,--report-directory=$RUNNER_TEMP/crash-reports
# —— 上游 test.py 只在 crash/timeout 时才打印退出码，而"零输出 + 非零退出"的静默 fast-fail
# 既没有输出也没有崩溃点；带上它至少能落一份 <report.*.json>（含 message 与 nativeStack）。
if(NODE_PORT_TEST_NODE_ARGS)
  list(APPEND _node_suite_args "--node-args=${NODE_PORT_TEST_NODE_ARGS}")
endif()
# ---------------------------------------------------------------------------
# 「应当跳过」清单 = 文件（单一来源 + 平台过滤 + 强制写理由） + 使用者额外给的
#
# 见 test/cmake/node-suite-skips.txt 顶部：为什么要有这个文件、以及加条目之前要过的判据。
# 这里做三件事：
#   1) 按当前平台筛选（all / windows / linux / macos）；
#   2) **理由为空就 FATAL_ERROR** —— 空的跳过等于把 bug 藏起来，宁可在配置期红；
#   3) 跟 NODE_PORT_TEST_SKIP（使用者用 -D 或 preset 额外加的）合并去重。
# ---------------------------------------------------------------------------
string(TOLOWER "${CMAKE_SYSTEM_NAME}" _node_suite_os)
if(_node_suite_os STREQUAL "darwin")
  set(_node_suite_os "macos")
endif()

set(_node_suite_skips "")
set(_node_suite_skip_file "${CMAKE_SOURCE_DIR}/cmake/node-suite-skips.txt")
if(EXISTS "${_node_suite_skip_file}")
  # ★ 用 file(READ) 再按行切，**不要**用 file(STRINGS)：后者是按**空白符**取词、
  #   不是按行 —— 实测会把 "# node 官方套件…" 切成 "# node "、"" 之类的碎片，
  #   理由里的空格也会把一行拆开，于是"三段式"检查全线误报。
  file(READ "${_node_suite_skip_file}" _node_suite_skip_text)
  string(REPLACE "\r\n" "\n" _node_suite_skip_text "${_node_suite_skip_text}")
  string(REPLACE "\n" ";" _node_suite_skip_lines "${_node_suite_skip_text}")
  unset(_node_suite_skip_text)
  foreach(_node_suite_line IN LISTS _node_suite_skip_lines)
    string(STRIP "${_node_suite_line}" _node_suite_line)
    if(_node_suite_line STREQUAL "" OR _node_suite_line MATCHES "^#")
      continue()
    endif()
    # 分隔符用 `|` 而不是逗号/分号：分号是 CMake 的列表分隔符、逗号是生成器表达式的，
    # 理由里出现它们会立刻把解析搞坏。
    string(REPLACE "|" ";" _node_suite_fields "${_node_suite_line}")
    list(LENGTH _node_suite_fields _node_suite_field_count)
    if(NOT _node_suite_field_count EQUAL 3)
      message(FATAL_ERROR
        "node-suite-skips.txt 这一行不是「用例名 | 平台 | 理由」三段：\n  ${_node_suite_line}")
    endif()
    list(GET _node_suite_fields 0 _node_suite_name)
    list(GET _node_suite_fields 1 _node_suite_plat)
    list(GET _node_suite_fields 2 _node_suite_why)
    string(STRIP "${_node_suite_name}" _node_suite_name)
    string(STRIP "${_node_suite_plat}" _node_suite_plat)
    string(STRIP "${_node_suite_why}" _node_suite_why)
    if(_node_suite_why STREQUAL "")
      message(FATAL_ERROR
        "node-suite-skips.txt 里这条跳过没写理由：${_node_suite_name}"
        "（欠账 §5b 的规矩：只放环境相关的，且理由必须写清楚）")
    endif()
    if(_node_suite_plat STREQUAL "all" OR _node_suite_plat STREQUAL "${_node_suite_os}")
      list(APPEND _node_suite_skips "${_node_suite_name}")
    endif()
  endforeach()
  unset(_node_suite_line)
  unset(_node_suite_fields)
  unset(_node_suite_field_count)
else()
  message(WARNING
    "找不到跳过清单 ${_node_suite_skip_file}：本轮不做任何额外跳过"
    "（上游 *.status 的 SKIP 仍然生效）")
endif()

if(NODE_PORT_TEST_SKIP)
  # ★ 先按逗号拆开再合并。这个变量是**逗号分隔的列表**（test.py --skip-tests 的口径，
  #   也是 preset / -D 传进来的形态）。整串塞进 list 会变成**一个**元素：
  #   既和清单文件里的同名条目重复，又去不掉 —— 实测日志里同名条目出现过两遍，
  #   而且构建目录里 cache 残留的旧值会把已经撤销的跳过悄悄带回来。
  string(REPLACE "," ";" _node_suite_extra_skips "${NODE_PORT_TEST_SKIP}")
  list(APPEND _node_suite_skips ${_node_suite_extra_skips})
  unset(_node_suite_extra_skips)
endif()

if(_node_suite_skips)
  list(REMOVE_DUPLICATES _node_suite_skips)
  list(JOIN _node_suite_skips "," _node_suite_skips_joined)
  list(APPEND _node_suite_args "--skip-tests=${_node_suite_skips_joined}")
  message(STATUS "node 官方套件额外跳过（${_node_suite_os}）：${_node_suite_skips_joined}")
else()
  message(STATUS "node 官方套件没有额外跳过（${_node_suite_os}）")
endif()

string(REPLACE "," ";" _node_suite_list "${NODE_PORT_TEST_SUITES}")
if(NOT _node_suite_list)
  # 空 = 用 test.py 的默认集合（它会自己排除 addons/internet/node-api 等非 JS 套件）
  set(_node_suite_list "default")
endif()

# 临时根（NODE_TEST_DIR）：**必须又短、又"离家近"** —— 两个方向同时受限。
#
# 套件里有一批用例要 `listen()`/`bind()` 一个 UNIX domain socket，而 sun_path 的可用
# 字节数只有 108（Linux，含结尾 NUL）/ 104（macOS）⇒ 可用 107 / 103。两种算法各受一侧限制：
#
#   ① **绝对侧**：`tmpdir.resolve()` 给的是绝对路径（tmpdir.js 先 realpathSync(NODE_TEST_DIR)）
#      ⇒ `<临时根>/.tmp.<id>/copy_%<n>/<pid>.sock`
#      （copy_%N 来自 test/common/fs.js 的 nextdir()，尾部实测 29 字符）
#      用例：test-fs-cp-async-socket / test-fs-cp-sync-copy-socket-error
#   ② **相对侧**：`common.PIPE = path.relative(process.cwd(), tmpdir.path) + '/node-test.<pid>.sock-…'`
#      （test/common/index.js:257）cwd = **套件根**（我们的 WORKING_DIRECTORY）⇒ 相对路径前面
#      会带上"从 cwd 上溯到公共祖先"的若干层 `../`，每层 3 字符；尾部 = 20 + 追加名（最长实测 33）
#      用例：test-net-* 一族 5 条（listen-path / listen-handle / boundsocket / connect-options-*）
#
# ★ 两个方向是**互相拉扯**的，run #29/#30 各踩了一头：
#   * 放构建目录下但名字长（`node-suite-tmp/node-suite`，CI 上 93 字符）：① 直接超（fs-cp 两条红）；
#   * 改放系统临时目录（run #30 我改的）：① 舒服了，但两侧同时炸 ——
#     - Linux/macOS：② 变成 **13 层 `../`（39 字符）** ⇒ test-net-* 一族 5 条挂 `listen EINVAL`
#       （macOS 还多出一批 http-unix-socket / cluster / permission-fs）；
#     - Windows：CI 的 %TEMP% 是 **8.3 短名** `C:\Users\RUNNER~1\AppData\Local\Temp`
#       ⇒ 一堆做路径比对/看目录的用例整片红：test-fs-realpath、test-fs-promises、
#       test-fs-watch*、test-fs-promises-watch*（RUNNER~1 vs runneradmin、`h2\bar` vs `bar`），
#       x64-windows 与 arm64-windows 各 30~40 条。
#   所以基目录取**构建目录**（它与 cwd 同在一棵树里，② 的 `../` 只有几层），名字取短名 `ns`，
#   单用例时**连子目录都不套**（一个字符也要省）。按这套布局算出来的实际值：
#     Linux CI 绝对侧 98 / 相对侧 80（上限 107）；macOS CI 99 / 80（上限 103，余量最薄）；
#     本机 Windows 87 / 80（Windows 走命名管道，不查这一项）。
#   要换地方：-DNODE_PORT_TEST_TMPBASE=<目录>（但换了要重算这两个数，红线会替你把关）。
if(NODE_PORT_TEST_TMPBASE)
  set(_node_suite_tmpbase "${NODE_PORT_TEST_TMPBASE}")
else()
  set(_node_suite_tmpbase "${CMAKE_CURRENT_BINARY_DIR}")
endif()
file(TO_CMAKE_PATH "${_node_suite_tmpbase}" _node_suite_tmpbase)
# ★ Windows 上**不能**用带 8.3 短名的目录（典型就是 %TEMP% = C:\Users\RUNNER~1\AppData\Local\Temp）。
#   run #30 实测：临时根落到短名目录后，一批做路径比对 / 看目录的用例整片红
#   （test-fs-realpath 报 RUNNER~1 vs runneradmin、test-fs-watch 报 `h2\bar` vs `bar`、
#    加 test-fs-promises / test-fs-promises-watch* … 两档 Windows 各 30~40 条）。
#   判据用 `~` 是因为 8.3 短名长这样；正常情况下路径里不会有它。
if(WIN32 AND _node_suite_tmpbase MATCHES "~")
  message(FATAL_ERROR
    "套件临时根的基目录里出现了 8.3 短名（`~`）：\n"
    "  ${_node_suite_tmpbase}\n"
    "Windows 上这会带坏一批做路径比对的官方用例（run #30 实测 30~40 条，见本文件上面那段）。\n"
    "处置：不要用 %TEMP%（CI 上它是 C:\\Users\\RUNNER~1\\…），改用 -DNODE_PORT_TEST_TMPBASE=<不含 ~ 的短目录>。")
endif()
set(_node_suite_tmproot "${_node_suite_tmpbase}/ns")
file(MAKE_DIRECTORY "${_node_suite_tmproot}")

if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  set(_node_suite_socket_max 103)   # sun_path[104]
else()
  set(_node_suite_socket_max 107)   # sun_path[108]
endif()

# 把上面那张"数字表"变成构建期断言：两侧都算出来，超了就当场红（附上算式与处置办法）。
# 只在 UNIX 上查 —— Windows 走命名管道（`\\.\pipe\…`）且这族用例本来就 skip。
function(_node_suite_assert_socket_budget _dir)
  if(NOT UNIX)
    return()
  endif()
  get_filename_component(_dir "${_dir}" ABSOLUTE)
  string(LENGTH "${_dir}" _abs_len)
  math(EXPR _abs "${_abs_len} + 10 + 8 + 11")      # /.tmp.<id> + /copy_%<n> + /<pid>.sock
  # cwd 是内核给的规范路径（真跑时 process.cwd() 会把符号链接解掉），所以两边都 REALPATH 后再比。
  get_filename_component(_node_suite_dir_real "${node_TEST_SUITE_DIR}" REALPATH)
  file(RELATIVE_PATH _rel "${_node_suite_dir_real}" "${_dir}")
  # ★ 别用 while + `string(REGEX REPLACE "^\\.\\./" …)` 去数层数：CMake 的 REGEX REPLACE
  #   在一次调用里会把**所有**能匹配的 `../` 都吃掉（`^` 会跟着扫描位置往后走，实测
  #   `../../../../../ns` 被一次性变成 `ns`，层数误算成 1）。用 MATCHALL 精确计数。
  string(REGEX MATCHALL "\\.\\./" _node_suite_ups "${_rel}")
  list(LENGTH _node_suite_ups _up)
  string(REGEX REPLACE "^(\\.\\./)+" "" _rest "${_rel}")
  unset(_node_suite_ups)
  string(LENGTH "${_rest}" _rest_len)
  # 相对侧 = `../`×层数 + 相对部分 + `/.tmp.<id>`(10) + `/node-test.<pid>.sock`(20) + 追加名(33)
  math(EXPR _net "3 * ${_up} + ${_rest_len} + 10 + 20 + 33")
  message(STATUS "  套件临时目录 ${_dir}")
  message(STATUS "    socket 路径预算：绝对侧 ${_abs} / 相对侧 ${_net}（上限 ${_node_suite_socket_max}）")
  if(_abs GREATER _node_suite_socket_max OR _net GREATER _node_suite_socket_max)
    message(FATAL_ERROR
      "套件的临时目录会让 socket 路径超长（上限 ${_node_suite_socket_max}）：\n"
      "  ${_dir}\n"
      "  绝对侧 ${_abs}（sun_path 只放得下 ${_node_suite_socket_max} 字节）；"
      "相对侧 ${_net}（common.PIPE 会从 cwd 起算，cwd 之上 ${_up} 层 ../）。\n"
      "后果：test-fs-cp-*-socket 一族挂 `listen EINVAL`、test-net-* 一族挂 `bind EINVAL`，"
      "而且报错里看不出真因（run #29/#30 实测）。\n"
      "处置：把构建目录挪浅一点，或用 -DNODE_PORT_TEST_TMPBASE=<短目录> 指一个既短、"
      "又和套件根同一棵树（少几层 ..）的地方。")
  endif()
endfunction()

# _node_suite_register(<用例名> <label 后缀> <test.py 的位置参数…>)
function(_node_suite_register _name _label _tmpname)
  # 临时子目录名**故意取短名**（见上面那段预算说明）：注册序号 `t0`/`t1`/…。
  # 用序号而不用 "<套件>-shard<N>"：分片时两个套件的 shard0 会撞同一个目录。
  # 目录名只进 NODE_TEST_DIR，判读时看下面那条 STATUS（用例名 → 临时目录）就够了。
  # 单用例时**不套子目录**（每个字符都算进 socket 预算）：只有一个 test.py 进程、
  # 而且 RUN_SERIAL，隔离没有意义；分片时才需要 t0/t1/… 各一份。
  if(_tmpname STREQUAL "")
    set(_node_suite_tmpdir "${_node_suite_tmproot}")
  else()
    set(_node_suite_tmpdir "${_node_suite_tmproot}/${_tmpname}")
  endif()
  _node_suite_assert_socket_budget("${_node_suite_tmpdir}")
  message(STATUS "  用例 ${_name} → 临时目录 ${_tmpname}")
  add_test(NAME "${_name}"
           COMMAND ${Python3_EXECUTABLE} ${_node_suite_args}
                   "--temp-dir=${_node_suite_tmpdir}"
                   ${ARGN})
  set_tests_properties("${_name}" PROPERTIES
    LABELS "node-suite;node-suite-${_label}"
    TIMEOUT ${NODE_PORT_TEST_SUITE_TIMEOUT}
    WORKING_DIRECTORY "${node_TEST_SUITE_DIR}"
    # node 官方套件的 test/common/index.js 会检查"有没有冒出它不认识的全局"
    # （Unexpected global(s) found）。宿主环境里任何 NODE_OPTIONS=--require 的
    # 预载（本机就是 WorkBuddy 注入的 node-language-shim.cjs）都会往每个 node
    # 进程里塞 __CODEBUDDY_NODE_* 全局，一跑就红 257 个 —— 全是环境问题，
    # 不是库的问题（实测：直接跑同一个用例，清掉 NODE_OPTIONS 就过）。
    # 所以这里把 NODE_OPTIONS 清空，套件进程不继承宿主的任何预载。
    ENVIRONMENT "NODE_OPTIONS=")
endfunction()

set(_node_suite_count 0)
if(NODE_PORT_TEST_SHARDS)
  foreach(_suite IN LISTS _node_suite_list)
    math(EXPR _shard_last "${NODE_PORT_TEST_SHARDS} - 1")
    foreach(_shard RANGE 0 ${_shard_last})
      set(_node_suite_name "node-suite-${_suite}-shard${_shard}")
      _node_suite_register("${_node_suite_name}" "${_suite}" "t${_node_suite_count}"
                           "--run=${_shard},${NODE_PORT_TEST_SHARDS}" "${_suite}")
      # sequential/ 是"独占机器"写的（固定端口）：分片并发会在同一台机上互相抢端口，
      # 所以这一组让 ctest 一次只跑一个（RUN_SERIAL：不与其他任何用例并发）。
      if(_suite STREQUAL "sequential")
        set_tests_properties("${_node_suite_name}" PROPERTIES RUN_SERIAL TRUE)
      endif()
      math(EXPR _node_suite_count "${_node_suite_count} + 1")
    endforeach()
  endforeach()
else()
  # 上游 make jstest 的口径：一个进程，套件按位置参数一次全给。
  _node_suite_register("node-suite" "all" "" ${_node_suite_list})
  # 这个用例内部已经 -j 起满并行，再和别的用例抢机器只会引入端口/临时目录噪音。
  set_tests_properties("node-suite" PROPERTIES RUN_SERIAL TRUE)
  set(_node_suite_count 1)
endif()

message(STATUS "node 官方套件：注册了 ${_node_suite_count} 个 ctest 用例"
               "（套件：${NODE_PORT_TEST_SUITES}；分片：'${NODE_PORT_TEST_SHARDS}'）")
message(STATUS "  driver : ${_node_suite_runner}")
message(STATUS "  shell  : $<TARGET_FILE:node_embed>")
message(STATUS "  临时根 : ${_node_suite_tmproot}")
