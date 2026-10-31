# Build: configure.py -> gyp -f ninja -> ninja, once per configuration.
#
# Owns: the per-configuration build directory, the environment the build runs with, the
# ninja invocation and its job count, and the failure reporting when a build stops.
#
# Expects from the portfile: _node_configs, SOURCE_PATH, and everything toolchain and
# externalize published.

# ---------------------------------------------------------------------------
# 2) Build loop: configure.py -> gyp -f ninja -> ninja, once per configuration.
# ---------------------------------------------------------------------------
set(_node_ninja_jobs "")
if(DEFINED VCPKG_CONCURRENCY AND NOT VCPKG_CONCURRENCY STREQUAL "")
    set(_node_ninja_jobs "-j${VCPKG_CONCURRENCY}")
endif()

set(_node_installed_libs "")

# LIB is *appended* to per configuration, on purpose, and it looks like a bug every time someone reads
# it. It is not: gyp builds the host tools (`mksnapshot`, `node_mksnapshot`, `torque`) with the release
# library spelling - `zs.lib`, not `zsd.lib` - while it points their /LIBPATH at `debug/lib`. `zs.lib`
# exists only in `lib/`, so during the Debug pass the release directory is the only place those names
# resolve, and setting LIB instead of appending turns `LNK4098` (the warning that made this look wrong)
# into `fatal error LNK1181: cannot open input file 'zs.lib'`. Measured; see the comment in #56.
#
# The warning itself is the price of "host tool compiled for the debug CRT, linking release-built
# dependency archives". It is a build-time tool that is never shipped, and `libnode` links cleanly in
# the same run.
foreach(_node_cfg IN LISTS _node_configs)
    if(_node_cfg STREQUAL "Debug")
        set(_node_cfg_arg "--debug")
        set(_node_is_debug TRUE)
        set(_node_lib_dir "${CURRENT_INSTALLED_DIR}/debug/lib")
        set(ENV{PKG_CONFIG_PATH} "${CURRENT_INSTALLED_DIR}/debug/lib/pkgconfig")
        set(ENV{LIB} "${_node_lib_dir};$ENV{LIB}")
    else()
        set(_node_cfg_arg "")
        set(_node_is_debug FALSE)
        set(_node_lib_dir "${CURRENT_INSTALLED_DIR}/lib")
        set(ENV{PKG_CONFIG_PATH} "${CURRENT_INSTALLED_DIR}/lib/pkgconfig")
        set(ENV{LIB} "${_node_lib_dir};$ENV{LIB}")
    endif()


    _node_shared_args(_node_shared_args "${_node_lib_dir}" "${_node_is_debug}")

    # -----------------------------------------------------------------------
    # Where the port's own host tools, and later the installed artifacts, find
    # the shared libraries they were linked against.
    #
    # A dynamic triplet makes every dependency a shared object, and two
    # consumers of them have nothing to help them:
    #
    # 1. The host tools (torque, mksnapshot, node_mksnapshot,
    #    bytecode_builtins_list_generator, ...) *run* during this build - they
    #    generate the sources everything else compiles - and they are linked
    #    against the dependencies. gyp puts them in the output root next to
    #    nothing that helps: the first one to run dies with "error while
    #    loading shared libraries: libada.so.4" (Linux) or "dyld: Library not
    #    loaded: @rpath/libz.1.3.2.1.dylib" (macOS), an hour into the leg and
    #    naming neither the tool nor the cause.
    # 2. The installed artifacts. The exported config links libnode itself and
    #    nothing else, so libnode.so has to find its dependencies on its own -
    #    they are installed next to it in <prefix>/lib - and the installed node
    #    executable has to find libnode, which sits in <prefix>/lib while the
    #    executable lives in <prefix>/tools/node.
    #
    # Both are answered with a *relative* rpath, never an absolute one: the
    # GitHub runner path shape (/home/runner/work/<repo>/<repo>/vcpkg/installed/
    # <triplet>/lib) is the same on every machine, so an absolute rpath would
    # not be inert on a consumer's machine - it would find whatever some other
    # build left at that path. A relative rpath names nothing and still works.
    #
    # The ninja generator writes LDFLAGS verbatim into build.ninja, and the
    # resulting command is run through sh. `$` is ninja's escape character and
    # sh would expand `$ORIGIN` to nothing, so a literal $ORIGIN only reaches
    # the linker if it is spelled `\$$ORIGIN` here (ninja: $$ -> $; sh: \$ ->
    # $). node.gyp spells its own rpath the same way. @loader_path has no `$`
    # and needs no such care.
    #
    # LDFLAGS_host is deliberately not used for the host tools: gyp's ninja
    # generator only honours a separate host toolset when cross-compiling
    # (gyp.common.CrossCompileRequested), and this port passes
    # --no-cross-compiling on every platform, so every link - host tools
    # included - is a target-toolset link that reads LDFLAGS.
    #
    # On Windows there is no rpath: the loader searches the executable's own
    # directory and then PATH, so the install tree's bin/ goes onto PATH for
    # the build. The host tools are never installed, and the consumer side
    # handles its own executables (node_test_runtime_libs in the test project).
    # -----------------------------------------------------------------------
    if(VCPKG_TARGET_IS_LINUX OR VCPKG_TARGET_IS_OSX)
        if(_node_shared_build)
            if(VCPKG_TARGET_IS_OSX)
                set(_node_ldflags_target
                    "${_node_ldflags_base} -Wl,-rpath,@loader_path -Wl,-rpath,@loader_path/../lib")
            else()
                set(_node_ldflags_target
                    "${_node_ldflags_base} -Wl,-rpath,\\$$ORIGIN -Wl,-rpath,\\$$ORIGIN/../lib")
            endif()
        else()
            set(_node_ldflags_target "${_node_ldflags_base}")
        endif()
        set(ENV{LDFLAGS} "${_node_ldflags_target}")
        set(ENV{LDFLAGS_host} "${_node_ldflags_base}")
    elseif(VCPKG_TARGET_IS_WINDOWS AND _node_shared_build)
        get_filename_component(_node_bin_dir "${_node_lib_dir}/../bin" ABSOLUTE)
        set(ENV{PATH} "${_node_bin_dir};$ENV{PATH}")
    endif()

    # --shared makes node.gyp build libnode as a shared_library and link the
    # node executable against it.
    if(_node_shared_build)
        set(_node_shared_build_arg "--shared")
    else()
        set(_node_shared_build_arg "")
    endif()

    # simdjson as a DLL needs a define on the consumer side, and gyp is a consumer that never
    # sees it: vcpkg's simdjson target carries SIMDJSON_USING_WINDOWS_DYNAMIC_LIBRARY=1 on its
    # INTERFACE, but the port links the library by name, so nothing propagates it. Two of the
    # globals node_base references from simdjson.h are *data*, and data has to be dllimport to
    # be reachable through an import library - measured as LNK2019 on
    # internal::error_codes and internal::structural_or_whitespace_negated, at
    # node_mksnapshot, and only on a dynamic Windows triplet.
    #
    # Handed over as an environment variable rather than an extra -D: -D does reach gyp (that
    # is how VCPKG_SIMDUTF_INCLUDE works, and it is forwarded verbatim), but a gyp condition
    # reading it produced no define, so patch 0023 has configure.py put it in
    # output['defines'] instead - the channel this port already uses for build-wide defines.
    # Only for a dynamic Windows triplet: with a static simdjson the macro would make the
    # compiler demand dllimport from an archive that has none.
    if(VCPKG_TARGET_IS_WINDOWS AND VCPKG_LIBRARY_LINKAGE STREQUAL "dynamic")
        set(ENV{NODE_PORT_SIMDJSON_USING_DLL} "1")
    else()
        unset(ENV{NODE_PORT_SIMDJSON_USING_DLL})
    endif()

    vcpkg_execute_required_process(
        COMMAND "${PYTHON3}" configure.py
            --ninja
            ${_node_cfg_arg}
            ${_node_clang_cl_arg}
            ${_node_shared_build_arg}
            ${_node_dest_cpu_args}
            --with-intl=system-icu
            ${_node_shared_args}
            "-DVCPKG_SIMDUTF_INCLUDE=${CURRENT_INSTALLED_DIR}/include"
        WORKING_DIRECTORY "${SOURCE_PATH}"
        LOGNAME "configure-${_node_cfg}"
    )

    # -----------------------------------------------------------------------
    # Shared linkage, Unix: put the dependencies where the host tools can load
    # them from.
    #
    # gyp puts every executable it links in the output root (out/<config>/)
    # and, on Linux, shared libraries one level down in lib/. The host tools
    # run from the output root and carry the relative rpath added above, so a
    # symlink per dependency name in the output root is all the loader needs
    # to find them: $ORIGIN / @loader_path already points there. lib/ gets
    # them too, because that is where libnode.so lives on Linux and where its
    # own $ORIGIN resolves - nothing loads it during this build, but a future
    # build step that does would otherwise fail the same silent way.
    #
    # Symlinks rather than copies: the libraries are hundreds of megabytes and
    # the build tree is transient. COPY_ON_ERROR covers a filesystem without
    # symlink support by falling back to a real copy.
    # -----------------------------------------------------------------------
    if(_node_shared_build AND (VCPKG_TARGET_IS_LINUX OR VCPKG_TARGET_IS_OSX))
        if(VCPKG_TARGET_IS_OSX)
            file(GLOB _node_shared_deps "${_node_lib_dir}/*.dylib")
        else()
            file(GLOB _node_shared_deps "${_node_lib_dir}/lib*.so*")
        endif()
        foreach(_node_out_subdir IN ITEMS "" "lib")
            set(_node_out_dir "${SOURCE_PATH}/out/${_node_cfg}")
            if(NOT _node_out_subdir STREQUAL "")
                set(_node_out_dir "${_node_out_dir}/${_node_out_subdir}")
                file(MAKE_DIRECTORY "${_node_out_dir}")
            endif()
            foreach(_node_dep IN LISTS _node_shared_deps)
                get_filename_component(_node_dep_name "${_node_dep}" NAME)
                file(CREATE_LINK "${_node_dep}"
                     "${_node_out_dir}/${_node_dep_name}"
                     SYMBOLIC COPY_ON_ERROR)
            endforeach()
            unset(_node_dep)
            unset(_node_dep_name)
            unset(_node_out_dir)
        endforeach()
        unset(_node_out_subdir)
        unset(_node_shared_deps)
    endif()

    # -----------------------------------------------------------------------
    # Windows shared: put the dependency DLLs where the tools are run from.
    #
    # The same problem the symlinks above solve on Unix, with a different answer: Windows has
    # no rpath, and the loader searches the executable's own directory before PATH. PATH alone
    # is not enough here, because gyp-win-tool's action-wrapper runs each action with the
    # environment it recorded at gyp time (`environment.x64`), so the PATH this port exports
    # does not reach it. Measured 2026-10-21: with the DLLs only in `<installed>/bin`,
    # `node_mksnapshot.exe` linked and then the snapshot action died with
    # 0xC0000135 (STATUS_DLL_NOT_FOUND) while generating `gen/node_snapshot.cc`, which ninja
    # reports as `FAILED: [code=3221225781] gen/node_snapshot.cc` and nothing else.
    #
    # A copy, not a link: Windows has no link the loader follows. These are the dependency
    # DLLs only (a few tens of megabytes); libnode.dll itself is produced into this directory
    # by the build.
    if(VCPKG_TARGET_IS_WINDOWS AND _node_shared_build)
        set(_node_out_dir "${SOURCE_PATH}/out/${_node_cfg}")
        # `bin/` and `lib/`: vcpkg's convention is bin/, but not every port follows it - LIEF
        # installs `lib/LIEF.dll` next to its import library, and LIEF is one of the libraries
        # node's snapshot tool imports. Measured with the dependents check below: of the 24 names
        # it reported, 23 were system DLLs and the one real finding was LIEF.dll, which the
        # `bin/`-only glob had never copied.
        file(GLOB _node_dep_dlls
             "${CURRENT_INSTALLED_DIR}/bin/*.dll"
             "${CURRENT_INSTALLED_DIR}/lib/*.dll")
        if(_node_dep_dlls)
            file(COPY ${_node_dep_dlls} DESTINATION "${_node_out_dir}")
        endif()
        # Say it out loud: the first version of this copy was silent, and the build failed with
        # the same 0xC0000135 afterwards, which left "the copy did not run" and "the copy ran and
        # the missing DLL is something else" indistinguishable. One line settles it.
        list(LENGTH _node_dep_dlls _node_dep_dll_count)
        message(STATUS
            "node port: ${_node_cfg} copied ${_node_dep_dll_count} dependency DLL(s) from "
            "${CURRENT_INSTALLED_DIR}/bin into ${_node_out_dir}")
        unset(_node_dep_dll_count)
        unset(_node_dep_dlls)
        unset(_node_out_dir)
    endif()

    # -----------------------------------------------------------------------
    # Windows shared: name the DLL that is missing, instead of reporting its absence.
    #
    # The snapshot action runs `node_mksnapshot.exe` and Windows reports a missing dependency
    # only as 0xC0000135 - `FAILED: [code=3221225781] gen/node_snapshot.cc` and nothing else.
    # Copying the 27 dependency DLLs into the output root did not fix it, and one line of
    # diagnostic was worth more than three rounds of guessing: build the tool on its own (it
    # links fine; it is *running* it that fails), then ask it what it imports and which of those
    # files are not where the loader looks.
    # -----------------------------------------------------------------------
    if(VCPKG_TARGET_IS_WINDOWS AND _node_shared_build)
        vcpkg_execute_required_process(
            COMMAND "${NINJA}" -C "${SOURCE_PATH}/out/${_node_cfg}" ${_node_ninja_jobs} node_mksnapshot
            WORKING_DIRECTORY "${SOURCE_PATH}"
            LOGNAME "mksnapshot-${_node_cfg}"
        )
        find_program(_node_dumpbin NAMES dumpbin)
        if(_node_dumpbin)
            execute_process(
                COMMAND "${_node_dumpbin}" /nologo /dependents
                        "${SOURCE_PATH}/out/${_node_cfg}/node_mksnapshot.exe"
                OUTPUT_VARIABLE _node_mksnapshot_deps
                ERROR_QUIET)
            string(REGEX MATCHALL "[A-Za-z0-9_.-]+[.]dll" _node_mksnapshot_dlls "${_node_mksnapshot_deps}")
            list(REMOVE_DUPLICATES _node_mksnapshot_dlls)
            set(_node_missing_dlls "")
            foreach(_node_dll IN LISTS _node_mksnapshot_dlls)
                if(NOT EXISTS "${SOURCE_PATH}/out/${_node_cfg}/${_node_dll}")
                    string(APPEND _node_missing_dlls " ${_node_dll}")
                endif()
            endforeach()
            if(_node_missing_dlls STREQUAL "")
                message(STATUS
                    "node port: ${_node_cfg} node_mksnapshot imports "
                    "${_node_mksnapshot_dlls}, all present in the output root")
            else()
                message(STATUS
                    "node port: ${_node_cfg} node_mksnapshot imports a DLL that is NOT in the "
                    "output root:${_node_missing_dlls} (system DLLs are expected in this list; "
                    "anything else is a dependency that was not copied)")
            endif()
            unset(_node_missing_dlls)
            unset(_node_mksnapshot_deps)
            unset(_node_mksnapshot_dlls)
        else()
            message(STATUS "node port: ${_node_cfg} dumpbin not found; cannot name the missing DLL")
        endif()
        unset(_node_dumpbin)
    endif()

    set(_node_ninja_targets libnode)
    if(_node_cfg STREQUAL "Release" AND "tools" IN_LIST FEATURES)
        list(APPEND _node_ninja_targets node)
    endif()

    vcpkg_execute_required_process(
        COMMAND "${NINJA}" -C "${SOURCE_PATH}/out/${_node_cfg}" ${_node_ninja_jobs} ${_node_ninja_targets}
        WORKING_DIRECTORY "${SOURCE_PATH}"
        LOGNAME "build-${_node_cfg}"
    )

    # -----------------------------------------------------------------------
    # Free this configuration's object files.
    #
    # Nothing after the link needs them: the archives the install step globs
    # are separate files in the same tree, the vendored-build check below
    # reads build.ninja and not the objects, and no step relinks. A
    # dual-configuration triplet builds both trees in one source directory,
    # so the second configuration starts with the first one's objects still
    # on disk - and a macOS x64 Debug leg ran out of space exactly there,
    # 1253 edges into the second build, with a message ("can't write to
    # output file (No space left on device)") that names neither the
    # configuration nor the cause. Deleting the objects costs nothing and is
    # what makes two trees fit on a runner that fits one.
    # -----------------------------------------------------------------------
    file(GLOB_RECURSE _node_config_objects
         "${SOURCE_PATH}/out/${_node_cfg}/obj/*.o"
         "${SOURCE_PATH}/out/${_node_cfg}/obj/*.obj")
    if(_node_config_objects)
        file(REMOVE ${_node_config_objects})
    endif()
    unset(_node_config_objects)

    # -----------------------------------------------------------------------
    # Ask the generated build graph whether any library this port externalizes
    # is *also* compiled from its vendored copy.
    #
    # The --shared-* switches remove dependency edges, but a target that pulls a
    # vendored gyp in unconditionally still compiles it - simdutf.gyp arrives
    # through ada.gyp that way, which is what patch 0011 had to gate. Nothing
    # downstream reports the result: the linker silently picks one definition and
    # the consumer finds out later, as an unexplained duplicate symbol. The graph
    # states every source it compiles, so one pass over it is the whole check.
    # -----------------------------------------------------------------------
    vcpkg_execute_required_process(
        COMMAND "${PYTHON3}" "${NODE_PORT_DIR}/check-no-vendored-build.py"
                --build-dir "${SOURCE_PATH}/out/${_node_cfg}"
        WORKING_DIRECTORY "${SOURCE_PATH}"
        LOGNAME "vendored-check-${_node_cfg}"
    )
endforeach()
