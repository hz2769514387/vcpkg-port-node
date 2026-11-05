vcpkg_download_distfile(
    ARCHIVE
    URLS "https://github.com/unicode-org/icu/releases/download/release-${VERSION}/icu4c-${VERSION}-sources.tgz"
    FILENAME "icu4c-${VERSION}-sources.tgz"
    SHA512 04A49455E1489030C520A4BFD2664FA2171E7938D08F2ACDBBCB1FDA976639FD8B1F0704F2EEC89BA59A7B6D118CEAAB6EC5A096E40D9085A0895D91CE225245
)

vcpkg_extract_source_archive(SOURCE_PATH
    ARCHIVE "${ARCHIVE}"
    PATCHES
        # Node.js's own two-line fix for the era fallback: when eras/wide is missing from the
        # data, the old code restored the failing status and carried on, which leaves the era
        # arrays in a state its destructor does not survive (issue #27).
        dtfmtsym-eras-status.patch
        # locid.cpp builds a LocaleKey with a member offset; clang rejects offsetof on a
        # non-standard-layout type outside the GNU extension, and ICU 78.3 only builds this file
        # with clang through that path.
        locid-clang-offsetof.patch
        disable-static-prefix.patch # https://gitlab.kitware.com/cmake/cmake/-/issues/16617; also mingw.
        fix_bsd_and_solaris.patch
        fix_parallel_build_on_windows.patch
        fix-python-path-with-spaces.patch
        fix-using-install-sh.diff
        mh-darwin.patch
        mh-mingw.patch
        mh-msys-msvc.patch
        subdirs.patch
        vcpkg-cross-data.patch
)

vcpkg_find_acquire_program(PYTHON3)
set(ENV{PYTHON} "${PYTHON3}")

vcpkg_list(SET CONFIGURE_OPTIONS)
vcpkg_list(SET BUILD_OPTIONS)

if(VCPKG_TARGET_IS_EMSCRIPTEN)
    vcpkg_list(APPEND CONFIGURE_OPTIONS --disable-extras icu_cv_host_frag=mh-linux)
    vcpkg_list(APPEND BUILD_OPTIONS "\"PKGDATA_OPTS=--without-assembly -O ../data/icupkg.inc\"")
elseif(VCPKG_TARGET_IS_UWP)
    vcpkg_list(APPEND CONFIGURE_OPTIONS --disable-extras ac_cv_func_tzset=no ac_cv_func__tzset=no)
    string(APPEND VCPKG_C_FLAGS " -DU_PLATFORM_HAS_WINUWP_API=1")
    string(APPEND VCPKG_CXX_FLAGS " -DU_PLATFORM_HAS_WINUWP_API=1")
    vcpkg_list(APPEND BUILD_OPTIONS "\"PKGDATA_OPTS=--windows-uwp-build -O ../data/icupkg.inc\"")
elseif(VCPKG_TARGET_IS_OSX AND VCPKG_LIBRARY_LINKAGE STREQUAL "dynamic")
    vcpkg_list(APPEND CONFIGURE_OPTIONS --enable-rpath)
    if(DEFINED CMAKE_INSTALL_NAME_DIR)
        vcpkg_list(APPEND BUILD_OPTIONS "ID_PREFIX=${CMAKE_INSTALL_NAME_DIR}")
    endif()
endif()

if(VCPKG_TARGET_IS_WINDOWS AND NOT VCPKG_TARGET_IS_MINGW)
    list(APPEND CONFIGURE_OPTIONS ac_cv_lib_m_floor=no)
endif()

