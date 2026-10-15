# 消费方示例 · 场景七（**vcpkg 侧**）：node 怎么进一个**有分层的工程**
#
# 前面的示例都围着"一个可执行 + node"转；这个示例回答更常见的工程形态：
# "我的工程有底层库、有多个可执行，node port 怎么接？"
#
# 形态（一次安装，两种接法并存，各自清楚）：
#
#   node_engine（消费方自己的 STATIC 库）
#       └─ PRIVATE 链 unofficial::node::node   ← node 全工程只在这里出现
#   layered_app（可执行）── 只链 node_engine，看不到 node 的任何痕迹
#   direct_cli （可执行）── 直接链 unofficial::node::node，并用 fmt
#
# 这条链路同时验掉三个真实疑问：
#   1) PRIVATE 链静态库，传递依赖（头文件、node 那一大串静态库、链接选项）
#      能不能到最终可执行？—— 链接成功 + 跑起来就是答案；
#   2) Windows 上"嵌平台兼容性清单"（不嵌就退出码 216 那个坑）：
#      静态库层带不过去，**每个最终可执行自己嵌** —— 本例两个都嵌了；
#   3) node 与另一个 vcpkg 库（fmt）在同一个目标里相安无事。
#
# 与相关示例的分工：那边证明"node 与**可能冲突的同名库**共存"
# （abseil/highway/simdutf/zlib 那批）；这边证明"node 进**分层工程结构**"。
# 本示例不依赖任何其它 example_/test_ 目录。
#
# ★ 不要在这里再 find_package(unofficial-node)：父项目（test/CMakeLists.txt）已经找过，
#   imported target 全工程可见 —— 再找一次会让 vcpkg 的 add_library 包装报
#   "cannot create imported target ... another target with the same name already exists"
#   （2026-10-14 本机实测）。example_coexist 等目录同样只继承、不重复找。
#   把这个目录单独拷走去用时，在最外层补一次 find_package(unofficial-node CONFIG REQUIRED) 即可。
find_package(fmt CONFIG REQUIRED)

# ---- 第一层：消费方自己的引擎静态库 -----------------------------------------
# node 只在这里出现一次，而且 PRIVATE：上层只看到 engine::RunScript。
add_library(node_engine STATIC engine/engine.cpp)
target_include_directories(node_engine PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/engine)
target_link_libraries(node_engine PRIVATE unofficial::node::node)
# C++20 由 unofficial::node::node 的 INTERFACE 声明（port 侧 cxx_std_20），这里不写。
if(MSVC)
  target_compile_options(node_engine PRIVATE /utf-8)  # 本层源码注释是中文
endif()

# ---- 第二层 A：只链引擎库的可执行 -------------------------------------------
add_executable(layered_app app/main.cpp)
target_link_libraries(layered_app PRIVATE node_engine)
if(MSVC)
  target_compile_options(layered_app PRIVATE /utf-8)
endif()
# Windows 的清单/栈/compiler-rt 由 unofficial::node::node 的 INTERFACE 自动带上

# ---- 第二层 B：直接链 node + fmt 的可执行 ------------------------------------
add_executable(direct_cli cli/main.cpp)
target_link_libraries(direct_cli PRIVATE unofficial::node::node fmt::fmt)
# C++20 由 unofficial::node::node 的 INTERFACE 声明（port 侧 cxx_std_20），这里不写。
if(MSVC)
  target_compile_options(direct_cli PRIVATE /utf-8)
endif()
# 同上：清单/栈/compiler-rt 由 node 的 INTERFACE 自动带上，这里什么都不写。

# ---- 示例自带的测试 ----------------------------------------------------------
# 两个目标跑同一个脚本（脚本不关心谁调的 node），断言各自拿到自己的标记。
add_test(NAME example-multitarget-layered-app
         COMMAND layered_app "${CMAKE_CURRENT_SOURCE_DIR}/demo_script.js" engine-app)
set_tests_properties(example-multitarget-layered-app PROPERTIES
  LABELS "example;example_multitarget"
  TIMEOUT 300
  PASS_REGULAR_EXPRESSION "MULTITARGET-OK engine-app")

add_test(NAME example-multitarget-direct-cli
         COMMAND direct_cli "${CMAKE_CURRENT_SOURCE_DIR}/demo_script.js" direct-cli)
set_tests_properties(example-multitarget-direct-cli PROPERTIES
  LABELS "example;example_multitarget"
  TIMEOUT 300
  PASS_REGULAR_EXPRESSION "MULTITARGET-OK direct-cli")
