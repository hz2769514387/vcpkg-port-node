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
    # ★ 三条查询按"严 → 宽"排，**第一条就是原来那条**，所以 x64 机器上行为一字不变。
    #   为什么需要后两条：原来硬要求 `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`，
    #   那是**x64 中心**的组件名。2026-10-13 起 arm64-windows 走原生 arm64 runner，
    #   那个镜像上的 VS 若只装了 ARM64 工具集，这条查询返回空 ⇒ INCLUDE / LIB / nmake
    #   全都**静默**不挂（vcpkg 的 nmake 支路于是报"找不到 nmake"，离真因很远）。
    #   第二条用 `-requiresAny`：任一 C++ 工具组件在就算命中；第三条兜"任意 VS"。
    #
    #   ★ 参数用 '|' 分隔，**不能用 ';'**：';' 是 CMake 的列表分隔符，写成
    #     "-requires;ID" 放进 list 会被拆成两个元素，下面的 foreach 就变成"按 token 迭代"
    #     （第一条查询成了裸的 `-requires`，vswhere 会吐版本横幅，被误判成命中）。
    #     这个坑是**把这段真跑一遍**才发现的，光看代码看不出来。
    set(_node_port_vswhere_queries
      "-requires|Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
      "-requiresAny|-requires|Microsoft.VisualStudio.Component.VC.Tools.x86.x64|Microsoft.VisualStudio.Component.VC.Tools.ARM64|Microsoft.VisualStudio.Component.VC.Tools.ARM64EC"
      ""
    )
    foreach(_node_port_vswhere_query IN LISTS _node_port_vswhere_queries)
      string(REPLACE "|" ";" _node_port_vswhere_query_args "${_node_port_vswhere_query}")
      set(_node_port_vswhere_args -latest -products * -property installationPath ${_node_port_vswhere_query_args})
      execute_process(COMMAND "${_node_port_vswhere}" ${_node_port_vswhere_args}
        OUTPUT_VARIABLE _node_port_vswhere_out
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE)
      if(NOT _node_port_vswhere_out STREQUAL "")
        string(REPLACE "\n" ";" _node_port_vswhere_lines "${_node_port_vswhere_out}")
        list(GET _node_port_vswhere_lines 0 _node_port_vs_root)
        message(VERBOSE "node-port: vswhere 命中（查询 [${_node_port_vswhere_query}]）→ ${_node_port_vs_root}")
        break()
      endif()
    endforeach()
    unset(_node_port_vswhere_args)
    unset(_node_port_vswhere_query)
    unset(_node_port_vswhere_query_args)
  endif()
  unset(_node_port_vswhere)
  unset(_node_port_vswhere_out)
  unset(_node_port_vswhere_lines)
  unset(_node_port_vswhere_queries)
endif()

# vswhere 与环境变量都报原生路径（反斜杠），而 file(GLOB) **不认反斜杠** ——
# MSVC 目录会静默变空，最后只有 SDK 那一半 INCLUDE/LIB 被设上。
if(NOT _node_port_vs_root STREQUAL "")
  file(TO_CMAKE_PATH "${_node_port_vs_root}" _node_port_vs_root)
endif()

# 给 clang-cl.cmake 用：它要从同一个安装里取 VC/Tools/Llvm。
set(NODE_PORT_VS_INSTALL_ROOT "${_node_port_vs_root}")

# 宿主架构（x64 / arm64）——决定各处"**宿主**工具"的目录。
# 注意与 _node_port_msvc_arch（**目标**架构）区分开：宿主工具必须能在构建机上跑。
set(_node_port_host_arch "x64")
if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(ARM64|arm64|aarch64)$")
  set(_node_port_host_arch "arm64")
endif()

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

