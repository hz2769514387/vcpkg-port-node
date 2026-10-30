# The patch set

Twenty-five patches, all of them upstream source. Most carry their reason **inside the diff**, as a
comment added to the patched file, next to the code that needs it - that comment travels with the code
through a rebase, which is where it is worth having. This file is the index: what each patch changes,
and what breaks without it, so that a failed hunk can be triaged without opening twenty-five files.

The numbering is load-bearing. Six files are touched by more than one patch, so they must be applied in
order and a rebase has to resolve them together:

| file | patches |
|---|---|
| `tools/js2c.cc` | 0009, 0015, 0017 |
| `configure.py` | 0008, 0023, 0024 |
| `tools/test.py` | 0021, 0025 |
| `common.gypi` | 0018, 0022 |
| `deps/crates/crates.gyp` | 0014, 0020 |
| `tools/v8_gypfiles/v8.gyp` | 0011, 0012 |

## The route (gyp → ninja on all three platforms)

| patch | touches | what breaks without it |
|---|---|---|
| 0002 | gyp's ninja generator | On Windows a `.S` file (GAS syntax) was handed to MASM, which cannot assemble it; and a `-L<dir>` entry in a `libraries` list was passed as a library rather than a search path |
| 0003 | gyp's msvs emulation | Arguments carrying `=` (`--config_value protocol.path=...`) were run through `normpath`, which collapses `key=..` and drops the key; PCH flags and `/std:` were not emitted |
| 0004 | gyp's MSVSSettings | `LanguageStandard`/`ManualProcessorCompilation` were MSBuild-only, so the ninja generator emitted no `/std:` and did not filter `/MP` |
| 0005 | gyp's win_tool | Linker output and manifest files were decoded as strict UTF-8; a localized MSVC message (GBK on a Chinese Windows) raised `UnicodeDecodeError` and hid the real link error behind a decoding traceback |
| 0006 | gyp's ninja_syntax | An unconsumed `map`/iterator was written into the generated file as `<map object at 0x...>` |
| 0007 | gyp's common | The `-dM` predefines probe produced nothing under clang-cl (it ignores the flag with a warning); the probe now borrows `clang.exe` targeting the MSVC ABI |
| 0008 | `configure.py` | A `CC` that is a bare path containing spaces was `shlex.split` first, which broke it in two |
| 0014 | `deps/crates/crates.gyp` | `$(Platform)` is an MSBuild macro: it made the generated ninja file invalid and handed cargo the wrong architecture. Replaced with `<(target_arch)` |
| 0019 | `deps/libffi/libffi.gyp` | The Windows arm64 assembly object reached the link line only through a `libraries` entry, which the MSBuild generator forwards and the ninja generator does not |
| 0020 | `deps/crates/crates.gyp` | The Debug branch never passed the Rust target, so cargo wrote a host-architecture archive while every link line named the target one |

## Being a vcpkg port (externalized dependencies, no vendored copies)

| patch | touches | what breaks without it |
|---|---|---|
| 0001 | `tools/icu/icu-system.gyp` | On Windows with `--with-intl=system-icu`, `v8.gyp` depends on `:icudata` unconditionally and upstream's system-icu manifest omits it: `dependency ... icudata#target not found`. The real icudata comes from vcpkg's icu |
| 0011 | `simdutf.gyp`, `v8.gyp` | simdutf was compiled from the vendored copy as well as linked from vcpkg - two copies in one process. The target now only satisfies the dependency edge `deps/ada` declares unconditionally |
| 0012 | `v8.gyp` | Chromium's zlib `.c` files produced duplicate symbols next to vcpkg's; `CHROMIUM_ZLIB_NO_CHROMECONF` drops the `Cr_z_` prefix so the code calls vcpkg's `deflate`/`inflate`/... |
| 0022 | `common.gypi` | `BUILDING_UV_SHARED` was defined for Windows unconditionally. With vcpkg's dynamic libuv the consuming side wants `USING_UV_SHARED`, and vcpkg rewrites uv.h's guard so that carrying both is an immediate `#error`. node.gypi removes it for its own targets but host tools never include node.gypi |
| 0023 | `configure.py` | vcpkg's simdjson DLL needs `SIMDJSON_USING_WINDOWS_DYNAMIC_LIBRARY=1` on the consuming side; two globals node reads from `simdjson.h` are data, and data must be dllimport - `LNK2019` on exactly those two symbols |
| 0024 | `configure.py` | Linux shared: abseil arrives as ~90 archives that reference each other, and a single-pass ELF link leaves sixteen symbols undefined *in a shared library that still links*. Fixed with a link group |

## Building from Linux and macOS with paths that Windows also sees

| patch | touches | what breaks without it |
|---|---|---|
| 0009 | `tools/js2c.cc` | The prefix/suffix matching is written for POSIX paths; MSBuild passes `/`, ninja passes `\` |
| 0010 | `deps/v8/src/torque/source-positions.cc` | Same: Windows separators never compared equal to the forward-slash forms, so Torque regenerated everything |
| 0016 | `deps/v8/src/torque/csa-generator.cc` | The path is embedded in a C string literal, and `\d` / `\.` are not escape sequences: the generated source failed to compile |
| 0018 | `common.gypi` | Node's own macOS deployment target was used blindly; every dependency vcpkg built took *vcpkg's* target, so the two disagreed at link time |
| 0013 | `deps/v8/src/codegen/compiler.cc` | Adds the `descriptor-array-inl.h` include this configuration needs; without it the translation unit does not compile |

## Diagnostics this repository added

| patch | touches | what breaks without it |
|---|---|---|
| 0015 | `tools/js2c.cc` | `GetDefinitionImpl` asserts when the output length is 0, which conflates "the input is not valid UTF-8" with "the linked simdutf disagrees with the header it was compiled against". The patch makes the message say which |
| 0017 | `tools/js2c.cc` | A fallback for input that `validate_utf8_with_errors` accepts while `convert_utf8_to_utf16` returns 0 |
| 0021 | `tools/test.py` | The official driver prints an exit code only for crashes and timeouts, so a case that dies quietly (empty output) reported nothing at all |
| 0025 | `tools/test.py` | Case output was decoded strictly; one undecodable byte (a Windows API message in the ANSI code page) killed the whole shard with `UnicodeDecodeError` while nothing had actually failed |

## Adding one

Number it after the last, name it `<number>-<file-or-symptom>.patch`, keep the reason **in the diff**
as a comment where the code changed, and add the row here. A patch whose reason is only in this file
will lose it the first time the file is reformatted; a patch whose reason is only in the diff is hard
to find. Both is the point.
