# One compiler for everything, which on Windows means clang-cl.
#
# Node.js builds itself with clang-cl on Windows (node 24 and later require it;
# vcbuild.bat hard-codes it), and this repository's consumer projects use it
# too - every preset that does not say `-msvc` asks CMake for the ClangCL
# toolset. What was missing is the middle of the chain: vcpkg built every
# dependency of the port with cl.exe, the MSVC default, so a libnode compiled by
# clang-cl was linked against libraries compiled by cl.exe.
#
# That is the configuration this file removes. With it, the port, every
# dependency vcpkg builds for it and the consumer are all clang-cl, which is the
# only Windows compiler configuration this repository tests or guarantees.
# Advanced consumers who want a mixed or MSVC-only build are welcome to it; the
# port neither blocks it nor supports it.
#
# clang-cl is not on PATH inside a vcvars session, so it is located the way the
# port locates it (ports/node/portfile.cmake): an explicit override first, then
# the LLVM that Visual Studio ships for this machine's architecture, then a
# standalone LLVM, then PATH.
#
# VCPKG_TARGET_ARCHITECTURE is what the compiler has to produce code for; on the
# GitHub runners the arm64 legs run on an arm64 machine and the x64 legs on an
# x64 one, so this is always a native build and needs no --target flag. A cross
# build (x64 host, arm64 target) would need one, and is not a configuration this
# repository tests.

if(DEFINED _VCPKG_CLANG_CL_TOOLCHAIN_INCLUDED)
    return()
endif()
set(_VCPKG_CLANG_CL_TOOLCHAIN_INCLUDED TRUE)

set(_clang_cl "")

if(DEFINED ENV{NODE_PORT_LLVM_BIN} AND EXISTS "$ENV{NODE_PORT_LLVM_BIN}/clang-cl.exe")
    set(_clang_cl "$ENV{NODE_PORT_LLVM_BIN}/clang-cl.exe")
endif()

if(NOT _clang_cl AND DEFINED ENV{VCINSTALLDIR})
    # VS ships one LLVM per host architecture (x64 and ARM64 trees side by side).
    # Picking the wrong one either fails to run or silently emits the wrong
    # machine type, so the host's architecture goes first.
    set(_vs_llvm_archs "")
    if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(ARM64|arm64|aarch64)$")
        list(APPEND _vs_llvm_archs ARM64 x64)
    else()
        list(APPEND _vs_llvm_archs x64 ARM64)
    endif()
    foreach(_arch IN LISTS _vs_llvm_archs)
        if(EXISTS "$ENV{VCINSTALLDIR}/Tools/Llvm/${_arch}/bin/clang-cl.exe")
            set(_clang_cl "$ENV{VCINSTALLDIR}/Tools/Llvm/${_arch}/bin/clang-cl.exe")
            break()
        endif()
    endforeach()
    unset(_vs_llvm_archs)
    unset(_arch)
endif()

if(NOT _clang_cl)
    # VCINSTALLDIR is only set inside a vcvars session, and vcpkg runs the
    # compiler-detection step before it loads one, so the Visual Studio install
    # is asked for directly. vswhere ships with every VS 2017+ installer and is
    # the supported way to find one; its two default locations are spelled out
    # because CMake cannot read $ENV{ProgramFiles(x86)} - the parentheses end the
    # variable name.
    set(_vswhere "")
    foreach(_cand
        "C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
        "C:/Program Files/Microsoft Visual Studio/Installer/vswhere.exe")
        if(EXISTS "${_cand}")
            set(_vswhere "${_cand}")
            break()
        endif()
    endforeach()
    unset(_cand)
    if(_vswhere)
        execute_process(
            COMMAND "${_vswhere}" -latest -products * -property installationPath
            OUTPUT_VARIABLE _vs_path
            OUTPUT_STRIP_TRAILING_WHITESPACE
            RESULT_VARIABLE _vs_result)
        if(_vs_result EQUAL 0 AND _vs_path)
            set(_vs_llvm_archs "")
            if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(ARM64|arm64|aarch64)$")
                list(APPEND _vs_llvm_archs ARM64 x64)
            else()
                list(APPEND _vs_llvm_archs x64 ARM64)
            endif()
            foreach(_arch IN LISTS _vs_llvm_archs)
                if(EXISTS "${_vs_path}/VC/Tools/Llvm/${_arch}/bin/clang-cl.exe")
                    set(_clang_cl "${_vs_path}/VC/Tools/Llvm/${_arch}/bin/clang-cl.exe")
                    break()
                endif()
            endforeach()
            unset(_vs_llvm_archs)
            unset(_arch)
        endif()
        unset(_vs_path)
        unset(_vs_result)
    endif()
    unset(_vswhere)
endif()

