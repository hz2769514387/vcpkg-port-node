# coexist 子项目：行为级共存验证。
#
# 两个用例，强度不同：
#   1) coexist-node-runtime（coexist.js）：只跑 node 那侧，把各库提供的 node 能力过一遍；
#   2) coexist-mutual-in-process（mutual_roundtrip + mutual.js）：**最硬的一层** ——
#      一个可执行里同时链 node::node 与这批"可能和 node 依赖重复/冲突"的 vcpkg 库，
#      然后让 C++ 侧与**同一个进程里的 node 运行时**互相消费对方的产物并各自复核。
#      （只有"双方真的在同一个进程里、用同一份库、数据来回走"才谈得上共存。）

add_test(NAME coexist-node-runtime
         COMMAND node_embed --experimental-sqlite "${CMAKE_CURRENT_SOURCE_DIR}/coexist.js")
set_tests_properties(coexist-node-runtime PROPERTIES
  LABELS "coexist"
  TIMEOUT 900
  PASS_REGULAR_EXPRESSION "COEXIST-OK")

find_package(ZLIB CONFIG REQUIRED)
find_package(OpenSSL REQUIRED)
find_package(unofficial-sqlite3 CONFIG REQUIRED)
find_package(simdjson CONFIG REQUIRED)
find_package(ada CONFIG REQUIRED)
find_package(ICU COMPONENTS uc i18n data REQUIRED)

add_executable(mutual_roundtrip mutual_roundtrip.cpp)
target_link_libraries(mutual_roundtrip PRIVATE
    node::node            # 内含 v8、vcpkg 的 abseil/highway，以及下面这些依赖
    ZLIB::ZLIB            # v8 内嵌 zlib 已并入这一份
    OpenSSL::Crypto OpenSSL::SSL
    unofficial::sqlite3::sqlite3
    simdjson::simdjson
    ada::ada              # node 的 URL 解析就用它（含 idna 数据）
    ICU::uc ICU::i18n ICU::data)
target_compile_features(mutual_roundtrip PRIVATE cxx_std_20)
if(WIN32 AND DEFINED node_NODE_SOURCE_MANIFEST AND EXISTS "${node_NODE_SOURCE_MANIFEST}")
  # 与 app/ 同样的原因：Windows 上目标必须嵌 node 的平台兼容性清单，否则一启动就退出码 216
  target_link_options(mutual_roundtrip PRIVATE
    "/MANIFEST:EMBED" "/MANIFESTINPUT:${node_NODE_SOURCE_MANIFEST}")
endif()
if(MSVC)
  target_compile_options(mutual_roundtrip PRIVATE /utf-8)
endif()

add_test(NAME coexist-mutual-in-process
         COMMAND mutual_roundtrip
                 "${CMAKE_CURRENT_SOURCE_DIR}/mutual.js"
                 "${CMAKE_CURRENT_BINARY_DIR}/mutual-work")
set_tests_properties(coexist-mutual-in-process PROPERTIES
  LABELS "coexist"
  TIMEOUT 900
  PASS_REGULAR_EXPRESSION "MUTUAL-OK")
