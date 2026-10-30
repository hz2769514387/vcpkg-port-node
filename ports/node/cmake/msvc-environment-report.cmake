# The closing decision of the MSVC environment probe, on its own so it can be exercised.
#
# Why this is a separate file: the three cases have three different right answers, and two of them can
# only be reached on a machine that is missing Visual Studio or missing its environment. Leaving the
# `if`/`elseif` at the end of msvc-environment.cmake meant those two answers were never executed by
# anything - not by this repository's CI, which always has a complete toolchain, and not by a
# developer, whose machine does too. As a function, `cmake -P` drives all three in milliseconds.
#
# The cases, in the order they are checked:
#
#   1. toolset and SDK resolved   -> STATUS; the probe did its job.
#   2. neither resolved, but
#      INCLUDE and LIB are
#      already in the process
#      environment                -> STATUS; that is the Visual Studio developer prompt path, and it
#                                    works. Warning there is a false alarm - the old code did exactly
#                                    that, and a message that fires when nothing is wrong is how the
#                                    one that matters gets ignored.
#   3. neither                    -> FATAL_ERROR. gyp's own failure for this case is
#                                    `ValueError: Could not locate Visual Studio installation.`
#                                    several hundred lines of ninja later, and it never says the port
#                                    looked for Visual Studio at all.

function(node_port_report_msvc_environment _root _sdk)
    if(NOT _root STREQUAL "" AND NOT _sdk STREQUAL "")
        message(STATUS "node port: MSVC command-line environment ready (MSVC ${_root}, Windows SDK ${_sdk})")
        return()
    endif()

    # Both halves matter. A resolved toolset with no SDK cannot find rc.exe or the Windows headers; a
    # resolved SDK with no toolset cannot find a compiler. The old code required both for the good
    # message and checked only the toolset for the bad one, so "toolset but no SDK" printed nothing.
    if(_root STREQUAL "" AND _sdk STREQUAL "")
        set(_missing "MSVC toolset or Windows SDK")
    elseif(_root STREQUAL "")
        set(_missing "MSVC toolset")
    else()
        set(_missing "Windows SDK")
    endif()

    if(NOT "$ENV{INCLUDE}" STREQUAL "" AND NOT "$ENV{LIB}" STREQUAL "")
        message(STATUS
            "node port: no ${_missing} found, but INCLUDE and LIB are already set in this process - "
            "using that environment. This is the Visual Studio developer command prompt path; it "
            "works as long as the prompt's environment is complete.")
        return()
    endif()

    message(FATAL_ERROR
        "node port: cannot build Node.js on Windows: no ${_missing} found, and this process has no "
        "INCLUDE/LIB to fall back on.\n"
        "  Looked for: vswhere.exe under ProgramFiles(x86), the path in VCPKG_VISUAL_STUDIO_PATH, "
        "and the Windows SDK under ProgramFiles(x86).\n"
        "  Without this, the build fails later inside gyp with 'Could not locate Visual Studio "
        "installation', which does not mention any of the above.\n"
        "  Either:\n"
        "    * set VCPKG_VISUAL_STUDIO_PATH to the Visual Studio root, for example\n"
        "      C:/Program Files/Microsoft Visual Studio/2022/Community, or\n"
        "    * run vcpkg from a Visual Studio developer command prompt, where INCLUDE and LIB are "
        "already set.")
endfunction()
