#!/usr/bin/env python3
"""Exercise `ports/node/cmake/msvc-environment-report.cmake` through all of its cases.

Why this exists
---------------

That function decides what the port says when it cannot find a usable MSVC environment, and two of
its four cases can only happen on a machine that is *missing* Visual Studio or its SDK. No CI runner
here is missing either, and neither is a developer's machine, so before this file existed the two
interesting answers were never executed by anything - which is how the port came to warn when nothing
was wrong, say nothing when the SDK was missing, and warn-and-continue in the case that should stop.

The function takes the two resolved values as arguments and reads INCLUDE/LIB from the environment,
so it needs no toolchain: `cmake -P` drives it in milliseconds, on any platform.

Usage: check_msvc_environment_report.py [-v]

Exits 0 when every case produces the specified message and exit status, 1 otherwise.
"""

import argparse
import os
import subprocess
import sys
import tempfile
import textwrap

MODULE = os.path.join("ports", "node", "cmake", "msvc-environment-report.cmake")

# The driver is generated rather than tracked: it is four lines, and keeping it out of the repository
# avoids a second file that must stay in step with this one.
DRIVER = textwrap.dedent(
    """\
    if(NOT DEFINED REPORT_MODULE)
      message(FATAL_ERROR "REPORT_MODULE is required")
    endif()
    include("${REPORT_MODULE}")
    node_port_report_msvc_environment("${ROOT}" "${SDK}")
    """
)

# name, root, sdk, INCLUDE/LIB set in the environment, expected exit status, expected text
CASES = [
    ("toolset and SDK resolved", "C:/VS", "10.0.22621", False, 0,
     "MSVC command-line environment ready (MSVC C:/VS, Windows SDK 10.0.22621)"),
    ("nothing resolved, INCLUDE/LIB inherited", "", "", True, 0,
     "no MSVC toolset or Windows SDK found, but INCLUDE and LIB are already set"),
    ("nothing at all", "", "", False, 1,
     "cannot build Node.js on Windows: no MSVC toolset or Windows SDK found"),
    # Half a toolchain: the case the old code printed nothing about, because its good-message branch
    # required both halves and its bad-message branch only looked at the toolset.
    ("toolset but no SDK", "C:/VS", "", False, 1, "no Windows SDK found"),
    ("SDK but no toolset", "", "10.0.22621", False, 1, "no MSVC toolset found"),
]


def run_case(cmake, driver, module, root, sdk, inherited):
    env = dict(os.environ)
    for var in ("INCLUDE", "LIB"):
        env.pop(var, None)
        if inherited:
            env[var] = "C:/somewhere"
    proc = subprocess.run(
        [cmake, f"-DREPORT_MODULE={module}", f"-DROOT={root}", f"-DSDK={sdk}", "-P", driver],
        capture_output=True, text=True, encoding="utf-8", errors="replace", env=env)
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("-v", "--verbose", action="store_true", help="print every case's message")
    args = parser.parse_args()

    if not os.path.isfile(MODULE):
        print(f"check_msvc_environment_report: {MODULE} not found; run from the repository root",
              file=sys.stderr)
        return 2

    cmake = os.environ.get("CMAKE", "cmake")
    module = os.path.abspath(MODULE)
    failures = 0

    with tempfile.TemporaryDirectory() as tmp:
        driver = os.path.join(tmp, "driver.cmake")
        with open(driver, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(DRIVER)
        for name, root, sdk, inherited, want_code, want_text in CASES:
            code, out = run_case(cmake, driver, module, root, sdk, inherited)
            # CMake re-flows a FATAL_ERROR message to the terminal width, so a phrase from the source
            # can come back split across two lines with an indent. Compare on collapsed whitespace.
            flat = " ".join(out.split())
            ok = code == want_code and " ".join(want_text.split()) in flat
            if not ok:
                failures += 1
            print(f"{'ok  ' if ok else 'FAIL'}  {name}")
            if args.verbose or not ok:
                message = next((l.strip() for l in out.splitlines() if "node port:" in l), "<no message>")
                print(f"        exit={code} (want {want_code})  {message[:150]}")
                if not ok:
                    print(f"        expected to contain: {want_text}")

    print(f"check_msvc_environment_report: {len(CASES) - failures}/{len(CASES)} cases as specified")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
