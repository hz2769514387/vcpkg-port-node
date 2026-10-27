# Install: what leaves the build tree and lands in the package.
#
# Owns: the headers, the gyp archives (and the shared library when the linkage is dynamic),
# compiler-rt's builtins archive, and the licence.
#
# Expects from the portfile: _node_configs, the build output directory, and the linkage.

# ---------------------------------------------------------------------------
# 3) Install headers, the gyp archives and compiler-rt.
# ---------------------------------------------------------------------------
file(INSTALL "${SOURCE_PATH}/src/" DESTINATION "${CURRENT_PACKAGES_DIR}/include/node"
    FILES_MATCHING PATTERN "*.h" PATTERN "*.hpp")
# V8's headers live under include/node-v8, not the include root: vcpkg's Unique
# File Mapping Rule forbids two ports installing the same file, and the official
# `v8` port installs include/v8.h. The consumer config adds this directory to
# the include path, so `#include <v8.h>` still resolves.
file(INSTALL "${SOURCE_PATH}/deps/v8/include/" DESTINATION "${CURRENT_PACKAGES_DIR}/include/node-v8")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/include/node/api" "${CURRENT_PACKAGES_DIR}/include/node/res")

if(VCPKG_TARGET_IS_WINDOWS)
    set(_node_lib_suffix ".lib")
else()
    set(_node_lib_suffix ".a")
endif()