# ---------------------------------------------------------------------------
# 目标架构（x64 / arm64 / x86 / arm）—— 决定 LIB 目录，也被 clang-cl.cmake 用来
# 算 `--target=`。
#
# ★ 判据的顺序是有讲究的：**不能只看 VCPKG_TARGET_ARCHITECTURE**。
#   vcpkg **编 port** 时会把 `-DVCPKG_TARGET_ARCHITECTURE=<arch>` 显式传给那个子进程
#   （实测：abseil 的 configure 命令行里有它），但**消费端工程**（本仓库 test/）
#   走的是 vcpkg.cmake —— 那个文件在第 209 行就 include 本文件，而它**从不设置**
#   这个变量（只在 971 行把它列进 try_compile 的传播名单，值本身由 vcpkg 工具进程
#   自己持有）⇒ 在消费端它**永远是空的**。原来空值落到 "x64" 默认，后果：
#     * 消费端的 LIB 一直指向 `<MSVC>/lib/x64`，而 --target 也按 x64 给（前者见下、
#       后者见 clang-cl.cmake）；
#     * run #28 之前 node 自己的库也被 gyp 的 -m64 编成 x64 —— 两半错得一致，
#       所以只是"CRT 符号找不到"，看不出根因；
#     * run #29（patch 0017 让 node 的库真 arm64 之后）消费端还是 x64，于是
#       lld-link: error: node_base.lib(node_base.callback.obj): machine type arm64 conflicts with x64
#   退路按可靠性排序：
#     ① VCPKG_TARGET_ARCHITECTURE（port 侧唯一权威）；
#     ② VCPKG_TARGET_TRIPLET 的首段（vcpkg 的 triplet 命名约定是 `<arch>-<os>[-变体]`，
#        本仓库 test/cmake/triplets/ 的六个也都照此命名）；
#     ③ 宿主架构（本仓库 Windows 两档都是 host==target 的原生构建）。
#   三条都拿不到就**直接红**：宁可配置期报错，也不再"静默编成宿主的 x64"。
# ---------------------------------------------------------------------------
set(_node_port_target_arch_src "")
if(DEFINED VCPKG_TARGET_ARCHITECTURE AND NOT VCPKG_TARGET_ARCHITECTURE STREQUAL "")
  set(NODE_PORT_TARGET_ARCH_RAW "${VCPKG_TARGET_ARCHITECTURE}")
  set(_node_port_target_arch_src "VCPKG_TARGET_ARCHITECTURE")
elseif(DEFINED VCPKG_TARGET_TRIPLET AND NOT VCPKG_TARGET_TRIPLET STREQUAL "")
  string(REGEX MATCH "^[^-]+" NODE_PORT_TARGET_ARCH_RAW "${VCPKG_TARGET_TRIPLET}")
  set(_node_port_target_arch_src "VCPKG_TARGET_TRIPLET=${VCPKG_TARGET_TRIPLET} 的首段")
else()
  set(NODE_PORT_TARGET_ARCH_RAW "${_node_port_host_arch}")
  set(_node_port_target_arch_src
      "宿主架构（CMAKE_HOST_SYSTEM_PROCESSOR=${CMAKE_HOST_SYSTEM_PROCESSOR}）")
endif()

if(NODE_PORT_TARGET_ARCH_RAW STREQUAL "x64")
  set(_node_port_target_arch_value "x64")
elseif(NODE_PORT_TARGET_ARCH_RAW STREQUAL "arm64")
  set(_node_port_target_arch_value "arm64")
elseif(NODE_PORT_TARGET_ARCH_RAW STREQUAL "x86")
  set(_node_port_target_arch_value "x86")
elseif(NODE_PORT_TARGET_ARCH_RAW STREQUAL "arm")
  set(_node_port_target_arch_value "arm")
else()
  message(FATAL_ERROR
    "认不出的目标架构 '${NODE_PORT_TARGET_ARCH_RAW}'（来自 ${_node_port_target_arch_src}）。\n"
    "只认 x64 / arm64 / x86 / arm。这通常意味着 triplet 名不按 `<arch>-<os>...` 的约定，"
    "或者有人在命令行上把 VCPKG_TARGET_ARCHITECTURE 设成了别的东西。")
endif()
unset(_node_port_target_arch_src)
unset(NODE_PORT_TARGET_ARCH_RAW)

