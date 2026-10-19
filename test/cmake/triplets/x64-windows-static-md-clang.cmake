# The stock `x64-windows-static-md` triplet, building every dependency with clang-cl instead of
# cl.exe. See ../toolchains/clang-cl.cmake for why: Node.js requires clang-cl on
# Windows, this repository's consumer projects use it, and a libnode compiled by
# clang-cl linked against cl.exe-built libraries is a mixture the port does not
# test and does not support. Everything else - architecture, CRT, linkage, and
# whether Debug is built - is exactly the stock triplet's.
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${CMAKE_CURRENT_LIST_DIR}/../toolchains/clang-cl.cmake")
