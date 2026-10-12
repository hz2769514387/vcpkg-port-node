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
# vcpkg 平台 toolchain：设 CMAKE_MSVC_RUNTIME_LIBRARY（/MT vs /MD）、CMAKE_CXX_FLAGS 等。
# 当本文件被设为 VCPKG_CHAINLOAD_TOOLCHAIN_FILE 时，它会**替换** vcpkg 的默认平台
# toolchain（scripts/toolchains/windows.cmake），导致 CRT 标志从不被设上——
# 所有依赖 port 都会用 /MD 编，最终链接 node（/MT）时报 LNK2038 RuntimeLibrary 不匹配。
# 这里显式 include 它来补回。
# ---------------------------------------------------------------------------
if(DEFINED _VCPKG_ROOT_DIR AND EXISTS "${_VCPKG_ROOT_DIR}/scripts/toolchains/windows.cmake")
    include("${_VCPKG_ROOT_DIR}/scripts/toolchains/windows.cmake")
elseif(DEFINED Z_VCPKG_ROOT_DIR AND EXISTS "${Z_VCPKG_ROOT_DIR}/scripts/toolchains/windows.cmake")
    include("${Z_VCPKG_ROOT_DIR}/scripts/toolchains/windows.cmake")
endif()
# windows.cmake 设 CMAKE_RC_FLAGS="/c65001 /DWIN32"，但 cmcldeps 会把 RC 标志传给
# clang-cl 做依赖追踪——clang-cl 不认 /c65001（那是 rc.exe 的 UTF-8 代码页开关）。
# 去掉 /c65001，rc.exe 用系统代码页即可（资源文件都是 ASCII）。
if(DEFINED CMAKE_RC_FLAGS)
    string(REPLACE "/c65001 " "" CMAKE_RC_FLAGS "${CMAKE_RC_FLAGS}")
    set(CMAKE_RC_FLAGS "${CMAKE_RC_FLAGS}" CACHE STRING "" FORCE)
endif()

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
# 不覆盖 CMAKE_RC_COMPILER：windows.cmake 设的 CMAKE_RC_FLAGS（/c65001）是给 rc.exe 的，
# llvm-rc 走 cmake_llvm_rc 时会把 RC 标志传给 clang-cl，而 clang-cl 不认 /c65001。
# msvc-command-line-env.cmake 已把 Windows SDK 的 rc.exe 放进 PATH。

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

# ---------------------------------------------------------------------------
# arm64 交叉编译：把 --target 塞进 CC/CXX 环境变量
#
# vcpkg_configure_make 对 autotools 端口（如 icu）会把 CFLAGS 里的 --target=
# 移到 CPPFLAGS（z_vcpkg_configure_make_process_flags 的"Filter common CPPFLAGS"段）。
# 但部分 configure 脚本的 link test 不带 $CPPFLAGS，于是 --target 丢了，
# clang-cl 退回宿主默认的 x86_64，编出 x64 目标文件 →
#   lld-link: error: …\conftest-….obj: machine type x64 conflicts with arm64
# 而 autotools 只会把它读成 "error: C compiler cannot create executables"。
#
# 这里直接设 ENV{CC}/ENV{CXX}：vcpkg_configure_make 的
# z_vcpkg_append_to_configure_environment 在 Windows 上会优先用 ENV{CC}
# 而不是默认的 VCPKG_DETECTED_CMAKE_C_COMPILER。这样 --target 就不经过
# CFLAGS/CPPFLAGS 过滤，始终跟着编译器走。
# 只对非默认架构（arm64）做：x64 是 clang-cl 的宿主默认，不需要。
# ---------------------------------------------------------------------------
if(NOT _node_port_target_arch STREQUAL "x86_64")
  set(ENV{CC} "${CMAKE_C_COMPILER} --target=${_node_port_compiler_target}")
  set(ENV{CXX} "${CMAKE_CXX_COMPILER} --target=${_node_port_compiler_target}")
  message(VERBOSE "node-port: arm64 交叉编译，CC/CXX 已注入 --target=${_node_port_compiler_target}")
endif()

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