# 存进 cache：本文件可能有 include 守卫（二次 include 直接 return），而 clang-cl.cmake
# 与 triplet 都依赖这个值 —— cache 变量不受"谁先 include、在哪个作用域"的影响。
set(NODE_PORT_TARGET_ARCH "${_node_port_target_arch_value}" CACHE INTERNAL
    "本工程的目标架构（MSVC 写法：x64/arm64/x86/arm）；由 msvc-command-line-env.cmake 解析")

# MSVC 的 lib 目录名就是这套写法，直接沿用。
set(_node_port_msvc_arch "${NODE_PORT_TARGET_ARCH}")

# 宿主工具目录（nmake / cl.exe / dumpbin 所在）——**按宿主架构挑，不要写死 Hostx64**。
# ★ 原来这里写的是"宿主工具目录恒为 Hostx64（我们只在 x64 宿主上构建）"。
#   2026-10-13 起 arm64-windows 这一档走**原生 arm64 runner**（windows-11-arm），
#   那个前提就不成立了：arm64 宿主上 VS 的工具目录是 `Hostarm64/arm64`。
#   两个都挂上、存在才加（_node_port_env_prepend 自带 EXISTS 检查），
#   这样 x64 宿主的行为与之前完全一致，arm64 宿主也能拿到 nmake。
if(NOT _node_port_msvc_root STREQUAL "")
  # 两个布局都挂上（存在才加）。★ 注意 prepend 是"插到最前"，所以**后调用的排在更前** ——
  # 先挂备选、再挂宿主架构那个，保证宿主原生工具优先。
  if(_node_port_host_arch STREQUAL "arm64")
    set(_node_port_msvc_host_dir "Hostarm64/arm64")
    set(_node_port_msvc_host_alt "Hostx64/x64")
  else()
    set(_node_port_msvc_host_dir "Hostx64/x64")
    set(_node_port_msvc_host_alt "Hostarm64/arm64")
  endif()
  _node_port_env_prepend(PATH "${_node_port_msvc_root}/bin/${_node_port_msvc_host_alt}")
  _node_port_env_prepend(PATH "${_node_port_msvc_root}/bin/${_node_port_msvc_host_dir}")
  unset(_node_port_msvc_host_dir)
  unset(_node_port_msvc_host_alt)
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
  # ★★ 只认"像版本号"的目录名（`^[0-9]+\.[0-9]+`）。
  #
  # 为什么：`<kits>/Include/` 下面**不只**有版本目录 —— 还躺着 `wdf` / `um` / `ucrt` /
  # `shared` / `winrt` 这些**同级**目录。而原来的 `list(SORT)` 是**字典序**，
  # `'w' > '1'`，于是"最新的 SDK 版本"会被算成 **wdf**。
  #
  # ★ 实测（run #26 的 arm64，windows-11-arm 镜像）：`_node_port_sdk_version` 变成 `wdf`
  #   ⇒ INCLUDE / LIB / SDK bin 三处全部指向 `<kits>/.../wdf/...`（不存在）
  #   ⇒ `_node_port_env_prepend` 对不存在的路径是静默跳过 ⇒ INCLUDE/LIB/rc.exe 全都没挂上。
  #   表现出来是**别的 port** 报怪错（run #25 是 abseil 的
  #   `RC Pass 1: command "rc ..." failed: no such file or directory`）——
  #   这次是新加的"挑不到 rc.exe 就 FATAL"把它当场点破了。
  #   （本机 SDK 的 Include/ 只有版本目录，所以本地看不出来；x64 镜像大概也没有 wdf，
  #     于是 x64 一直"侥幸"能过 —— CMake 自己会去找 rc.exe，掩盖了这三处 prepend 失效。）
  set(_node_port_sdk_versioned "")
  foreach(_node_port_sdk_cand IN LISTS _node_port_sdk_versions)
    if(_node_port_sdk_cand MATCHES "^[0-9]+\\.[0-9]+")
      list(APPEND _node_port_sdk_versioned "${_node_port_sdk_cand}")
    endif()
  endforeach()
  unset(_node_port_sdk_cand)
  if(_node_port_sdk_versioned)
    # COMPARE NATURAL：按数值段比，10.0.9.0 < 10.0.10.0 才对（字典序会反过来）。
    list(SORT _node_port_sdk_versioned COMPARE NATURAL ORDER DESCENDING)
    list(GET _node_port_sdk_versioned 0 _node_port_sdk_version)
  endif()
  unset(_node_port_sdk_versioned)
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
  # 的规矩该用**宿主**架构挑目录（x64 宿主 → x64；arm64 宿主 → arm64）。
  #
  # ★★ 2026-10-13 实测（run #25 的 arm64-windows，换原生 arm64 runner 后第一次跑）：
  #    原来那句"宿主架构目录不存在就退回目标架构目录"会**两头落空** —— arm64 宿主上
  #    目标架构也是 arm64，于是退回的还是同一个不存在的目录；而
  #    `_node_port_env_prepend` 对不存在的路径是**静默跳过**的 ⇒ 整条 PATH 上没有 rc.exe
  #    ⇒ CMake 的 vs_link_exe 连 try-compile 都过不了，报在 **abseil 的 configure** 里：
  #        RC Pass 1: command "rc /fo .../manifest.res .../manifest.rc" failed ...
  #            no such file or directory
  #    离真因（PATH 没挂上 SDK 的宿主工具目录）非常远。
  #    以前没暴露是因为交叉编译时宿主恒为 x64，`bin/<ver>/x64/rc.exe` 一直都在。
  #
  # 现在按"宿主架构 → x64 → x86 → 任意带 rc.exe 的子目录"挑，**一个都没有就当场红** ——
  # 缺 rc.exe 是结构性问题，不该留到别的 port 里以看不懂的样子报出来。
  # （挑到 x64 的 rc.exe 在 arm64 宿主上靠仿真也能跑，这是可接受的降级。）
  set(_node_port_sdk_bin_arch "")
  foreach(_node_port_sdk_bin_cand IN ITEMS "${_node_port_host_arch}" "x64" "x86")
    if(EXISTS "${_node_port_kits_root}/bin/${_node_port_sdk_version}/${_node_port_sdk_bin_cand}/rc.exe")
      set(_node_port_sdk_bin_arch "${_node_port_sdk_bin_cand}")
      break()
    endif()
  endforeach()
  if(_node_port_sdk_bin_arch STREQUAL "")
    file(GLOB _node_port_sdk_bin_cands
      RELATIVE "${_node_port_kits_root}/bin/${_node_port_sdk_version}"
      "${_node_port_kits_root}/bin/${_node_port_sdk_version}/*")
    foreach(_node_port_sdk_bin_cand IN LISTS _node_port_sdk_bin_cands)
      if(EXISTS "${_node_port_kits_root}/bin/${_node_port_sdk_version}/${_node_port_sdk_bin_cand}/rc.exe")
        set(_node_port_sdk_bin_arch "${_node_port_sdk_bin_cand}")
        break()
      endif()
    endforeach()
    unset(_node_port_sdk_bin_cands)
  endif()
  unset(_node_port_sdk_bin_cand)
  if(_node_port_sdk_bin_arch STREQUAL "")
    message(FATAL_ERROR
      "在 Windows SDK ${_node_port_sdk_version} 下找不到任何带 rc.exe 的宿主工具目录：\n"
      "  ${_node_port_kits_root}/bin/${_node_port_sdk_version}/*\n"
      "缺 rc.exe 时 CMake 的 vs_link_exe 连 try-compile 都过不了（报在别的 port 的 configure 里，\n"
      "读起来完全看不出是这里的问题）。请把 SDK 的桌面工具装全。")
  endif()
  message(VERBOSE "node-port: SDK 宿主工具目录用 ${_node_port_sdk_bin_arch}（宿主架构 ${_node_port_host_arch}）")
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
