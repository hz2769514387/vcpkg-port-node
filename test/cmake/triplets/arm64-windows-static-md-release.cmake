# The stock `arm64-windows-static-md` triplet (static libnode, dynamic CRT), Release only.
#
# The matrix legs (issue #11) build this cell Release-only: with the stock dual triplet
# the port is built twice and the slowest legs - a four-core arm64 Linux runner - ran
# past GitHub's six-hour job limit (measured: linux-shared-arm64 spent its whole
# six hours inside the install, still compiling libnode). Release-only halves that,
# and the Debug dimension stays covered by the Debug workflow on the static triplets.
set(VCPKG_BUILD_TYPE release)

set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