if(NOT _clang_cl)
    foreach(_cand
        "$ENV{LLVM_ROOT}/bin/clang-cl.exe"
        "$ENV{LLVMInstallDir}/bin/clang-cl.exe"
        "C:/Program Files/LLVM/bin/clang-cl.exe"
        "C:/Program Files (x86)/LLVM/bin/clang-cl.exe")
        if(EXISTS "${_cand}")
            set(_clang_cl "${_cand}")
            break()
        endif()
    endforeach()
    unset(_cand)
endif()

if(NOT _clang_cl)
    find_program(_clang_cl NAMES clang-cl clang-cl.exe)
endif()

if(NOT _clang_cl)
    message(FATAL_ERROR
        "node port toolchain: clang-cl not found. Node.js requires it for its Windows "
        "builds and this repository builds every dependency with it as well. Point "
        "NODE_PORT_LLVM_BIN at an LLVM bin directory, or install the Visual Studio "
        "C++ Clang compiler component.")
endif()

message(STATUS "node port toolchain: building everything with ${_clang_cl}")

set(CMAKE_C_COMPILER "${_clang_cl}" CACHE FILEPATH "clang-cl, the compiler Node.js uses on Windows")
set(CMAKE_CXX_COMPILER "${_clang_cl}" CACHE FILEPATH "clang-cl, the compiler Node.js uses on Windows")

# CMake derives the resource compiler from the compiler's own directory when the
# compiler is MSVC-like, which lands on a bare `rc` for clang-cl (it lives in the
# LLVM tree, not next to the SDK) - and then the link step of every try_compile
# fails with `RC Pass 1: ... no such file or directory` before a single port is
# configured. Take rc.exe from the Windows SDK instead.
#
# The SDK is looked up by path, not through $ENV{WindowsSdkDir}: vcpkg starts a
# port build with a clean environment (no vcvars), which is also why clang-cl
# itself is found with vswhere above. The env var is still honoured first for
# anyone running this toolchain from a developer prompt.
if(NOT CMAKE_RC_COMPILER OR NOT EXISTS "${CMAKE_RC_COMPILER}")
    set(_sdk_roots "")
    if(DEFINED ENV{WindowsSdkDir})
        set(_sdk_from_env "$ENV{WindowsSdkDir}")
        string(REGEX REPLACE "[\\\\/]+$" "" _sdk_from_env "${_sdk_from_env}")
        list(APPEND _sdk_roots "${_sdk_from_env}")
        unset(_sdk_from_env)
    endif()
    list(APPEND _sdk_roots
        "C:/Program Files (x86)/Windows Kits/10"
        "C:/Program Files/Windows Kits/10")
    set(_rc "")
    foreach(_root IN LISTS _sdk_roots)
        if(_rc OR NOT IS_DIRECTORY "${_root}/bin")
            continue()
        endif()
        if(DEFINED ENV{WindowsSDKVersion})
            set(_sdk_version "$ENV{WindowsSDKVersion}")
            string(REGEX REPLACE "[\\\\/]+$" "" _sdk_version "${_sdk_version}")
            if(EXISTS "${_root}/bin/${_sdk_version}/${VCPKG_TARGET_ARCHITECTURE}/rc.exe")
                set(_rc "${_root}/bin/${_sdk_version}/${VCPKG_TARGET_ARCHITECTURE}/rc.exe")
            endif()
            unset(_sdk_version)
        endif()
        if(NOT _rc)
            file(GLOB _rc_dirs LIST_DIRECTORIES true "${_root}/bin/*")
            list(SORT _rc_dirs)
            list(REVERSE _rc_dirs)
            foreach(_dir IN LISTS _rc_dirs)
                if(EXISTS "${_dir}/${VCPKG_TARGET_ARCHITECTURE}/rc.exe")
                    set(_rc "${_dir}/${VCPKG_TARGET_ARCHITECTURE}/rc.exe")
                    break()
                endif()
            endforeach()
            unset(_rc_dirs)
            unset(_dir)
        endif()
    endforeach()
    unset(_sdk_roots)
    unset(_root)
    if(_rc)
        message(STATUS "node port toolchain: resource compiler ${_rc}")
        set(CMAKE_RC_COMPILER "${_rc}" CACHE FILEPATH "rc.exe from the Windows SDK" FORCE)
    else()
        message(FATAL_ERROR
            "node port toolchain: no rc.exe found in a Windows SDK. clang-cl builds need the "
            "resource compiler for the manifest step of every CMake try-compile.")
    endif()
    unset(_rc)
endif()
# clang-cl is the MSVC command-line interface: it needs the MSVC headers and
# libraries, which vcpkg puts on the search path by loading vcvars before it
# configures a port (VCPKG_LOAD_VCVARS_ENV defaults to on). Nothing else to do
# here - in particular no --target flag, because every CI leg builds for its own
# machine type.
