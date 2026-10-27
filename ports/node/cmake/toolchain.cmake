# Toolchain: which compiler builds Node.js, and the environment it needs.
#
# Owns: the clang-cl ladder and the MSVC command-line environment on Windows, CC/CXX on
# Unix, the CRT channel, compiler-rt builtins, the macOS frameworks the archives drag in,
# and cargo (which vcpkg cannot acquire).
#
# Expects from the portfile: nothing. Publishes _node_cc / _node_cxx / _node_dynamic_crt /
# _node_rt_arch and, on Windows, the environment configure.py and gyp inherit.

# ---------------------------------------------------------------------------
# Compiler and environment.
#   * Windows: clang-cl (Node.js 24+ requires it). The compiler and the MSVC
#     command-line environment are both set up here, so the consumer needs
#     nothing beyond a stock triplet.
#   * Linux / macOS: the system cc / c++.
# configure.py reads CC/CXX to choose the compiler rule in the generated ninja.
# ---------------------------------------------------------------------------
set(_node_cc "")
set(_node_cxx "")
set(_node_clang_cl_arg "")
set(_node_rt_builtins_lib "")
set(_node_rt_arch "")
set(_node_dynamic_crt 0)

if(VCPKG_TARGET_IS_WINDOWS)
    # Put INCLUDE / LIB / PATH together for the gyp/ninja build (nmake, MSVC and
    # SDK headers, rc.exe/mt.exe) and publish NODE_PORT_VS_INSTALL_ROOT and
    # NODE_PORT_HOST_ARCH.
    include("${NODE_PORT_DIR}/scripts/node-msvc-env.cmake")

    # --- locate clang-cl ---
    #   (1) NODE_PORT_LLVM_BIN     explicit override (CI pins the runner layout)
    #   (2) NODE_PORT_LLVM_ROOT    an LLVM install root (with x64/bin or bin)
    #   (3) VS's bundled LLVM, picked by host architecture (VS ships x64 and
    #       ARM64 trees side by side; the wrong one either will not run or
    #       silently produces the wrong machine type)
    #   (4) a standalone LLVM install in the usual place
    #   (5) vcpkg_find_acquire_program(CLANG), which may download LLVM
    #   (6) $ENV{CC} when it names clang-cl
    #   (7) find_program(clang-cl)
    set(_node_clang_cl "")
    if(DEFINED NODE_PORT_LLVM_BIN AND NOT NODE_PORT_LLVM_BIN STREQUAL ""
       AND EXISTS "${NODE_PORT_LLVM_BIN}/clang-cl.exe")
        set(_node_clang_cl "${NODE_PORT_LLVM_BIN}/clang-cl.exe")
    endif()
    if(_node_clang_cl STREQUAL "" AND DEFINED NODE_PORT_LLVM_ROOT AND NOT NODE_PORT_LLVM_ROOT STREQUAL "")
        foreach(_cand "${NODE_PORT_LLVM_ROOT}/x64/bin/clang-cl.exe"
                      "${NODE_PORT_LLVM_ROOT}/bin/clang-cl.exe")
            if(EXISTS "${_cand}")
                set(_node_clang_cl "${_cand}")
                break()
            endif()
        endforeach()
        unset(_cand)
    endif()
    if(_node_clang_cl STREQUAL "" AND DEFINED NODE_PORT_VS_INSTALL_ROOT
       AND NOT NODE_PORT_VS_INSTALL_ROOT STREQUAL "")
        set(_node_llvm_arch_order "")
        if(DEFINED NODE_PORT_HOST_ARCH)
            list(APPEND _node_llvm_arch_order "${NODE_PORT_HOST_ARCH}")
        endif()
        list(APPEND _node_llvm_arch_order x64 ARM64)
        foreach(_arch IN LISTS _node_llvm_arch_order)
            if(EXISTS "${NODE_PORT_VS_INSTALL_ROOT}/VC/Tools/Llvm/${_arch}/bin/clang-cl.exe")
                set(_node_clang_cl "${NODE_PORT_VS_INSTALL_ROOT}/VC/Tools/Llvm/${_arch}/bin/clang-cl.exe")
                break()
            endif()
        endforeach()
        unset(_node_llvm_arch_order)
        unset(_arch)
    endif()
    if(_node_clang_cl STREQUAL "")
        foreach(_cand
            "$ENV{LLVM_ROOT}/bin/clang-cl.exe"
            "$ENV{LLVMInstallDir}/bin/clang-cl.exe"
            "C:/Program Files/LLVM/bin/clang-cl.exe"
            "C:/Program Files (x86)/LLVM/bin/clang-cl.exe")
            if(EXISTS "${_cand}")
                set(_node_clang_cl "${_cand}")
                break()
            endif()
        endforeach()
        unset(_cand)
    endif()
    if(_node_clang_cl STREQUAL "")
        vcpkg_find_acquire_program(CLANG)
        if(DEFINED CLANG AND NOT CLANG STREQUAL "")
            get_filename_component(_clang_bin "${CLANG}" DIRECTORY)
            if(EXISTS "${_clang_bin}/clang-cl.exe")
                set(_node_clang_cl "${_clang_bin}/clang-cl.exe")
            endif()
            unset(_clang_bin)
        endif()
    endif()
    if(_node_clang_cl STREQUAL "" AND DEFINED ENV{CC} AND "$ENV{CC}" MATCHES "clang-cl")
        set(_node_clang_cl "$ENV{CC}")
    endif()
    if(_node_clang_cl STREQUAL "")
        find_program(_node_clang_cl NAMES clang-cl)
    endif()
    if(NOT _node_clang_cl)
        message(FATAL_ERROR
            "node port: clang-cl is required on Windows (Node.js 24+ upstream rule).\n"
            "Looked at NODE_PORT_LLVM_BIN, NODE_PORT_LLVM_ROOT, VS's bundled LLVM\n"
            "(by host architecture), a standalone LLVM install, vcpkg's CLANG\n"
            "acquisition, $ENV{CC} and PATH - none matched. Install Visual Studio's\n"
            "'C++ Clang compiler' component (or a standalone LLVM) and retry.")
    endif()
    # Verify the architecture: a VS that ships both x64 and ARM64 LLVM trees can
    # hand out the wrong one, which fails far away from here.
    if(DEFINED NODE_PORT_HOST_ARCH AND EXISTS "${_node_clang_cl}")
        get_filename_component(_clang_parent "${_node_clang_cl}" DIRECTORY)
        get_filename_component(_clang_llvm_arch "${_clang_parent}" DIRECTORY)
        get_filename_component(_clang_llvm_arch "${_clang_llvm_arch}" NAME)
        if(_clang_llvm_arch MATCHES "^(x64|ARM64|arm64)$"
           AND NOT _clang_llvm_arch STREQUAL "${NODE_PORT_HOST_ARCH}")
            message(FATAL_ERROR
                "node port: found the ${_clang_llvm_arch} clang-cl (${_node_clang_cl}) but "
                "the host is ${NODE_PORT_HOST_ARCH} - the build would produce the wrong "
                "machine type. Point NODE_PORT_LLVM_ROOT at the ${NODE_PORT_HOST_ARCH} tree.")
        endif()
        unset(_clang_parent)
        unset(_clang_llvm_arch)
    endif()
    message(STATUS "node port: clang-cl = ${_node_clang_cl}")
    set(_node_cc "${_node_clang_cl}")
    set(_node_cxx "${_node_clang_cl}")

    # gyp's VS probe reads registry keys modern VS does not write, and its
    # DirectX probe decodes reg.exe output as UTF-8 (dies on a localized code
    # page). Both are avoided by pinning these.
    set(ENV{GYP_MSVS_VERSION} 2022)
    if(NODE_PORT_VS_INSTALL_ROOT)
        set(ENV{GYP_MSVS_OVERRIDE_PATH} "${NODE_PORT_VS_INSTALL_ROOT}")
    endif()
    set(ENV{DXSDK_DIR} "C:/nonexistent")

    # system-icu is resolved through pkg-config; vcpkg's PKGCONFIG is a native
    # Windows build that understands PKG_CONFIG_PATH.
    vcpkg_find_acquire_program(PKGCONFIG)
    set(ENV{PKG_CONFIG} "${PKGCONFIG}")

    # vcpkg's headers go on INCLUDE too: some non-V8 targets (js2c, torque) need
    # simdutf.h and friends, and adding the directory once beats repeating it
    # per target.
    set(ENV{INCLUDE} "${CURRENT_INSTALLED_DIR}/include;$ENV{INCLUDE}")

    # --clang-cl=<ver> makes configure.py set clang=1, which is what turns
    # V8's asm_to_inline_asm action on (otherwise the embedded blob symbols go
    # missing and the link fails).
    execute_process(
        COMMAND "${_node_cc}" --version
        OUTPUT_VARIABLE _clang_version_output
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE)
    string(REGEX REPLACE "^clang version ([0-9]+[.][0-9]+[.][0-9]+).*" "\\1"
           _llvm_version "${_clang_version_output}")
    set(_node_clang_cl_arg "--clang-cl=${_llvm_version}")

    # The patches that probe macros/OpenSSL need the clang.exe sibling and a
    # target triple, and hdr-histogram's __cpu_model needs clang's compiler-rt
    # builtins. Both come from the environment so the patches carry no
    # architecture constants.
    if(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
        set(_node_llvm_arch "aarch64")
        set(_node_rt_arch "aarch64")
    elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "x86")
        set(_node_llvm_arch "i686")
        set(_node_rt_arch "i386")
    else()
        set(_node_llvm_arch "x86_64")
        set(_node_rt_arch "x86_64")
    endif()
    set(ENV{NODE_PORT_CLANG_TARGET} "${_node_llvm_arch}-pc-windows-msvc")
    set(ENV{NODE_PORT_CLANG_RT_BUILTINS_NAME} "clang_rt.builtins-${_node_rt_arch}")

    # --- CRT: follow VCPKG_CRT_LINKAGE ---
    # Node.js upstream only switches to a dynamic CRT through --shared, which
    # also turns the library into a DLL. For a static library with /MD the port
    # adds the minimal channel - two anchored edits with the same shape:
    #   * configure.py: force_dynamic_crt additionally reads NODE_PORT_FORCE_DYNAMIC_CRT;
    #   * common.gypi: the two MSVC_runtimeType conditions also check force_dynamic_crt.
    # With a static CRT the variable is unset, so both edits are semantically
    # identical to upstream (0 is false). vcpkg_replace_string makes an upstream
    # wording change fail loudly rather than silently.
    if(VCPKG_CRT_LINKAGE STREQUAL "dynamic")
        set(_node_dynamic_crt 1)
        set(ENV{NODE_PORT_FORCE_DYNAMIC_CRT} "1")
        message(STATUS "node port: VCPKG_CRT_LINKAGE=dynamic -> /MD, /MDd")
    else()
        message(STATUS "node port: VCPKG_CRT_LINKAGE=${VCPKG_CRT_LINKAGE} -> /MT, /MTd")
    endif()

    # --- compiler-rt builtins: ship them ---
    # The clang-cl objects reference __cpu_model (__builtin_cpu_supports), and a
    # consumer link (cl.exe's link.exe or lld-link) never pulls in clang's
    # compiler-rt on its own. The port installs the archive and the exported
    # config links it by absolute path, so a consumer without a matching LLVM
    # still links.
    execute_process(
        COMMAND "${_node_cc}" --print-resource-dir
        OUTPUT_VARIABLE _clang_resource_dir
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE)
    if(NOT _clang_resource_dir STREQUAL "")
        file(TO_CMAKE_PATH "${_clang_resource_dir}" _clang_resource_dir)
        set(_rt_cand "${_clang_resource_dir}/lib/windows/clang_rt.builtins-${_node_rt_arch}.lib")
        if(EXISTS "${_rt_cand}")
            set(_node_rt_builtins_lib "${_rt_cand}")
            message(STATUS "node port: compiler-rt builtins ${_rt_cand}")
        else()
            message(FATAL_ERROR
                "node port: compiler-rt builtins not found at ${_rt_cand} "
                "(--print-resource-dir = ${_clang_resource_dir}). A consumer link "
                "would fail on __cpu_model; check the clang-cl installation.")
        endif()
    else()
        message(FATAL_ERROR "node port: clang-cl --print-resource-dir returned nothing (${_node_cc})")
    endif()
    unset(_clang_resource_dir)
    unset(_rt_cand)
