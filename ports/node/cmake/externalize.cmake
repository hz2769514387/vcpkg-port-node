# Externalization: which vcpkg package stands in for which vendored dependency, and how its
# name, includes and libraries are handed to configure.py as --shared-* arguments.
#
# Owns: _node_shared_args(), one function that produces the argument list for a configuration,
# and the per-dependency wiring underneath it.
#
# Expects from the portfile: CURRENT_INSTALLED_DIR, VCPKG_TARGET_IS_*, and the linkage.

# ---------------------------------------------------------------------------
# 1) Feed vcpkg's dependencies to configure.py as --shared-*.
#    Library names are the real file names in the vcpkg package. On Windows
#    static there are a few differences (zlib -> zs, brotli without the lib
#    prefix, openssl keeps it). pkg-config does not exist on Windows, so the
#    library list has to be passed explicitly or nothing is added to the link
#    line at all.
#
#    Debug builds must link the dependencies' debug libraries, otherwise
#    _ITERATOR_DEBUG_LEVEL does not match.
# ---------------------------------------------------------------------------
function(_node_shared_args _out _libdir _is_debug)
    # Filled while the options are built and reported once at the end, so one run
    # names every wrong library name instead of the first.
    set(_missing_report "")
    set(_present_txt "")
    if(VCPKG_TARGET_IS_WINDOWS)
        # This repository's zlib overlay installs the Chromium fork as `zs.lib`
        # when it is built statically and as `zlib.lib` when it is built as a
        # DLL (it renames the static output to keep it from colliding with the
        # registry port's file). configure.py needs the real file name, so the
        # name follows the linkage rather than being a constant - hard-coding
        # `zs` is what made a shared libnode fail with
        # `LINK : fatal error LNK1181: cannot open input file 'zs.lib'`.
        # The fork's own CMakeLists: shared is OUTPUT_NAME z, static is
        # z${zlib_static_suffix} (zs on Windows). gyp appends the debug `d`
        # itself, so what is handed over is always the release stem.
        if(_node_shared_build)
            set(_zlib_lib    "z")
        else()
            set(_zlib_lib    "zs")
        endif()
        set(_openssl_lib "libcrypto,libssl")
        # vcpkg's libuv names its Windows output after the linkage: the static
        # archive is target uv_a with OUTPUT_NAME "uv" and PREFIX "lib", which
        # is libuv.lib, while the dynamic build's import library is target uv
        # with OUTPUT_NAME "uv" and no prefix - plain uv.lib. Unix is uv in
        # both linkages. Hard-coding libuv for Windows is what made every
        # *-windows (dynamic) leg fail the up-front name check below with
        # "libuv ... not in .../lib".
        if(_node_shared_build)
            set(_libuv_lib   "uv")
        else()
            set(_libuv_lib   "libuv")
        endif()
        set(_absl_prefix "absl_")
        set(_absl_suffix ".lib")
        set(_hwy_lib     "hwy")
        # vcpkg's spdlog and fmt add the usual debug postfix.
        if(_is_debug)
            set(_spdlog_lib "spdlogd")
            set(_fmt_lib    "fmtd")
        else()
            set(_spdlog_lib "spdlog")
            set(_fmt_lib    "fmt")
        endif()
        # bcrypt exists on Windows only - it is mbedtls's Windows entropy source
        # (BCryptGenRandom), and LIEF's own CMake links it under if(WIN32) for
        # the same reason. On Unix mbedtls reads /dev/urandom and needs nothing.
        set(_lief_libs "LIEF,${_spdlog_lib},${_fmt_lib},mbedx509,tfpsacrypto,bcrypt")
    else()
        set(_zlib_lib    "z")
        set(_openssl_lib "crypto,ssl")
        set(_libuv_lib   "uv")
        # The CI triplets on Unix are release-only, so only the release names
        # are exercised there; the debug postfix is a CMake-level convention
        # that holds on Unix too, but that combination is unverified.
        if(_is_debug)
            set(_spdlog_lib "spdlogd")
            set(_fmt_lib    "fmtd")
        else()
            set(_spdlog_lib "spdlog")
            set(_fmt_lib    "fmt")
        endif()
        set(_lief_libs "LIEF,${_spdlog_lib},${_fmt_lib},mbedx509,tfpsacrypto")
        set(_absl_prefix "libabsl_")
        set(_absl_suffix ".a")
        set(_hwy_lib     "hwy")
    endif()

    # abseil is split into ~90 archives; Node's own pkg-config list names only
    # part of them, so take every installed name. Two shapes that are not that one:
    #
    #   * Windows with a dynamic triplet. vcpkg's abseil port leaves
    #     ABSL_BUILD_MONOLITHIC_SHARED_LIBS at MSVC's default, which is ON, so the only
    #     library installed is abseil_dll.lib - there is no absl_mutex.lib and no absl_*.lib
    #     of any kind. The glob below therefore found nothing, the list went out empty, the
    #     precheck further down had no name to complain about, and the first host tool to
    #     link v8_libbase died with LNK2019 on absl::lts_*::Mutex. Measured on
    #     x64-windows-release.
    #   * POSIX. abseil there is static-only (vcpkg_check_linkage(ONLY_STATIC_LIBRARY) in its
    #     portfile), so the component archives are libabsl_*.a no matter what libnode's own
    #     linkage is.
    if(VCPKG_TARGET_IS_WINDOWS AND VCPKG_LIBRARY_LINKAGE STREQUAL "dynamic")
        set(_absl_libnames "abseil_dll")
    else()
        file(GLOB _absl_files RELATIVE "${_libdir}" "${_libdir}/${_absl_prefix}*${_absl_suffix}")
        set(_absl_libnames "")
        foreach(_f IN LISTS _absl_files)
            get_filename_component(_f "${_f}" NAME_WE)
            string(REGEX REPLACE "^lib" "" _f "${_f}")
            list(APPEND _absl_libnames "${_f}")
        endforeach()
        unset(_absl_files)
        unset(_f)
    endif()
    # An empty list is otherwise silent: the precheck only complains about names it was
    # given, and a build that never linked abseil fails much later and somewhere else.
    # abseil is not optional - --shared-abseil is always passed - so an empty list is a
    # defect in this file, not a consumer problem.
    if(NOT _absl_libnames)
        file(GLOB _present "${_libdir}/*")
        message(FATAL_ERROR
            "node port: no abseil libraries found under '${_libdir}' (looked for "
            "${_absl_prefix}*${_absl_suffix}). abseil is externalized unconditionally, so "
            "the build cannot proceed without it. What that directory holds:\n  ${_present}")
    endif()
    list(JOIN _absl_libnames "," _absl_libnames)

    # hdr-histogram's own CMake names the static library hdr_histogram_static and
    # the shared one hdr_histogram - the _static suffix is a linkage convention,
    # not part of the name. Which one exists depends on two separate decisions:
    #
    #   * Windows: the overlay forces a static library on every triplet (the
    #     upstream build's DLL is not used here), so it is always the suffixed
    #     name - and a dynamic triplet holding a shared libnode is exactly the
    #     case that made the precheck want hdr_histogram.lib;
    #   * everywhere else the overlay leaves the choice to the triplet, so a
    #     dynamic triplet installs libhdr_histogram.so with the version suffix
    #     and a static one installs libhdr_histogram_static.a.
    #
    # Keyed off the triplet, not off libnode's own linkage: the package's
    # linkage is the triplet's business.
    if(VCPKG_TARGET_IS_WINDOWS)
        set(_hdrhist_lib "hdr_histogram_static")
    elseif(VCPKG_LIBRARY_LINKAGE STREQUAL "dynamic")
        set(_hdrhist_lib "hdr_histogram")
    else()
        set(_hdrhist_lib "hdr_histogram_static")
    endif()
    set(_args "")
    foreach(_spec
        "openssl|${_openssl_lib}"
        "zlib|${_zlib_lib}"
        "libuv|${_libuv_lib}"
        "cares|cares"
        "brotli|brotlidec,brotlienc,brotlicommon"
        "nghttp2|nghttp2"
        "ngtcp2|ngtcp2"
        # vcpkg's nghttp3 port devendors sfparse (001-devendor-sfparse.patch) and
        # its own libnghttp3.pc carries "Libs.private: -lsfparse", so the static
        # library leaves sfparse_* undefined: the link line needs it as well.
        # Order matters - nghttp3 references sfparse, not the other way round.
        "nghttp3|nghttp3,sfparse"
        "http-parser|llhttp"
        "zstd|zstd"
        "simdjson|simdjson"
        "simdutf|simdutf"
        "sqlite|sqlite3"
        "ada|ada"
        "hdr-histogram|${_hdrhist_lib}"
        "abseil|${_absl_libnames}"
        "highway|${_hwy_lib}"
        "ffi|ffi"
        # perfetto is deliberately absent: --shared-perfetto is gated on
        # --with-perfetto in configure.py, and enabling it trips a V8 gyp gap
        # in the shared-SDK path (v8_libplatform loses trace-object.cc from its
        # source list while legacy tracing members still reference
        # TraceObject::~TraceObject, so mksnapshot fails to link). perfetto
        # tracing is an opt-in embedder feature that Node's own release build
        # does not enable, so the channel stays unwired until that is fixed;
        # ports/perfetto is ready and the issue is written up in docs.
        # "perfetto|perfetto"
        # LIEF is a C++ static library whose own TUs use spdlog (which is built
        # against external fmt) and mbedtls directly, so a consumer has to put
        # the providers after it on the link line - exactly what LIEFConfig.cmake
        # does for CMake consumers through find_dependency. Order: consumers
        # first, providers later (mbedx509 references tfpsacrypto symbols).
        # The exact chain is platform-dependent (bcrypt is Windows-only), see
        # _lief_libs above; LIEF, mbedtls and bcrypt keep their names in the
        # debug tree while spdlog/fmt carry the d postfix.
        "lief|${_lief_libs}")
        string(REPLACE "|" ";" _pair "${_spec}")
        list(GET _pair 0 _opt)
        list(GET _pair 1 _libnames)
        # A name that is wrong here surfaces as LNK1181 "cannot open input file"
        # several thousand lines later, once every dependency has been built and
        # the first host tool is linked - an hour into a leg, and the message
        # names neither the dependency nor what was expected. Checking the names
        # against the directory they came from costs nothing and fails in
        # seconds with the missing names and what is actually there.
        # _libnames is comma-separated because that is the separator
        # --shared-<dep>-libname takes; CMake needs semicolons to iterate it.
        #
        # Not every name on the link line is a vcpkg library: LIEF's list ends
        # with bcrypt, which is mbedtls's Windows entropy source and lives in
        # the SDK rather than in the install prefix. The first run with this
        # check proved it by demanding bcrypt from a directory that has never
        # held it.
        set(_node_sdk_libs
            bcrypt ntdll winmm ws2_32 crypt32 advapi32 user32 kernel32
            dbghelp iphlpapi ole32 shell32 secur32 cryptui)
        set(_missing "")
        string(REPLACE "," ";" _libnames_list "${_libnames}")
        foreach(_n IN LISTS _libnames_list)
            if(_n IN_LIST _node_sdk_libs)
                continue()
            endif()
            if(VCPKG_TARGET_IS_WINDOWS)
                set(_candidates "${_libdir}/${_n}.lib")
                # gyp appends the debug `d` itself, so the debug tree holds
                # zsd.lib for a name of zs. Accepting only the bare stem here
                # would reject the Debug build that already works.
                if(_is_debug)
                    list(APPEND _candidates "${_libdir}/${_n}d.lib")
                endif()
            else()
                set(_candidates "${_libdir}/lib${_n}.a"
                                "${_libdir}/lib${_n}.so"
                                "${_libdir}/lib${_n}.dylib")
            endif()
            file(GLOB _hit ${_candidates})
            if(NOT _hit)
                # Collected rather than reported here: this check has cost one CI
                # round per wrong name (zlib, then libuv, then hdr-histogram),
                # because each round reported only the first option it tripped over
                # and the next round then failed on the next one. One pass over every
                # option, one report.
                list(APPEND _missing "${_n}")
            endif()
            unset(_hit)
            unset(_candidates)
        endforeach()
        unset(_n)
        if(_missing)
            foreach(_m IN LISTS _missing)
                string(APPEND _missing_report "\n  --shared-${_opt}-libname ${_m}")
            endforeach()
            unset(_m)
            if(NOT _present_txt)
                file(GLOB _present "${_libdir}/*")
                list(TRANSFORM _present REPLACE "^.*/" "")
                list(LENGTH _present _present_count)
                if(_present_count GREATER 60)
                    list(SUBLIST _present 0 60 _present)
                    list(APPEND _present "...")
                endif()
                string(REPLACE ";" "\n  " _present_txt "${_present}")
                unset(_present)
                unset(_present_count)
            endif()
        endif()
        unset(_missing)
        list(APPEND _args
            "--shared-${_opt}"
            "--shared-${_opt}-includes=${CURRENT_INSTALLED_DIR}/include"
            "--shared-${_opt}-libpath=${_libdir}"
            "--shared-${_opt}-libname=${_libnames}")
    endforeach()
    unset(_spec)
    unset(_pair)
    unset(_opt)
    unset(_libnames)
    if(_missing_report)
        message(FATAL_ERROR
            "node port: these --shared-*-libname entries name libraries that are not in "
            "${_libdir}:${_missing_report}\n\n"
            "A wrong name here used to reach the linker as LNK1181 an hour later. "
            "What that directory actually holds:\n  ${_present_txt}")
    endif()
    unset(_missing_report)
    unset(_present_txt)
    set(${_out} "${_args}" PARENT_SCOPE)
endfunction()
