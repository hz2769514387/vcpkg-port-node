# MSVC command-line environment for the port's own gyp/ninja build.
#
# vcpkg prepares the MSVC environment for the dependencies it builds, but this
# port drives gyp and ninja directly (clang-cl + link.exe), so it has to put
# INCLUDE, LIB and PATH together itself. What this prevents is hard to read
# otherwise: everything configures, the other ports build, and then a tool fails
# because a header or rc.exe is simply not on the search path.
#
# The port runs from `cmake -P` (script mode), so:
#   * there is no cache - plain variables only;
#   * CMAKE_HOST_SYSTEM_PROCESSOR is not defined (only project() sets it), so
#     $ENV{PROCESSOR_ARCHITECTURE} is the fallback.

if(_NODE_PORT_MSVC_ENV_INCLUDED)
  return()
endif()
set(_NODE_PORT_MSVC_ENV_INCLUDED TRUE)

# vcpkg's download mode replaces execute_process with a fatal stub. Nothing is
# built in that mode, so skip the environment probe entirely.
if(DEFINED VCPKG_DOWNLOAD_MODE)
  return()
endif()

function(_node_port_env_prepend _name _value)
  if(_value STREQUAL "" OR NOT EXISTS "${_value}")
    return()
  endif()
  set(_current "$ENV{${_name}}")
  string(FIND "${_current}" "${_value}" _found)
  if(NOT _found EQUAL -1)
    return()
  endif()
  if(_current STREQUAL "")
    set(ENV{${_name}} "${_value}")
  else()
    set(ENV{${_name}} "${_value};${_current}")
  endif()
endfunction()

