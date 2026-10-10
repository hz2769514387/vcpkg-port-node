# Toolchain：clang-cl（MSVC 兼容驱动），目标 x86_64 / arm64-pc-windows-msvc。
#
# 两处都用它：本工程自己的代码，以及 vcpkg port 的 chainload toolchain ——
# 于是最终链接里的每个目标文件都是 clang 产的（工程约定第 2 条：三平台一律 clang）。
#
# 注意：vcpkg 是在子进程里读这个文件的，所以它需要的一切都必须只从这个文件推得出来，
# 外层 shell 里 export 的变量不一定能活到这里。搜索位置不对时用 NODE_PORT_LLVM_ROOT 覆盖。

# 顺带把 nmake 与 INCLUDE/LIB 安排好，并发布 NODE_PORT_VS_INSTALL_ROOT。
# 这里 include 一次、triplet 里还要 include 一次：不走 CMake 的 port（openssl 的 nmake 构建）
# 永远不会加载本文件，只见得到 triplet。
include("${CMAKE_CURRENT_LIST_DIR}/msvc-command-line-env.cmake")

# ---------------------------------------------------------------------------
# 找 clang-cl
# ---------------------------------------------------------------------------
set(_node_port_llvm_candidates "")

if(DEFINED ENV{NODE_PORT_LLVM_ROOT} AND NOT "$ENV{NODE_PORT_LLVM_ROOT}" STREQUAL "")
  list(APPEND _node_port_llvm_candidates "$ENV{NODE_PORT_LLVM_ROOT}")
endif()
if(DEFINED ENV{LLVM_ROOT} AND NOT "$ENV{LLVM_ROOT}" STREQUAL "")
  list(APPEND _node_port_llvm_candidates "$ENV{LLVM_ROOT}")
endif()
if(NOT NODE_PORT_VS_INSTALL_ROOT STREQUAL "")
  # VS 自带一份匹配的 LLVM —— 这是本机的常见情况。
  list(APPEND _node_port_llvm_candidates "${NODE_PORT_VS_INSTALL_ROOT}/VC/Tools/Llvm")
endif()
if(DEFINED ENV{ProgramFiles} AND NOT "$ENV{ProgramFiles}" STREQUAL "")
  file(GLOB _node_port_vs_llvm "$ENV{ProgramFiles}/Microsoft Visual Studio/*/*/VC/Tools/Llvm")
  list(APPEND _node_port_llvm_candidates ${_node_port_vs_llvm})
  unset(_node_port_vs_llvm)
  list(APPEND _node_port_llvm_candidates "$ENV{ProgramFiles}/LLVM")
endif()
# 独立 LLVM 发行版。写死是因为 ProgramFiles 可能没定义，而安装器本来就装在这里。
list(APPEND _node_port_llvm_candidates
  "C:/Program Files/LLVM"
  "C:/Program Files (x86)/LLVM")

set(NODE_PORT_LLVM_ROOT "" CACHE PATH "提供 clang-cl 的 LLVM 安装根目录")
foreach(_node_port_candidate ${_node_port_llvm_candidates})
  if(EXISTS "${_node_port_candidate}/x64/bin/clang-cl.exe")
    set(NODE_PORT_LLVM_ROOT "${_node_port_candidate}")
    break()
  elseif(EXISTS "${_node_port_candidate}/bin/clang-cl.exe")
    set(NODE_PORT_LLVM_ROOT "${_node_port_candidate}")
    break()
  endif()
endforeach()
unset(_node_port_llvm_candidates)
unset(_node_port_candidate)

if(NODE_PORT_LLVM_ROOT STREQUAL "")
  message(FATAL_ERROR
    "找不到 clang-cl。装 Visual Studio 的「C++ Clang 编译器」组件，"
    "或者把 NODE_PORT_LLVM_ROOT 指向 LLVM 安装根目录（含 bin/clang-cl.exe 或 x64/bin/clang-cl.exe 的那一层）。"
    "注意：只装「Clang 工具」是只有 clang-format/clang-tidy 的，没有 clang-cl。")
endif()

if(EXISTS "${NODE_PORT_LLVM_ROOT}/x64/bin/clang-cl.exe")
  set(NODE_PORT_LLVM_BIN "${NODE_PORT_LLVM_ROOT}/x64/bin")
else()
  set(NODE_PORT_LLVM_BIN "${NODE_PORT_LLVM_ROOT}/bin")
endif()

set(CMAKE_C_COMPILER "${NODE_PORT_LLVM_BIN}/clang-cl.exe" CACHE FILEPATH "" FORCE)
set(CMAKE_CXX_COMPILER "${NODE_PORT_LLVM_BIN}/clang-cl.exe" CACHE FILEPATH "" FORCE)
if(EXISTS "${NODE_PORT_LLVM_BIN}/lld-link.exe")
  set(CMAKE_LINKER "${NODE_PORT_LLVM_BIN}/lld-link.exe" CACHE FILEPATH "" FORCE)
