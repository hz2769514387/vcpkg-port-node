# vcpkg overlay triplet：x64 / macOS / clang / 静态库 / release-only。
#
# 归属：消费端（test）拥有，不是 port 的一部分。
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
set(VCPKG_OSX_ARCHITECTURES x64)

# 默认 release-only（CI 的常态）。要编 debug：设 NODE_PORT_BUILD_TYPE=debug
# （ci-debug.yml 就是这么做的；本机也可以 export 后再 cmake --preset ...）。
# ★ debug 口径**从未实测**，见 ports/node/portfile.cmake 顶部那段 WARNING。
if("$ENV{NODE_PORT_BUILD_TYPE}" STREQUAL "debug")
  set(VCPKG_BUILD_TYPE debug)
else()
  set(VCPKG_BUILD_TYPE release)
endif()