# Windows: ICU is compiled by clang-cl, and this block is why.
#
# A cl.exe-built ICU aborts a clang-cl Debug process the first time it formats a date (issue #27;
# the minimal reproducer links ICU alone, with no Node.js in it). Node.js itself and every
# consumer this repository tests are clang-cl, so ICU joins them - the same move ADR 0009 made for
# OpenSSL, and for the same reason: a library compiled by the other compiler is not something the
# Debug CRT tolerates. The compiler is chosen here rather than by the triplet, so a consumer keeps
# a stock triplet.
#
# Two things have to be arranged for the autotools flow, which vcpkg-make drives:
#
#  * CC/CXX overrides. vcpkg-make writes the compiler it detected into CC/CXX, and
#    z_vcpkg_make_prepare_programs reads CC/CXX from the environment first ("Allows to overwrite
#    settings in custom triplets via the environment"). On a stock triplet that detected cl.exe,
#    so the environment names clang-cl; on a clang triplet it already detected clang-cl.
#
#  * INCLUDE/LIB/PATH. vcpkg loads vcvars for its MSVC triplets only, so a chainloaded clang-cl
#    triplet reaches the make flow with no headers, no libraries and no linker on the search path.
#    The triplet's toolchain assembles what vcvars would have set inside its own process; the
#    get-vars run records the environment it ends up with, and this process - the one that starts
#    the shell - sets it again. Environment variables arrive as whole strings, so the spaces in
#    "C:/Program Files/..." are not a problem; a flag carrying those paths is retokenized by the
#    msys shell and shatters (the reason this is not done with -imsvc and -libpath flags).
#
# --disable-extras: `make all` builds ICU's utility programs (uconv and the sample tools), which
# do not compile under clang-cl, and the delivered static libraries need none of them. The host
# build that a cross build uses is the exception: it is the one that asks for the `tools` feature,
# and on a stock triplet it stays on cl.exe so those tools exist.
#
# MinGW and UWP keep the compiler their triplets name: MinGW is gcc, and UWP has its own cl.exe
# flags (above). Neither is a cell this repository builds.
if(VCPKG_TARGET_IS_WINDOWS AND NOT VCPKG_TARGET_IS_MINGW AND NOT VCPKG_TARGET_IS_UWP)
    vcpkg_cmake_get_vars(_icu_cmake_vars_file)
    include("${_icu_cmake_vars_file}")
    if(VCPKG_DETECTED_ENV_INCLUDE AND VCPKG_DETECTED_ENV_LIB)
        set(ENV{INCLUDE} "${VCPKG_DETECTED_ENV_INCLUDE}")
        set(ENV{LIB} "${VCPKG_DETECTED_ENV_LIB}")
        set(ENV{PATH} "${VCPKG_DETECTED_ENV_PATH}")
    elseif(TARGET_TRIPLET MATCHES "clang")
        message(FATAL_ERROR
            "icu overlay: triplet '${TARGET_TRIPLET}' builds with clang-cl but reported an empty "
            "INCLUDE/LIB, so the MSVC/UCRT headers and libraries would not be on any search path. "
            "A clang-cl triplet has to bring the environment vcvars would have set (issue #34).")
    endif()

    if(TARGET_TRIPLET MATCHES "clang")
        list(APPEND CONFIGURE_OPTIONS --disable-extras)
        # ICU's own Windows platform file (mh-msys-msvc) writes lib.exe's spelling into every
        # Makefile: AR_OUTOPT = -OUT:, and Makefile.inc starts ARFLAGS with "cr". ar-lib
        # translates both for lib.exe, but a clang-cl triplet archives with llvm-ar, which takes
        # GNU ar's options: "-OUT:icudt.lib" makes it print its help and exit 0 without writing
        # the archive (measured, issue #34). These are ICU's variables, not vcpkg-make's, so the
        # override belongs here and only in this branch.
        list(APPEND BUILD_OPTIONS "AR_OUTOPT=" "ARFLAGS=cr")
        message(STATUS "icu overlay: clang-cl triplet, INCLUDE/LIB carried over from the toolchain")
    elseif(NOT "tools" IN_LIST FEATURES)
        list(APPEND CONFIGURE_OPTIONS --disable-extras)
        # clang-cl lives in a directory with spaces, and a configure variable is expanded unquoted
        # by the make shell - so the directory goes on PATH and the bare name into CC/CXX.
        set(_icu_clang_cl "")
        set(_icu_vswhere "")
        foreach(_cand
            "C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
            "C:/Program Files/Microsoft Visual Studio/Installer/vswhere.exe")
            if(EXISTS "${_cand}")
                set(_icu_vswhere "${_cand}")
                break()
            endif()
        endforeach()
        unset(_cand)
        if(_icu_vswhere)
            execute_process(COMMAND "${_icu_vswhere}" -latest -products * -property installationPath
                            OUTPUT_VARIABLE _icu_vs_path OUTPUT_STRIP_TRAILING_WHITESPACE
                            RESULT_VARIABLE _icu_vs_result)
            if(_icu_vs_result EQUAL 0 AND _icu_vs_path)
                # $ENV{PROCESSOR_ARCHITECTURE}, not CMAKE_HOST_SYSTEM_PROCESSOR: a port script
                # runs before any project() and the latter is empty here (ADR 0009, run 39236163698).
                set(_icu_host_arch "$ENV{PROCESSOR_ARCHITECTURE}")
                if(_icu_host_arch MATCHES "^(ARM64|arm64|aarch64)$")
                    set(_icu_llvm_archs ARM64 x64)
                else()
                    set(_icu_llvm_archs x64 ARM64)
                endif()
                foreach(_arch IN LISTS _icu_llvm_archs)
                    if(EXISTS "${_icu_vs_path}/VC/Tools/Llvm/${_arch}/bin/clang-cl.exe")
                        set(_icu_clang_cl "${_icu_vs_path}/VC/Tools/Llvm/${_arch}/bin/clang-cl.exe")
                        break()
                    endif()
                endforeach()
                unset(_icu_llvm_archs)
                unset(_arch)
            endif()
            unset(_icu_vs_path)
            unset(_icu_vs_result)
        endif()
        unset(_icu_vswhere)
        if(NOT _icu_clang_cl)
            message(FATAL_ERROR
                "icu overlay: clang-cl not found. A cl.exe-built ICU aborts a clang-cl Debug process "
                "(issue #27), so this port refuses to fall back to cl.exe. Install Visual Studio's "
                "'C++ Clang compiler' component, or point the build at a triplet that ships one.")
        endif()
        message(STATUS "icu overlay: building with ${_icu_clang_cl} (issue #27)")
        get_filename_component(_icu_clang_dir "${_icu_clang_cl}" DIRECTORY)
        vcpkg_add_to_path(PREPEND "${_icu_clang_dir}")
        unset(_icu_clang_dir)
        set(ENV{CC} "compile clang-cl.exe")
        set(ENV{CXX} "compile clang-cl.exe")
        set(ENV{CPP} "compile clang-cl.exe -E")
        if(NOT VCPKG_CROSSCOMPILING)
            set(ENV{CC_FOR_BUILD} "compile clang-cl.exe")
            set(ENV{CPP_FOR_BUILD} "compile clang-cl.exe -E")
            set(ENV{CXX_FOR_BUILD} "compile clang-cl.exe")
        endif()
    endif()