endif()
if(EXISTS "${NODE_PORT_LLVM_BIN}/llvm-rc.exe")
  set(CMAKE_RC_COMPILER "${NODE_PORT_LLVM_BIN}/llvm-rc.exe" CACHE FILEPATH "" FORCE)
endif()
if(EXISTS "${NODE_PORT_LLVM_BIN}/llvm-mt.exe")
  set(CMAKE_MT "${NODE_PORT_LLVM_BIN}/llvm-mt.exe" CACHE FILEPATH "" FORCE)
endif()

# ---------------------------------------------------------------------------
# 目标架构（arm64 也留好代码路径，只是没有机器实测）
# ---------------------------------------------------------------------------
set(_node_port_target_arch "x86_64")
if(DEFINED VCPKG_TARGET_ARCHITECTURE)
  if(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
    set(_node_port_target_arch "aarch64")
  elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "x86")
    set(_node_port_target_arch "i686")
  endif()
endif()
set(_node_port_compiler_target "${_node_port_target_arch}-pc-windows-msvc")

# ---------------------------------------------------------------------------
# 编译器身份
#
# 告诉 CMake 这是"MSVC 前端的 clang"，让它按 cl.exe 的约定办事（响应文件、/FLAG 语法、MSVC ABI），
# 而不是 gcc 的约定。这里是**声明**而不是探测：本文件会在 CMake 还没做编译器探测的上下文里被加载。
# ---------------------------------------------------------------------------
set(CMAKE_C_COMPILER_ID "Clang")
set(CMAKE_CXX_COMPILER_ID "Clang")
set(CMAKE_C_COMPILER_FRONTEND_VARIANT "MSVC")
set(CMAKE_CXX_COMPILER_FRONTEND_VARIANT "MSVC")
set(CMAKE_C_COMPILER_TARGET "${_node_port_compiler_target}" CACHE STRING "" FORCE)
set(CMAKE_CXX_COMPILER_TARGET "${_node_port_compiler_target}" CACHE STRING "" FORCE)

# CRT 口径**由 triplet 决定，这里不写死**：vcpkg 的 windows toolchain 会按
# VCPKG_CRT_LINKAGE 设好 CMAKE_MSVC_RUNTIME_LIBRARY（static → /MT，dynamic → /MD）。
# 本文件作为 chainload toolchain 在 vcpkg 之后加载，若在此 FORCE 覆盖，就会让
# "CRT 跟随三元组"失效 —— 所以这里只负责编译器，不碰 CRT。

# ---------------------------------------------------------------------------
# compiler-rt 内建库（`9.0-P-5`，踩坑-20）
#
# CMake 对 MSVC 前端的链接规则是**直接调 lld-link**（rules.ninja 里
# `vs_link_exe ... -- lld-link.exe /nologo @$RSP_FILE`），绕过了 clang-cl 驱动 ——
# 于是 clang 驱动本来会自动加上去的 compiler-rt 内建库就没了。症状是链接期
#   undefined symbol: __cpu_model
# （clang 编出来的 zlib / brotli / ada 用 `__builtin_cpu_supports` 时引用它；
# 官方 node 用 MSVC 编，没有这条依赖，所以这不是"照抄漏了"，是换编译器的代价。）
#
# 这里只**探路径**；挂到目标上是顶层 CMakeLists 的事（此时还没有任何目标）。
# `--print-libgcc-file-name` 在 clang-cl 上返回字面量 "libgcc.a" 没法用，
# 用 `--print-resource-dir` 再拼，资源目录布局是 clang 的既定事实。
# ---------------------------------------------------------------------------
# 下载模式（--only-downloads）下 vcpkg 会把 execute_process 换成直接报错的版本，
# 而那个模式不构建任何东西 —— 所以跳过这次探测。
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows" AND NOT DEFINED VCPKG_DOWNLOAD_MODE)
  execute_process(
    COMMAND "${NODE_PORT_LLVM_BIN}/clang-cl.exe" --print-resource-dir
    OUTPUT_VARIABLE _node_port_clang_resource_dir
    ERROR_QUIET
    OUTPUT_STRIP_TRAILING_WHITESPACE)

  # compiler-rt 的架构后缀与 clang 的 target arch 不是一套写法。
  if(_node_port_target_arch STREQUAL "x86_64")
    set(_node_port_rt_arch "x86_64")
  elseif(_node_port_target_arch STREQUAL "aarch64")
    set(_node_port_rt_arch "aarch64")
  elseif(_node_port_target_arch STREQUAL "i686")
    set(_node_port_rt_arch "i386")
  else()
    set(_node_port_rt_arch "${_node_port_target_arch}")
  endif()

  file(TO_CMAKE_PATH "${_node_port_clang_resource_dir}" _node_port_clang_resource_dir)
  set(NODE_PORT_CLANG_RT_BUILTINS
      "${_node_port_clang_resource_dir}/lib/windows/clang_rt.builtins-${_node_port_rt_arch}.lib"
      CACHE FILEPATH "clang 的 compiler-rt 内建库（lld-link 直链时不会自动带上）")
  unset(_node_port_clang_resource_dir)
  unset(_node_port_rt_arch)
endif()