else()
    find_program(_node_c_prog NAMES cc gcc clang)
    find_program(_node_cxx_prog NAMES c++ g++ clang++)
    set(_node_cc "${_node_c_prog}")
    set(_node_cxx "${_node_cxx_prog}")
    set(ENV{PKG_CONFIG} "pkg-config")
endif()

# shlex eats backslashes: CC/CXX and PKG_CONFIG use forward slashes.
set(ENV{CC} "${_node_cc}")
set(ENV{CXX} "${_node_cxx}")

# ---------------------------------------------------------------------------
# Apple: system frameworks the static archives drag in.
#
# abseil's time_zone reaches CoreFoundation (cctz), and Node.js's own certificate
# gathering reaches Security. Upstream states both in node.gyp's `libraries` for
# its own build, but the way a consumer links this port is through the exported
# CMake config, which is a different link line - so they have to be stated here
# too, for the port's own host tools (LDFLAGS) and for consumers (the config).
#
# The ninja generator reads LDFLAGS / LDFLAGS_host from the environment when gyp
# runs, which is inside configure.py, so setting them here is enough. The build
# loop below re-states them per configuration, because the shared-linkage rpath
# it adds differs between the release and the debug tree.
#
# VCPKG_TARGET_IS_OSX rather than APPLE: in port script mode a bare APPLE is
# ambiguous about target versus host, and vcpkg says so on every configure.
# ---------------------------------------------------------------------------
if(VCPKG_TARGET_IS_OSX)
    set(_node_ldflags_base "-framework CoreFoundation -framework Security")
else()
    set(_node_ldflags_base "")
endif()

# ---------------------------------------------------------------------------
# The Node.js crates target is built from Rust. The port only needs cargo on
# PATH; it is not something vcpkg can acquire.
# ---------------------------------------------------------------------------
find_program(_node_cargo NAMES cargo)
if(NOT _node_cargo)
    foreach(_cargo_hint
            "$ENV{USERPROFILE}/.cargo/bin/cargo.exe"
            "$ENV{HOME}/.cargo/bin/cargo.exe"
            "$ENV{HOME}/.cargo/bin/cargo"
            "C:/Users/$ENV{USERNAME}/.cargo/bin/cargo.exe")
        if(EXISTS "${_cargo_hint}")
            set(_node_cargo "${_cargo_hint}")
            get_filename_component(_cargo_dir "${_cargo_hint}" DIRECTORY)
            set(ENV{PATH} "${_cargo_dir};$ENV{PATH}")
            break()
        endif()
    endforeach()
endif()
if(NOT _node_cargo)
    message(FATAL_ERROR
        "node port: cargo is required to build Node.js's Temporal C API "
        "(deps/crates). Install a Rust toolchain and make sure cargo is on PATH.")
endif()
message(STATUS "node port: cargo = ${_node_cargo}")
