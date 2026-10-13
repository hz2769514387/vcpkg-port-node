# Sample Windows commit charge / commit limit in the background so that a CI round
# tells us *why* it passed or failed: vcpkg-port-node run #32 showed that the
# 0xC0000409 failures on Windows come from commit exhaustion
# ([low_level_alloc.cc : 554] RAW: Check new_pages != nullptr failed: VirtualAlloc failed
# inside V8's bundled abseil -- VirtualAlloc(..., MEM_RESERVE|MEM_COMMIT, ...)).
# The suite parallelism is now capped at -j 2 on Windows; this sampler records the
# headroom we actually had, so the next round can be judged instead of guessed at.
#
# Usage (CI starts it detached, then creates the stop file to end it):
#   pwsh -NoProfile -File tools/commit-watch.ps1 -Output <file> -StopFile <file> [-IntervalSeconds 5]
# Both values are printed as gigabytes, one sample per line:
#   <iso timestamp> <committed GB> <limit GB> <free GB>

param(
  [Parameter(Mandatory = $true)][string]$Output,
  [Parameter(Mandatory = $true)][string]$StopFile,
  [int]$IntervalSeconds = 5
)

$GB = 1073741824.0
New-Item -ItemType File -Path $StopFile -Force | Out-Null

while (Test-Path -LiteralPath $StopFile) {
  try {
    $samples = (Get-Counter '\Memory\Committed Bytes', '\Memory\Commit Limit' -ErrorAction Stop).CounterSamples
    $committed = ($samples | Where-Object { $_.Path -like '*committed*' }).CookedValue
    $limit = ($samples | Where-Object { $_.Path -like '*limit*' }).CookedValue
    $free = $limit - $committed
    '{0} {1:N2} {2:N2} {3:N2}' -f (Get-Date -Format o), ($committed / $GB), ($limit / $GB), ($free / $GB) |
      Add-Content -Path $Output
  } catch {
    "sample failed: $($_.Exception.Message)" | Add-Content -Path $Output
  }
  Start-Sleep -Seconds $IntervalSeconds
}
