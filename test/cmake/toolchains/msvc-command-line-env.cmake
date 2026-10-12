# MSVC 命令行环境：nmake 在 PATH 上，INCLUDE / LIB 指向 CRT 与 Windows SDK。
#
# 为什么单独一个文件、而不是并进 clang-cl.cmake：
#
# **不是每个 vcpkg port 都走 CMake**。openssl 用 nmake 构建（node 也用 nmake 构建它），
# vcpkg 的 nmake 支路一进来就 `find_program(NMAKE nmake REQUIRED)`，而它的 makefile 要
# 通过 INCLUDE/LIB 找到 <inttypes.h>。**不走 vcpkg_configure_cmake 的 port 根本不会加载
# chainload 的 toolchain 文件** —— 只加载 triplet。所以只写在 clang-cl.cmake 里的东西，
# 恰恰对最需要它的那些 port 不可见。于是这个模块被两处都 include。
#
# 它防的故障很难查：一路 configure 成功、别的 port 都过，最后 openssl 挂了；
# 而且它只在**没有 vcpkg 二进制缓存**的机器上出现（缓存命中时 openssl 直接还原归档，压根不跑 nmake）。
#
# 开发者命令提示符里这三样本来就齐；那种情况下这里只补 nmake，不动已有的 INCLUDE/LIB。

if(_NODE_PORT_MSVC_CMD_ENV_INCLUDED)
  return()
endif()
set(_NODE_PORT_MSVC_CMD_ENV_INCLUDED TRUE)

# vcpkg 的**下载模式**（`vcpkg install --only-downloads`）会把 `execute_process` 整个换成
# 一个直接 FATAL_ERROR 的版本（见 vcpkg 自己的 scripts/cmake/execute_process.cmake：
# `if (DEFINED VCPKG_DOWNLOAD_MODE)`）。那个模式下不构建任何东西，也就不需要 INCLUDE/LIB 与 nmake。
#
# 所以这里直接返回。不返回的话，`--only-downloads` 会在**加载 triplet 的那一刻**就死，
# 报错是 "This command cannot be executed in Download Mode." —— 读起来像 vcpkg 的问题，
# 其实是"在下载模式里做了只有构建模式才该做的事"。
if(DEFINED VCPKG_DOWNLOAD_MODE)
  return()
endif()

function(_node_port_env_prepend _name _value)
  if(_value STREQUAL "" OR NOT EXISTS "${_value}")
    return()
  endif()
  set(_current "$ENV{${_name}}")
  string(FIND "${_current}" "${_value}" _node_port_found)
  if(NOT _node_port_found EQUAL -1)
    return()
  endif()
  if(_current STREQUAL "")
    set(ENV{${_name}} "${_value}")
  else()
    set(ENV{${_name}} "${_value};${_current}")
  endif()
endfunction()