# A shared libnode's file name carries the NODE_MODULE_VERSION on Unix. node.gyp
# sets `product_extension` to <(shlib_suffix) for a shared library off Windows,
# and configure.py fills that in with the module version: `libnode.147.dylib` on
# macOS, `libnode.so.147` on Linux. "libnode.dylib" and "libnode.so" are names
# the build never produces, which is what the first shared leg to reach the
# install step found out. The name is read out of the built tree once, from the
# Release configuration, and reused by the install step, the tools/ copy and the
# exported config, so nothing here has to track the module version itself.
if(_node_shared_build AND NOT VCPKG_TARGET_IS_WINDOWS)
    if(VCPKG_TARGET_IS_OSX)
        file(GLOB _node_shlib_candidates "${SOURCE_PATH}/out/Release/libnode*.dylib")
    else()
        file(GLOB _node_shlib_candidates "${SOURCE_PATH}/out/Release/lib/libnode.so*")
    endif()
    if(NOT _node_shlib_candidates)
        message(FATAL_ERROR
            "node port: the Release build produced no shared libnode under "
            "${SOURCE_PATH}/out/Release")
    endif()
    list(GET _node_shlib_candidates 0 _node_shlib_path)
    get_filename_component(_node_shlib_name "${_node_shlib_path}" NAME)
    unset(_node_shlib_candidates)
    unset(_node_shlib_path)

    # ---------------------------------------------------------------------------------
    # A shared libnode has to carry abseil, and this is the only place that is checkable.
    #
    # Off Windows, vcpkg's abseil is static-only, so there is no libabsl_*.so for the loader
    # to find: the archives must end up inside libnode. When they do not, the link still
    # *succeeds* - a shared library is allowed to leave symbols undefined - and the failure
    # appears at the consumer's link, two and a half hours into a leg, reading
    # "libnode.so.147: undefined reference to absl::lts_*::..." and pointing at the consumer
    # rather than at this port. That is exactly what the x64-linux-dynamic leg reported, and
    # nothing in the log above it named abseil once.
    #
    # Any undefined abseil symbol here is a defect by construction, so it is checked next to
    # the library. The refusal also reports whether the -labsl_* flags reached the gyp link
    # line at all, which is the first question the failure raises and the one the log cannot
    # answer: gyp's rsp file is only visible in build.ninja.
    # ---------------------------------------------------------------------------------
    find_program(_node_nm NAMES llvm-nm nm)
    if(NOT _node_nm)
        message(WARNING "node port: no nm found; cannot verify that abseil is inside libnode")
    else()
        foreach(_node_cfg IN LISTS _node_configs)
            if(_node_cfg STREQUAL "Debug")
                set(_node_cfg_out_dir "${SOURCE_PATH}/out/Debug")
            else()
                set(_node_cfg_out_dir "${SOURCE_PATH}/out/Release")
            endif()
            if(VCPKG_TARGET_IS_OSX)
                set(_node_cfg_shlib "${_node_cfg_out_dir}/${_node_shlib_name}")
                # Apple's nm has no -D; -u already means "undefined only", and a dylib's
                # undefined symbols are the external references either way.
                set(_node_nm_args -u)
            else()
                set(_node_cfg_shlib "${_node_cfg_out_dir}/lib/${_node_shlib_name}")
                # -D reads the dynamic symbol table, which survives stripping; a plain nm on
                # a stripped .so reports nothing at all and the check would pass by accident.
                set(_node_nm_args -D -u)
            endif()
            execute_process(
                COMMAND "${_node_nm}" ${_node_nm_args} "${_node_cfg_shlib}"
                OUTPUT_VARIABLE _node_undef
                ERROR_VARIABLE _node_undef_err
                RESULT_VARIABLE _node_undef_rc)
            if(NOT _node_undef_rc EQUAL 0)
                message(FATAL_ERROR
                    "node port: '${_node_nm} ${_node_nm_args}' failed on ${_node_cfg_shlib} "
                    "(${_node_undef_rc}), so the abseil check could not run: ${_node_undef_err}")
            endif()
            string(REGEX MATCHALL "[^\n]*(_ZN4absl|AbslInternal)[^\n]*" _node_absl_undef "${_node_undef}")
            if(_node_absl_undef)
                list(LENGTH _node_absl_undef _node_absl_undef_count)
                list(SUBLIST _node_absl_undef 0 5 _node_absl_undef_head)
                string(REPLACE ";" "\n  " _node_absl_undef_head "${_node_absl_undef_head}")
                # Two questions, asked separately because they have different answers.
                # 1) Did configure.py receive the names? configure.py writes config.gypi next
                #    to itself, in the source root - not in out/<config>/, which is where the
                #    first version of this looked and always reported "file-missing".
                set(_node_absl_in_gypi "file-missing")
                if(EXISTS "${SOURCE_PATH}/config.gypi")
                    file(READ "${SOURCE_PATH}/config.gypi" _node_gypi_txt)
                    if(_node_gypi_txt MATCHES "-labsl_")
                        set(_node_absl_in_gypi "yes")
                    else()
                        set(_node_absl_in_gypi "no")
                    endif()
                    unset(_node_gypi_txt)
                endif()
                # 2) Did gyp put them on a link line, and where? Every ninja file, not just
                #    build.ninja: gyp writes one per target, and the first version of this
                #    read build.ninja alone and reported a confident "no" for flags that were
                #    sitting in obj/cctest.ninja. The library's own edge is reported
                #    separately, because "the flags exist somewhere" and "the library that
                #    needs them has them" are different facts.
                set(_node_absl_in_ninja "")
                set(_node_absl_in_libnode "no libnode edge found")
                file(GLOB_RECURSE _node_ninja_files "${_node_cfg_out_dir}/*.ninja")
                foreach(_nf IN LISTS _node_ninja_files)
                    file(READ "${_nf}" _node_ninja_txt)
                    file(RELATIVE_PATH _node_ninja_hit "${_node_cfg_out_dir}" "${_nf}")
                    if(_node_ninja_txt MATCHES "-labsl_")
                        string(APPEND _node_absl_in_ninja " ${_node_ninja_hit}")
                    endif()
                    if(_node_ninja_hit MATCHES "libnode")
                        # "The file mentions -labsl_*" is not the question. gyp writes one file
                        # per target and it holds several edges, so the flags can be in the file
                        # and still miss the edge that links the library. Ask the `libs` lines
                        # specifically - that variable is what the solink rule expands - and
                        # quote the first one so the answer is visible rather than inferred.
                        string(REGEX MATCHALL "libs = [^\n]*" _node_libs_lines "${_node_ninja_txt}")
                        if(_node_libs_lines STREQUAL "")
                            set(_node_absl_in_libnode
                                "no libs line at all in ${_node_ninja_hit} (though the file itself carries -labsl_*)")
                        else()
                            set(_node_libs_hit "no")
                            foreach(_node_libs_line IN LISTS _node_libs_lines)
                                if(_node_libs_line MATCHES "-labsl_")
                                    set(_node_libs_hit "yes")
                                endif()
                            endforeach()
                            list(GET _node_libs_lines 0 _node_libs_first)
                            string(SUBSTRING "${_node_libs_first}" 0 160 _node_libs_first)
                            set(_node_absl_in_libnode
                                "${_node_libs_hit}, in ${_node_ninja_hit} - first libs line: ${_node_libs_first}")
                            unset(_node_libs_first)
                            unset(_node_libs_line)
                        endif()
                        unset(_node_libs_lines)
                        unset(_node_libs_hit)
                    endif()
                endforeach()
                if(_node_absl_in_ninja STREQUAL "")
                    set(_node_absl_in_ninja "no file carries them")
                endif()
                unset(_node_ninja_files)
                unset(_node_ninja_txt)
                unset(_node_ninja_hit)
                message(FATAL_ERROR
                    "node port: ${_node_cfg} libnode has ${_node_absl_undef_count} undefined "
                    "abseil symbols, so nothing provides them at run time - abseil is "
                    "static-only off Windows and has to be inside libnode.\n"
                    "First few:\n  ${_node_absl_undef_head}\n\n"
                    "abseil names in config.gypi (so configure.py did get them): "
                    "${_node_absl_in_gypi}\n"
                    "-labsl_* in libnode's own edge: ${_node_absl_in_libnode}\n"
                    "ninja files carrying -labsl_*:${_node_absl_in_ninja}\n\n"
                    "If config.gypi has them and no ninja file does, gyp dropped them; if "
                    "neither has them, --shared-abseil-libname arrived empty; if another "
                    "target has them but libnode's edge does not, the flags are not reaching "
                    "the shared library; if libnode's edge has them, they were on the link "
                    "line and the archives were not pulled in (look at the order relative to "
                    "the objects, and at the solink rule's -Wl,--whole-archive, which wraps "
                    "only the inputs, not the libraries).")
            endif()
            unset(_node_absl_undef)
            unset(_node_absl_undef_count)
            unset(_node_absl_undef_head)
            unset(_node_undef)
            unset(_node_undef_err)
            unset(_node_cfg_shlib)
            unset(_node_nm_args)
        endforeach()
        unset(_node_cfg_out_dir)
        unset(_node_absl_in_gypi)
        unset(_node_absl_in_ninja)
        unset(_node_ninja_hit)
    endif()
    unset(_node_nm)
