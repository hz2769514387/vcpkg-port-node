#!/usr/bin/env bash
#
# Compare the node this port built against the official binary of the same version.
#
# This is step 5 of the release checklist in docs/versioning.md. It is not a per-push test - a
# comparison only means something on a quiet machine - so it runs as its own dispatched workflow
# (.github/workflows/benchmark.yml) and its numbers live in the run, not in docs/.
#
# Two halves, because they answer different questions:
#
#   startup   the median of 20 runs of an empty script, in microseconds. This is what "the binary
#             is fast" usually means, and it is a property of the executable.
#   workload  tools/benchmark_workload.js, four cases each leaning on a different piece of the C++
#             underneath (OpenSSL, zlib, V8's JSON, the buffer implementation), best of 5 runs.
#             The JavaScript is identical for both binaries, so the difference is what this port
#             changes: compiler, flags, externalized dependencies.
#
# Node.js's own benchmark/ directory is deliberately *not* parsed: its output format moved from
# "N ops/sec" lines to JSON records between releases, and a release check that breaks when
# upstream reformats a printer is not a release check.
#
# Usage: PRESET=x64-linux-release TRIPLET=x64-linux-release tools/benchmark_compare.sh
#
# Environment:
#   PRESET, TRIPLET   the build the port installed into (required)
#   OFFICIAL_URL      tarball to compare against (default: nodejs.org for this port's version)
#   OFFICIAL_NODE     use this binary instead of downloading (with OFFICIAL_SKIP_DOWNLOAD=1)

set -euo pipefail

: "${PRESET:?PRESET is required, e.g. x64-linux-dynamic}"
: "${TRIPLET:?TRIPLET is required, e.g. x64-linux-dynamic-release}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prefix="${root}/test/build/${PRESET}/vcpkg_installed/${TRIPLET}"
ours="${prefix}/tools/node/node"
workload="${root}/tools/benchmark_workload.js"

node_release="${NODE_RELEASE:-$(grep -oE '"version": *"[0-9]+\.[0-9]+\.[0-9]+"' "${root}/ports/node/vcpkg.json" | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')}"
official_url="${OFFICIAL_URL:-https://nodejs.org/dist/v${node_release}/node-v${node_release}-linux-x64.tar.xz}"

for path in "${ours}" "${workload}"; do
  if [ ! -e "${path}" ]; then
    echo "::error::missing ${path} - this leg has to install the port with the tools feature"
    exit 1
  fi
done

echo "## node ${node_release}: this port vs the official binary"
echo

if [ "${OFFICIAL_SKIP_DOWNLOAD:-0}" = "1" ]; then
  official="${OFFICIAL_NODE:?OFFICIAL_SKIP_DOWNLOAD=1 needs OFFICIAL_NODE}"
else
  scratch="$(mktemp -d)"
  echo "Fetching ${official_url}"
  curl -fsSL "${official_url}" | tar -xJ -C "${scratch}" --strip-components=1
  official="${scratch}/bin/node"
fi

# Same Node.js or the comparison measures nothing.
v_ours="$("${ours}" --version)"
v_official="$("${official}" --version)"
if [ "${v_ours}" != "${v_official}" ]; then
  echo "::error::version mismatch: the port built ${v_ours}, the official binary is ${v_official}"
  exit 1
fi
echo "Both report ${v_ours}."
echo "Machine: $(nproc 2>/dev/null || echo '?') cores, $(awk -F: '/model name/ {gsub(/^ +/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || echo 'unknown')"
echo

median() { sort -n | awk '{a[NR] = $1} END {printf "%d", a[int((NR + 1) / 2)]}'; }

startup_us() {
  local node="$1" i start end
  "${node}" -e '' 2>/dev/null || true
  for i in $(seq 20); do
    start=$(date +%s%N)
    "${node}" -e '' 2>/dev/null
    end=$(date +%s%N)
    echo $(( (end - start) / 1000 ))
  done | median
}

# Best of 5: the fastest run is the one least disturbed by the machine, which is what a comparison
# between two binaries wants; a median would carry the noise of both.
best_ms() {
  local node="$1" case_name="$2" i value
  for i in $(seq 5); do
    "${node}" "${workload}" "${case_name}" | awk '{print $2}'
  done | sort -n | head -n 1
}

echo "Measuring startup (20 runs each, median)..."
s_ours="$(startup_us "${ours}")"
s_official="$(startup_us "${official}")"

echo "Measuring the workload (best of 5 each case)..."
echo
echo '| case | official | this port | this port / official |'
echo '|---|---|---|---|'
printf '| startup, median of 20 (ms) | %.1f | %.1f | %.2f |\n' \
  "$(awk -v v="${s_official}" 'BEGIN {print v/1000}')" \
  "$(awk -v v="${s_ours}" 'BEGIN {print v/1000}')" \
  "$(awk -v a="${s_ours}" -v b="${s_official}" 'BEGIN {print (b == 0 ? 0 : a/b)}')"

for case_name in hash gzip json buffer; do
  o="$(best_ms "${official}" "${case_name}")"
  p="$(best_ms "${ours}" "${case_name}")"
  printf '| %s, best of 5 (ms) | %s | %s | %s |\n' "${case_name}" "${o}" "${p}" \
    "$(awk -v a="${p}" -v b="${o}" 'BEGIN {print (b == 0 ? 0 : a/b)}' )"
done

echo
echo "A ratio near 1.00 means the port's build behaves like the official one. For the timing rows"
echo "lower is better; a ratio well above 1.00 is worth explaining in the release notes."