# 读环境变量。
#
# `$ENV{ProgramFiles(x86)}` 看着合理、其实不可用：那个 ")" 会提前结束变量引用，
# 在 CMP0053 的 NEW 规则下是**语法错误**而不是警告。而这个目录不是可选的
# （Windows SDK 与 vswhere 都在它下面），所以改成解析 `cmake -E environment` 的输出。
# 按行前缀匹配，因为变量名里有正则元字符。
function(_node_port_env_value _name _out)
  set(${_out} "" PARENT_SCOPE)
  execute_process(COMMAND "${CMAKE_COMMAND}" -E environment
    OUTPUT_VARIABLE _node_port_env_text
    ERROR_QUIET
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(_node_port_env_text STREQUAL "")
    return()
  endif()
  string(REPLACE "\n" ";" _node_port_lines "${_node_port_env_text}")
  string(LENGTH "${_name}=" _node_port_prefix_len)
  foreach(_node_port_line IN LISTS _node_port_lines)
    string(SUBSTRING "${_node_port_line}" 0 ${_node_port_prefix_len} _node_port_prefix)
    if(_node_port_prefix STREQUAL "${_name}=")
      string(SUBSTRING "${_node_port_line}" ${_node_port_prefix_len} -1 _node_port_value)
      string(STRIP "${_node_port_value}" _node_port_value)
      set(${_out} "${_node_port_value}" PARENT_SCOPE)
      return()
    endif()
  endforeach()
endfunction()

_node_port_env_value("ProgramFiles(x86)" _node_port_pf_x86)

# --- Visual Studio ----------------------------------------------------------
# vswhere 是官方答案，也是唯一在"VS 不在 C 盘 / 不是 2022"时仍然正确的办法。
set(_node_port_vs_root "")
if(DEFINED ENV{VCPKG_VISUAL_STUDIO_PATH} AND NOT "$ENV{VCPKG_VISUAL_STUDIO_PATH}" STREQUAL "")
  set(_node_port_vs_root "$ENV{VCPKG_VISUAL_STUDIO_PATH}")
endif()

if(_node_port_vs_root STREQUAL "" AND NOT _node_port_pf_x86 STREQUAL "")
  find_program(_node_port_vswhere vswhere
    HINTS "${_node_port_pf_x86}/Microsoft Visual Studio/Installer"
    NO_CACHE)
  if(_node_port_vswhere)
    execute_process(COMMAND "${_node_port_vswhere}" -latest -products *
      -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64
      -property installationPath
      OUTPUT_VARIABLE _node_port_vswhere_out
      ERROR_QUIET
      OUTPUT_STRIP_TRAILING_WHITESPACE)
    string(REPLACE "\n" ";" _node_port_vswhere_lines "${_node_port_vswhere_out}")
    if(_node_port_vswhere_lines)
      list(GET _node_port_vswhere_lines 0 _node_port_vs_root)
    endif()
  endif()
  unset(_node_port_vswhere)
  unset(_node_port_vswhere_out)
  unset(_node_port_vswhere_lines)
endif()

# vswhere 与环境变量都报原生路径（反斜杠），而 file(GLOB) **不认反斜杠** ——
# MSVC 目录会静默变空，最后只有 SDK 那一半 INCLUDE/LIB 被设上。
if(NOT _node_port_vs_root STREQUAL "")
  file(TO_CMAKE_PATH "${_node_port_vs_root}" _node_port_vs_root)
endif()

# 给 clang-cl.cmake 用：它要从同一个安装里取 VC/Tools/Llvm。
set(NODE_PORT_VS_INSTALL_ROOT "${_node_port_vs_root}")

# --- MSVC -------------------------------------------------------------------
set(_node_port_msvc_root "")
if(NOT _node_port_vs_root STREQUAL "")
  file(GLOB _node_port_msvc_versions "${_node_port_vs_root}/VC/Tools/MSVC/*")
  if(_node_port_msvc_versions)
    list(SORT _node_port_msvc_versions)
    list(REVERSE _node_port_msvc_versions)
    list(GET _node_port_msvc_versions 0 _node_port_msvc_root)
  endif()
  unset(_node_port_msvc_versions)
endif()

# 目标架构决定 lib 目录（arm64 也要能走通 —— 无机器实测不等于不支持）。
# 宿主工具目录恒为 Hostx64（我们只在 x64 宿主上构建）。
set(_node_port_msvc_arch "x64")
if(DEFINED VCPKG_TARGET_ARCHITECTURE AND NOT VCPKG_TARGET_ARCHITECTURE STREQUAL "")
  if(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
    set(_node_port_msvc_arch "arm64")
  elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "x86")
    set(_node_port_msvc_arch "x86")
  elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm")
    set(_node_port_msvc_arch "arm")
  endif()
endif()

if(NOT _node_port_msvc_root STREQUAL "")
  _node_port_env_prepend(PATH "${_node_port_msvc_root}/bin/Hostx64/x64")
  _node_port_env_prepend(INCLUDE "${_node_port_msvc_root}/include")
  _node_port_env_prepend(LIB "${_node_port_msvc_root}/lib/${_node_port_msvc_arch}")
endif()

# --- Windows SDK ------------------------------------------------------------
set(_node_port_kits_root "")
if(DEFINED ENV{WindowsSdkDir} AND NOT "$ENV{WindowsSdkDir}" STREQUAL "")
  set(_node_port_kits_root "$ENV{WindowsSdkDir}")
elseif(NOT _node_port_pf_x86 STREQUAL "")
  file(TO_CMAKE_PATH "${_node_port_pf_x86}" _node_port_pf_x86_cmake)
  set(_node_port_kits_root "${_node_port_pf_x86_cmake}/Windows Kits/10")
  unset(_node_port_pf_x86_cmake)
endif()
if(_node_port_kits_root STREQUAL "")
  set(_node_port_kits_root "C:/Program Files (x86)/Windows Kits/10")
endif()
unset(_node_port_pf_x86)

set(_node_port_sdk_version "")
if(EXISTS "${_node_port_kits_root}/Include")
  file(GLOB _node_port_sdk_versions RELATIVE "${_node_port_kits_root}/Include" "${_node_port_kits_root}/Include/*")
  if(_node_port_sdk_versions)
    list(SORT _node_port_sdk_versions)
    list(REVERSE _node_port_sdk_versions)
    list(GET _node_port_sdk_versions 0 _node_port_sdk_version)
  endif()
  unset(_node_port_sdk_versions)
endif()

if(NOT _node_port_sdk_version STREQUAL "")
  foreach(_node_port_part ucrt um shared winrt)
    _node_port_env_prepend(INCLUDE "${_node_port_kits_root}/Include/${_node_port_sdk_version}/${_node_port_part}")
  endforeach()
  foreach(_node_port_part ucrt um)
    _node_port_env_prepend(LIB "${_node_port_kits_root}/Lib/${_node_port_sdk_version}/${_node_port_part}/${_node_port_msvc_arch}")
  endforeach()
  # SDK bin 目录放的是 rc.exe / mt.exe / signtool.exe 等**宿主工具**：按 vcvars
  # 的规矩用**宿主**架构挑目录（x64_arm64 交叉时是 x64）。用目标架构会把
  # ARM64 的 rc.exe 放上 PATH —— 那种可执行文件在 x64 宿主上根本起不来
  # （CreateProcess: not a valid Win32 application），CMake try-compile 在
  # vs_link_exe 的 RC 阶段报 "unknown error"。
  set(_node_port_sdk_bin_arch "x64")
  if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(ARM64|arm64|aarch64)$")
    set(_node_port_sdk_bin_arch "arm64")
  elseif(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(x86|i386|i686)$")
    set(_node_port_sdk_bin_arch "x86")
  endif()
  if(NOT EXISTS "${_node_port_kits_root}/bin/${_node_port_sdk_version}/${_node_port_sdk_bin_arch}/rc.exe")
    set(_node_port_sdk_bin_arch "${_node_port_msvc_arch}")
  endif()
  _node_port_env_prepend(PATH "${_node_port_kits_root}/bin/${_node_port_sdk_version}/${_node_port_sdk_bin_arch}")
endif()

# VERBOSE 而不是 STATUS：triplet 每个 port 都要加载一次，STATUS 会刷很多遍。
# Windows SDK 的 mt.exe：给可执行嵌 manifest 用它，**不用** LLVM 的 llvm-mt ——
# 后者不支持 `-outputresource:`（实测直接回 "ignoring unsupported 'outputresource:'
# option"，什么都不做）。路径跟着上面算出来的 SDK 版本走，不写死版本号。
if(NOT _node_port_sdk_version STREQUAL "")
  set(NODE_PORT_WINSDK_MT "${_node_port_kits_root}/bin/${_node_port_sdk_version}/${_node_port_sdk_bin_arch}/mt.exe"
      CACHE FILEPATH "Windows SDK 的 mt.exe（嵌清单；llvm-mt 不支持 -outputresource）")
endif()

if(NOT _node_port_msvc_root STREQUAL "" AND NOT _node_port_sdk_version STREQUAL "")
  message(VERBOSE "node-port: MSVC 命令行环境就绪（MSVC ${_node_port_msvc_root}，Windows SDK ${_node_port_sdk_version}）")
endif()

unset(_node_port_msvc_root)
unset(_node_port_kits_root)
unset(_node_port_sdk_version)
unset(_node_port_part)
unset(_node_port_sdk_bin_arch)