endif()

foreach(_node_cfg IN LISTS _node_configs)
    if(_node_cfg STREQUAL "Debug")
        set(_node_out_dir "${SOURCE_PATH}/out/Debug")
        set(_node_pkg_lib_dir "${CURRENT_PACKAGES_DIR}/debug/lib")
        set(_node_pkg_bin_dir "${CURRENT_PACKAGES_DIR}/debug/bin")
    else()
        set(_node_out_dir "${SOURCE_PATH}/out/Release")
        set(_node_pkg_lib_dir "${CURRENT_PACKAGES_DIR}/lib")
        set(_node_pkg_bin_dir "${CURRENT_PACKAGES_DIR}/bin")
    endif()

    if(_node_shared_build)
        # Where gyp's ninja generator puts a shared_library, read out of
        # ComputeOutput (tools/gyp/pylib/gyp/generator/ninja.py): the output
        # root on Windows and macOS, lib/ on Linux. gyp names the Windows
        # import library "<dll>.lib", which is not a name anyone would guess.
        if(VCPKG_TARGET_IS_WINDOWS)
            set(_node_shlib "${_node_out_dir}/libnode.dll")
            set(_node_implib "${_node_shlib}.lib")
            file(INSTALL "${_node_shlib}" DESTINATION "${_node_pkg_bin_dir}")
            file(INSTALL "${_node_implib}" DESTINATION "${_node_pkg_lib_dir}")
        elseif(VCPKG_TARGET_IS_OSX)
            file(INSTALL "${_node_out_dir}/${_node_shlib_name}" DESTINATION "${_node_pkg_lib_dir}")
        else()
            file(INSTALL "${_node_out_dir}/lib/${_node_shlib_name}" DESTINATION "${_node_pkg_lib_dir}")
        endif()
        # Nothing else is a deliverable: the component archives are inputs the
        # shared library already absorbed, and linking them again from a
        # consumer would put a second copy of every symbol into the process.
        #
        # The library file itself is still what this port installed, and
        # node_INSTALLED_LIBRARIES has to say so: it is what the symbol audit in the
        # test project uses to tell this port's own files from everything else in
        # <prefix>/lib, and with an empty list that audit falls back to scanning the
        # whole directory - which in a dynamic triplet holds every dependency's static
        # archive, and reports the dependency against itself.
        if(_node_cfg STREQUAL "Release")
            if(VCPKG_TARGET_IS_WINDOWS)
                set(_node_installed_libs "libnode.dll.lib")
            else()
                set(_node_installed_libs "${_node_shlib_name}")
            endif()
        endif()
        unset(_node_shlib)
        unset(_node_implib)
        unset(_node_out_dir)
        unset(_node_pkg_lib_dir)
        unset(_node_pkg_bin_dir)
        continue()
    endif()

    # Windows/macOS: gyp puts static libraries under obj/ (recursively) and, on
    # macOS, static_library lands in the output root as well.  Rust crates
    # (node_crates) land under gen/ on Windows.
    file(GLOB_RECURSE _node_archives "${_node_out_dir}/obj/*${_node_lib_suffix}")
    file(GLOB _node_archives_root "${_node_out_dir}/*${_node_lib_suffix}")
    list(APPEND _node_archives ${_node_archives_root})
    file(GLOB_RECURSE _node_gen_archives "${_node_out_dir}/gen/*${_node_lib_suffix}")
    foreach(_g IN LISTS _node_gen_archives)
        get_filename_component(_gname "${_g}" NAME)
        if(_gname MATCHES "^[a-zA-Z_]+${_node_lib_suffix}$")
            list(APPEND _node_archives "${_g}")
        endif()
    endforeach()
    unset(_g)
    unset(_gname)
    unset(_node_gen_archives)
    file(INSTALL ${_node_archives} DESTINATION "${_node_pkg_lib_dir}")

    if(_node_rt_builtins_lib)
        file(INSTALL "${_node_rt_builtins_lib}" DESTINATION "${_node_pkg_lib_dir}")
    endif()

    if(_node_cfg STREQUAL "Release")
        set(_node_installed_libs "")
        foreach(_a IN LISTS _node_archives)
            get_filename_component(_n "${_a}" NAME)
            list(APPEND _node_installed_libs "${_n}")
        endforeach()
        list(REMOVE_DUPLICATES _node_installed_libs)
        unset(_n)
    endif()
    unset(_node_archives)
    unset(_node_archives_root)
endforeach()
unset(_node_out_dir)
unset(_node_pkg_lib_dir)
unset(_node_pkg_bin_dir)

if(VCPKG_TARGET_IS_WINDOWS)
    file(INSTALL "${SOURCE_PATH}/src/res/node.exe.extra.manifest"
        DESTINATION "${CURRENT_PACKAGES_DIR}/share/node" RENAME node.exe.extra.manifest)
endif()