# $ENV{ProgramFiles(x86)} cannot be used: the ')' ends the variable reference,
# which is a syntax error under the CMP0053 NEW rules. Read it from the output
# of `cmake -E environment` and match by line prefix instead.
function(_node_port_env_value _name _out)
  set(${_out} "" PARENT_SCOPE)
  execute_process(COMMAND "${CMAKE_COMMAND}" -E environment
    OUTPUT_VARIABLE _text
    ERROR_QUIET
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(_text STREQUAL "")
    return()
  endif()
  string(REPLACE "\n" ";" _lines "${_text}")
  string(LENGTH "${_name}=" _prefix_len)
  foreach(_line IN LISTS _lines)
    string(SUBSTRING "${_line}" 0 ${_prefix_len} _prefix)
    if(_prefix STREQUAL "${_name}=")
      string(SUBSTRING "${_line}" ${_prefix_len} -1 _value)
      string(STRIP "${_value}" _value)
      set(${_out} "${_value}" PARENT_SCOPE)
      return()
    endif()
  endforeach()
endfunction()

_node_port_env_value("ProgramFiles(x86)" _pf_x86)

# --- Visual Studio ----------------------------------------------------------
# vswhere is the official answer and the only one that stays correct when VS is
# not on C: or is not 2022.
set(_vs_root "")
if(DEFINED ENV{VCPKG_VISUAL_STUDIO_PATH} AND NOT "$ENV{VCPKG_VISUAL_STUDIO_PATH}" STREQUAL "")
  set(_vs_root "$ENV{VCPKG_VISUAL_STUDIO_PATH}")
endif()

if(_vs_root STREQUAL "" AND NOT _pf_x86 STREQUAL "")
  find_program(_vswhere vswhere
    HINTS "${_pf_x86}/Microsoft Visual Studio/Installer"
    NO_CACHE)
  if(_vswhere)
    # Queries run from strict to loose: the first is the x64-centred component,
    # the next two cover ARM64-only toolset installs. '|' separates the
    # arguments because ';' is CMake's list separator.
    set(_vswhere_queries
      "-requires|Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
      "-requiresAny|-requires|Microsoft.VisualStudio.Component.VC.Tools.x86.x64|Microsoft.VisualStudio.Component.VC.Tools.ARM64|Microsoft.VisualStudio.Component.VC.Tools.ARM64EC"
      "")
    foreach(_q IN LISTS _vswhere_queries)
      string(REPLACE "|" ";" _args "${_q}")
      execute_process(COMMAND "${_vswhere}" -latest -products * -property installationPath ${_args}
        OUTPUT_VARIABLE _out
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE)
      if(NOT _out STREQUAL "")
        string(REPLACE "\n" ";" _out_lines "${_out}")
        list(GET _out_lines 0 _vs_root)
        message(STATUS "node port: vswhere matched [${_q}] -> ${_vs_root}")
        break()
      endif()
    endforeach()
    unset(_args)
    unset(_q)
    unset(_out)
    unset(_out_lines)
    unset(_vswhere_queries)
  endif()
  unset(_vswhere)
endif()

# vswhere and the environment report native (backslash) paths, and file(GLOB)
# does not understand backslashes - the MSVC directory would silently go empty.
if(NOT _vs_root STREQUAL "")
  file(TO_CMAKE_PATH "${_vs_root}" _vs_root)
endif()

set(NODE_PORT_VS_INSTALL_ROOT "${_vs_root}")

# Host architecture (x64 / arm64): which "host tools" directory to use.
# Three-level read because CMAKE_HOST_SYSTEM_PROCESSOR is undefined in script
# mode: VCPKG_DETECTED_* -> CMAKE_HOST_* -> PROCESSOR_ARCHITECTURE.
set(_host_raw "${VCPKG_DETECTED_CMAKE_HOST_SYSTEM_PROCESSOR}")
if(_host_raw STREQUAL "")
  set(_host_raw "${CMAKE_HOST_SYSTEM_PROCESSOR}")
endif()
if(_host_raw STREQUAL "")
  set(_host_raw "$ENV{PROCESSOR_ARCHITECTURE}")
endif()
set(_host_arch "x64")
if(_host_raw MATCHES "^(ARM64|arm64|aarch64)$")
  set(_host_arch "arm64")
endif()
set(NODE_PORT_HOST_ARCH "${_host_arch}")
message(STATUS "node port: host architecture ${_host_arch} (read from '${_host_raw}')")

# --- MSVC toolset -----------------------------------------------------------
set(_msvc_root "")
if(NOT _vs_root STREQUAL "")
  file(GLOB _msvc_versions "${_vs_root}/VC/Tools/MSVC/*")
  if(_msvc_versions)
    list(SORT _msvc_versions)
    list(REVERSE _msvc_versions)
    list(GET _msvc_versions 0 _msvc_root)
  endif()
  unset(_msvc_versions)
endif()

# Target architecture: VCPKG_TARGET_ARCHITECTURE -> first segment of the
# triplet -> host. Fail loudly if none is available rather than silently
# building for the host.
set(_target_raw "")
if(DEFINED VCPKG_TARGET_ARCHITECTURE AND NOT VCPKG_TARGET_ARCHITECTURE STREQUAL "")
  set(_target_raw "${VCPKG_TARGET_ARCHITECTURE}")
elseif(DEFINED VCPKG_TARGET_TRIPLET AND NOT VCPKG_TARGET_TRIPLET STREQUAL "")
  string(REGEX MATCH "^[^-]+" _target_raw "${VCPKG_TARGET_TRIPLET}")
else()
  set(_target_raw "${_host_arch}")
endif()
if(NOT _target_raw MATCHES "^(x64|arm64|x86|arm)$")
  message(FATAL_ERROR
    "node port: unrecognised target architecture '${_target_raw}' "
    "(only x64/arm64/x86/arm are supported).")
endif()
set(NODE_PORT_TARGET_ARCH "${_target_raw}")
unset(_target_raw)

if(NOT _msvc_root STREQUAL "")
  # Host tools (nmake/cl/link) live under a host-architecture directory. Pick by
  # host arch; the other layout is a fallback. prepend inserts at the front, so
  # the host-native directory is added last and wins.
  if(_host_arch STREQUAL "arm64")
    set(_host_dir "Hostarm64/arm64")
    set(_alt_dir "Hostx64/x64")
  else()
    set(_host_dir "Hostx64/x64")
    set(_alt_dir "Hostarm64/arm64")
  endif()
  _node_port_env_prepend(PATH "${_msvc_root}/bin/${_alt_dir}")
  _node_port_env_prepend(PATH "${_msvc_root}/bin/${_host_dir}")
  unset(_host_dir)
  unset(_alt_dir)
  _node_port_env_prepend(INCLUDE "${_msvc_root}/include")
  _node_port_env_prepend(LIB "${_msvc_root}/lib/${NODE_PORT_TARGET_ARCH}")
endif()

# --- Windows SDK ------------------------------------------------------------
set(_kits_root "")
if(DEFINED ENV{WindowsSdkDir} AND NOT "$ENV{WindowsSdkDir}" STREQUAL "")
  set(_kits_root "$ENV{WindowsSdkDir}")
elseif(NOT _pf_x86 STREQUAL "")
  file(TO_CMAKE_PATH "${_pf_x86}" _pf_x86_cmake)
  set(_kits_root "${_pf_x86_cmake}/Windows Kits/10")
  unset(_pf_x86_cmake)
endif()
if(_kits_root STREQUAL "")
  set(_kits_root "C:/Program Files (x86)/Windows Kits/10")
endif()
unset(_pf_x86)

set(_sdk_version "")
if(EXISTS "${_kits_root}/Include")
  file(GLOB _sdk_cands RELATIVE "${_kits_root}/Include" "${_kits_root}/Include/*")
  # Keep only version-looking names: the directory also holds um/ucrt/shared/wdf,
  # and a plain lexicographic sort would pick 'wdf' as the newest.
  set(_sdk_versions "")
  foreach(_c IN LISTS _sdk_cands)
    if(_c MATCHES "^[0-9]+\\.[0-9]+")
      list(APPEND _sdk_versions "${_c}")
    endif()
  endforeach()
  unset(_c)
  if(_sdk_versions)
    # COMPARE NATURAL so 10.0.9.0 < 10.0.10.0.
    list(SORT _sdk_versions COMPARE NATURAL ORDER DESCENDING)
    list(GET _sdk_versions 0 _sdk_version)
  endif()
  unset(_sdk_versions)
  unset(_sdk_cands)
endif()

if(NOT _sdk_version STREQUAL "")
  foreach(_part ucrt um shared winrt)
    _node_port_env_prepend(INCLUDE "${_kits_root}/Include/${_sdk_version}/${_part}")
  endforeach()
  foreach(_part ucrt um)
    _node_port_env_prepend(LIB "${_kits_root}/Lib/${_sdk_version}/${_part}/${NODE_PORT_TARGET_ARCH}")
  endforeach()
  # SDK bin holds host tools (rc.exe, mt.exe). Pick by host arch, then x64/x86,
  # then any directory that actually has rc.exe. Fail if none exists: a missing
  # rc.exe makes gyp's msvs emulation fail in a place that reads like another
  # port's problem.
  set(_sdk_bin_arch "")
  foreach(_cand IN ITEMS "${_host_arch}" "x64" "x86")
    if(EXISTS "${_kits_root}/bin/${_sdk_version}/${_cand}/rc.exe")
      set(_sdk_bin_arch "${_cand}")
      break()
    endif()
  endforeach()
  if(_sdk_bin_arch STREQUAL "")
    file(GLOB _sdk_bin_cands
      RELATIVE "${_kits_root}/bin/${_sdk_version}"
      "${_kits_root}/bin/${_sdk_version}/*")
    foreach(_cand IN LISTS _sdk_bin_cands)
      if(EXISTS "${_kits_root}/bin/${_sdk_version}/${_cand}/rc.exe")
        set(_sdk_bin_arch "${_cand}")
        break()
      endif()
    endforeach()
    unset(_sdk_bin_cands)
  endif()
  unset(_cand)
  if(_sdk_bin_arch STREQUAL "")
    message(FATAL_ERROR
      "node port: no host-tool directory with rc.exe under Windows SDK "
      "${_sdk_version}:\n  ${_kits_root}/bin/${_sdk_version}/*\n"
      "gyp's msvs emulation needs rc.exe; install the SDK desktop tools.")
  endif()
  message(STATUS "node port: SDK host tools directory ${_sdk_bin_arch} (host ${_host_arch})")
  _node_port_env_prepend(PATH "${_kits_root}/bin/${_sdk_version}/${_sdk_bin_arch}")
  # mt.exe: gyp's msvs emulation embeds node.exe's manifest with it. LLVM's
  # llvm-mt is not a substitute - it ignores `-outputresource:`.
  set(NODE_PORT_WINSDK_MT "${_kits_root}/bin/${_sdk_version}/${_sdk_bin_arch}/mt.exe")
endif()

if(NOT _msvc_root STREQUAL "" AND NOT _sdk_version STREQUAL "")
  message(STATUS "node port: MSVC command-line environment ready (MSVC ${_msvc_root}, Windows SDK ${_sdk_version})")
elseif(_msvc_root STREQUAL "")
  message(WARNING
    "node port: MSVC toolset not found (VS missing or vswhere cannot see it).\n"
    "  gyp/clang-cl needs MSVC headers and libraries. Inside a developer command\n"
    "  prompt the environment is already complete; otherwise install VS's C++\n"
    "  workload or set VCPKG_VISUAL_STUDIO_PATH.")
endif()

unset(_msvc_root)
unset(_kits_root)
unset(_sdk_version)
unset(_part)
unset(_sdk_bin_arch)
unset(_host_raw)
unset(_host_arch)