endif()

if("tools" IN_LIST FEATURES)
  list(APPEND CONFIGURE_OPTIONS --enable-tools)
else()
  list(APPEND CONFIGURE_OPTIONS --disable-tools)
endif()
if(CMAKE_HOST_WIN32 AND VCPKG_TARGET_IS_MINGW AND NOT HOST_TRIPLET MATCHES "mingw")
    # Assuming no cross compiling because the host (windows) pkgdata tool doesn't
    # use the '/' path separator when creating compiler commands for mingw bash.
elseif(VCPKG_CROSSCOMPILING)
    set(TOOL_PATH "${CURRENT_HOST_INSTALLED_DIR}/tools/${PORT}")
    # convert to unix path
    string(REGEX REPLACE "^([a-zA-Z]):/" "/\\1/" _VCPKG_TOOL_PATH "${TOOL_PATH}")
    list(APPEND CONFIGURE_OPTIONS "--with-cross-build=${_VCPKG_TOOL_PATH}")
endif()

vcpkg_make_configure(
    SOURCE_PATH "${SOURCE_PATH}/source"
    DISABLE_MSVC_TRANSFORMATIONS
    # AUTORECONF # needs Autoconf version 2.72
    OPTIONS
        ${CONFIGURE_OPTIONS}
        --disable-samples
        --disable-tests
        --disable-layoutex
    OPTIONS_RELEASE
        --disable-debug
        --enable-release
    OPTIONS_DEBUG
        --enable-debug
        --disable-release
)
vcpkg_make_install(OPTIONS ${BUILD_OPTIONS})

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/share"
    "${CURRENT_PACKAGES_DIR}/debug/share"
    "${CURRENT_PACKAGES_DIR}/lib/icu"
    "${CURRENT_PACKAGES_DIR}/debug/lib/icu"
    "${CURRENT_PACKAGES_DIR}/debug/lib/icud")

file(GLOB TEST_LIBS
    "${CURRENT_PACKAGES_DIR}/lib/*test*"
    "${CURRENT_PACKAGES_DIR}/debug/lib/*test*")
if(TEST_LIBS)
    file(REMOVE ${TEST_LIBS})
endif()

if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
    # force U_STATIC_IMPLEMENTATION macro
    foreach(HEADER utypes.h utf_old.h platform.h)
        vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/unicode/${HEADER}" "defined(U_STATIC_IMPLEMENTATION)" "1")
    endforeach()
