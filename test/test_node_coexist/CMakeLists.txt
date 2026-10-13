# 本仓库的内部测试 · node port 本身的**一致性核对**
#
# 它验证的是"这个 port 有没有把依赖换对"：起一个 node 进程问它"你用的是哪一份依赖"，
# 再和 vcpkg 装出来的那份做交叉核对（编译期宏 vs 运行时报告）。
# 与 example_coexist 的分工：那边演示**消费方怎么用**（行为级共存），
# 这边是**本仓库**对端口自身的核对。两边互不依赖，删掉任何一边另一边照跑。
#
# ★ 用的 node 可执行文件是**端口自己装出来的**那份（`node_EXECUTABLE`，来自 tools feature），
#   不是示例 example_embed 的 node_embed ⇒ 那个示例删掉也不影响本测试。
if(NOT DEFINED node_EXECUTABLE OR NOT EXISTS "${node_EXECUTABLE}")
  message(WARNING
    "没有 node_EXECUTABLE（node port 的 tools feature 大概没开）⇒ 跳过 test-node-coexist。"
    "本测试要起一个 node 进程问它用的是哪份依赖；开 tools feature 即可。")
  return()
endif()

find_package(GTest CONFIG REQUIRED)
find_package(fmt CONFIG REQUIRED)

# nghttp2 没有 CMake 包配置（node 的消费配置里也是手工建的 imported target），自己找。
find_path(NGHTTP2_INCLUDE_DIR nghttp2/nghttp2.h REQUIRED)

add_executable(test_node_coexist test_node_coexist.cpp)

# ★ 只链 unofficial::node::node 本身、以及它**没有**覆盖到的东西 —— 绝不再重复列 node 已经提供的库。
#
# 为什么（这是 run #23 把 x64-linux 硬门弄红的原因，写下来防复发）：
#   node 的静态库与它依赖的 vcpkg 库由 node-config.cmake 组装成一条链接接口；
#   GNU 平台上是 CMake 的 $<LINK_GROUP:RESCAN,…>（落到链接器就是 --start-group/--end-group，
#   因为 GNU ld 单趟左到右、组内反复扫）。
#   CMake 会对链接项**去重**：这里若又显式列了组里的某个库，那次会被判成"同一份"，
#   于是**组内那份被删掉、只剩组外这份**；而组外的位置在 node 的静态库**之前**，
#   单趟扫描时它早就扫过去了 ⇒ 组内那个库的符号全部解析不了。
#   本文件原先正是这么写的 —— `node::nghttp2` 与 `"${NGHTTP2_LIBRARY}"` 是同一个
#   libnghttp2.a，各列了一遍，结果是 174 条 undefined reference 里 173 条是 nghttp2。
#
# 所以这里只留三样：
#   * GTest::gtest_main —— 测试框架；
#   * unofficial::node::node —— node 的整棵静态库（含 v8 与 uvwasi/merve/nbytes/…）
#                           **以及它自己的依赖**（nghttp2 / ICU / OpenSSL / zlib / brotli /
#                           sqlite3 / libuv / simdjson / simdutf / zstd / c-ares / ada / llhttp）；
#   * fmt::fmt           —— node 不用 fmt，所以它不在 node 的链接接口里（本测试要单独验它）。
# nghttp2 的**头文件**不在 unofficial::node::node 的 INTERFACE 里（node::nghttp2 是手工建的 imported
# target，只给了库、没给 INTERFACE_INCLUDE_DIRECTORIES），所以头单独给；
# **符号**（源码里要调 nghttp2_version()）照样由 unofficial::node::node 的链接接口提供。
target_link_libraries(test_node_coexist PRIVATE
    GTest::gtest_main
    unofficial::node::node
    fmt::fmt)
target_include_directories(test_node_coexist PRIVATE "${NGHTTP2_INCLUDE_DIR}")
target_compile_features(test_node_coexist PRIVATE cxx_std_20)

# 把"拿哪个 node 起进程"告诉 C++ 侧。
# ★ 走 file(GENERATE) 写成头文件，**不要**用 target_compile_definitions：
#   * 写成 `-DXXX="C:\...\node.exe"`（带转义引号）→ MSVC 的响应文件会把开头那个 \" 吃掉，
#     实际值少一个前引号，cmd 于是报"不是内部或外部命令"，现象像"node 跑不起来"（实测踩到过）；
#   * 干脆不写引号（-DXXX=C:/.../node.exe）→ 被 C++ 当 token 拆开，
#     报 `use of undeclared identifier 'C'` / 'work' / 'git' …（实测踩到过）。
#   写进头文件就没有响应文件那一层转义，字符串字面量原样落盘。
#   另外 file(GENERATE) 会展开生成器表达式，configure_file 不会。
file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/node_bin_path.h"
     CONTENT "#pragma once\n#define NODE_PORT_NODE_BIN \"${node_EXECUTABLE}\"\n")
target_include_directories(test_node_coexist PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
if(MSVC)
  target_compile_options(test_node_coexist PRIVATE /W0)
endif()

add_test(NAME test-node-coexist COMMAND test_node_coexist)
set_tests_properties(test-node-coexist PROPERTIES LABELS "internal;coexist" TIMEOUT 1800)
