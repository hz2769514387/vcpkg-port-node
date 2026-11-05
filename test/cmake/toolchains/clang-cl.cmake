# The toolchain a clang-cl triplet chainloads. This is the copyable half of the arrangement:
# the triplet states the architecture, CRT and linkage, and this file names the compiler and
# makes vcpkg's own Windows platform settings apply to it.
#
# Two details are not obvious:
#
# 1. The compiler is found through PATH. A triplet that sets `VCPKG_LOAD_VCVARS_ENV ON` makes
#    vcpkg load a Visual Studio developer environment before CMake runs, and vcvars puts the
#    Visual Studio LLVM tree on PATH. `LLVMInstallDir` covers a standalone LLVM installation.
#
# 2. vcpkg's `scripts/toolchains/windows.cmake` is included explicitly. That file is what
#    turns the triplet's `VCPKG_CRT_LINKAGE` into `/MT` or `/MD` in `CMAKE_*_FLAGS_*`, and what
#    sets `CMAKE_SYSTEM_NAME` and the processor. A clang-cl toolchain that omits it leaves
#    every CMake-based dependency on clang-cl's default `/MD`, and a static-CRT graph then
#    fails to link (`LNK2038` / `LNK2019`). It is located through `CMAKE_PARENT_LIST_FILE`,
#    which points at `<vcpkg>/scripts/buildsystems/vcpkg.cmake` even inside a try-compile,
#    where `CMAKE_TOOLCHAIN_FILE` is empty.
#
# Cross builds are not a configuration this repository tests: every CI leg runs on a machine
# of its own architecture. On such a machine `-m64`, `-m32` and the arm64 target triple select
# the machine type the triplet asks for.

if(DEFINED _VCPKG_CLANG_CL_TOOLCHAIN_FILE)
    return()
endif()
set(_VCPKG_CLANG_CL_TOOLCHAIN_FILE TRUE)

find_program(_vcpkg_clang_cl
    NAMES clang-cl clang-cl.exe
    HINTS "$ENV{LLVMInstallDir}/bin")
if(NOT _vcpkg_clang_cl)
    message(FATAL_ERROR
        "clang-cl toolchain: no clang-cl found. Install Visual Studio's 'C++ Clang compiler' "
        "component, or a standalone LLVM, and set VCPKG_LOAD_VCVARS_ENV ON in the triplet so "
        "vcvars puts it on PATH.")
endif()
message(STATUS "clang-cl toolchain: compiler ${_vcpkg_clang_cl}")
set(CMAKE_C_COMPILER "${_vcpkg_clang_cl}" CACHE FILEPATH "clang-cl, the compiler Node.js requires on Windows")
set(CMAKE_CXX_COMPILER "${_vcpkg_clang_cl}" CACHE FILEPATH "clang-cl, the compiler Node.js requires on Windows")

if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x86")
    set(_vcpkg_clang_cl_arch "-m32")
elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
    set(_vcpkg_clang_cl_arch "-m64")
elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
    set(_vcpkg_clang_cl_arch "--target=arm64-pc-windows-msvc")
else()
    message(FATAL_ERROR
        "clang-cl toolchain: unsupported VCPKG_TARGET_ARCHITECTURE "
        "'${VCPKG_TARGET_ARCHITECTURE}' (only x86, x64 and arm64)")
endif()
string(APPEND VCPKG_C_FLAGS " ${_vcpkg_clang_cl_arch}")
string(APPEND VCPKG_CXX_FLAGS " ${_vcpkg_clang_cl_arch}")
unset(_vcpkg_clang_cl_arch)

if(CMAKE_PARENT_LIST_FILE MATCHES "^.*/scripts/buildsystems/vcpkg[.]cmake$")
    get_filename_component(_vcpkg_scripts "${CMAKE_PARENT_LIST_FILE}" DIRECTORY)
    get_filename_component(_vcpkg_scripts "${_vcpkg_scripts}" DIRECTORY)
    include("${_vcpkg_scripts}/toolchains/windows.cmake")
    unset(_vcpkg_scripts)
else()
    message(FATAL_ERROR
        "clang-cl toolchain: the vcpkg checkout could not be located; this file is meant to be "
        "chainloaded by vcpkg (CMAKE_PARENT_LIST_FILE='${CMAKE_PARENT_LIST_FILE}')")
endif()