endif()

# Install executables from /tools/icu/sbin to /tools/icu/bin on unix (/bin because icu require this for cross compiling)
if(VCPKG_TARGET_IS_LINUX OR VCPKG_TARGET_IS_OSX AND "tools" IN_LIST FEATURES)
    vcpkg_copy_tools(
        TOOL_NAMES icupkg gennorm2 gencmn genccode gensprep
        SEARCH_DIR "${CURRENT_PACKAGES_DIR}/tools/icu/sbin"
        DESTINATION "${CURRENT_PACKAGES_DIR}/tools/${PORT}/bin"
    )
endif()

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/tools/icu/sbin"
    "${CURRENT_PACKAGES_DIR}/tools/icu/debug")

# To cross compile, we need some files at specific positions. So lets copy them
file(GLOB CROSS_COMPILE_DEFS "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/config/icucross.*")
file(INSTALL ${CROSS_COMPILE_DEFS} DESTINATION "${CURRENT_PACKAGES_DIR}/tools/${PORT}/config")

if(VCPKG_TARGET_IS_WINDOWS)
    string(REGEX MATCH "^[0-9]*" ICU_VERSION_MAJOR "${VERSION}")
    file(GLOB RELEASE_DLLS "${CURRENT_PACKAGES_DIR}/lib/*icu*${ICU_VERSION_MAJOR}.dll")
    file(COPY ${RELEASE_DLLS} DESTINATION "${CURRENT_PACKAGES_DIR}/tools/${PORT}/bin")

    # copy dlls
    file(GLOB RELEASE_DLLS "${CURRENT_PACKAGES_DIR}/lib/*icu*${ICU_VERSION_MAJOR}.dll")
    file(COPY ${RELEASE_DLLS} DESTINATION "${CURRENT_PACKAGES_DIR}/bin")
    if(NOT VCPKG_BUILD_TYPE)
        file(GLOB DEBUG_DLLS "${CURRENT_PACKAGES_DIR}/debug/lib/*icu*${ICU_VERSION_MAJOR}.dll")
        file(COPY ${DEBUG_DLLS} DESTINATION "${CURRENT_PACKAGES_DIR}/debug/bin")
    endif()

    # remove any remaining dlls in /lib
    file(GLOB DUMMY_DLLS "${CURRENT_PACKAGES_DIR}/lib/*.dll" "${CURRENT_PACKAGES_DIR}/debug/lib/*.dll")
    if(DUMMY_DLLS)
        file(REMOVE ${DUMMY_DLLS})
    endif()

    vcpkg_copy_pdbs()
endif()

vcpkg_fixup_pkgconfig()
set(cxx_link_libraries "")
if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
    block(PROPAGATE cxx_link_libraries)
        vcpkg_cmake_get_vars(cmake_vars_file)
        include("${cmake_vars_file}")
        list(REMOVE_ITEM VCPKG_DETECTED_CMAKE_CXX_IMPLICIT_LINK_LIBRARIES ${VCPKG_DETECTED_CMAKE_C_IMPLICIT_LINK_LIBRARIES})
        list(TRANSFORM VCPKG_DETECTED_CMAKE_CXX_IMPLICIT_LINK_LIBRARIES REPLACE "^([^/]+)\$" "-l\\1")
        string(JOIN " " cxx_link_libraries ${VCPKG_DETECTED_CMAKE_CXX_IMPLICIT_LINK_LIBRARIES})
    endblock()
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/lib/pkgconfig/icu-uc.pc" "baselibs = " "baselibs = ${cxx_link_libraries} ")
    if(NOT VCPKG_BUILD_TYPE)
        vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig/icu-uc.pc" "baselibs = " "baselibs = ${cxx_link_libraries} ")
    endif()
endif()

vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/tools/icu/bin/icu-config" "${CURRENT_INSTALLED_DIR}" "`dirname $0`/../../../" IGNORE_UNCHANGED)
vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/tools/icu/bin/icu-config" "${CURRENT_HOST_INSTALLED_DIR}" "`dirname $0`/../../../../${_HOST_TRIPLET}/" IGNORE_UNCHANGED)

configure_file("${CMAKE_CURRENT_LIST_DIR}/vcpkg-cmake-wrapper.cmake" "${CURRENT_PACKAGES_DIR}/share/${PORT}/vcpkg-cmake-wrapper.cmake" @ONLY)
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
