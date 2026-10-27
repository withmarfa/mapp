#!/bin/bash
# Runs the built Unit plan with a time limit. A run that outlives the limit is sampled before it is killed, so a
# stall names the call it is blocked in instead of ending as a silent cancel at the job's limit.
#
# Usage: run-unit-tests.sh <limit in seconds> <diagnostics directory>
# DERIVED_DATA names the build folder (default: build).
set -uo pipefail

limit=$1
diagnostics=$2
mkdir -p "$diagnostics"

# The tests run one at a time: about 300 wait-based tests that share the main thread and a three-core runner
# otherwise run out of their waits, or never finish.
xcodebuild -project MAPP.xcodeproj -scheme MAPP -testPlan Unit -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA:-build}" -resultBundlePath TestResults.xcresult \
  -parallel-testing-enabled NO test-without-building &
build=$!

derived=$(cd "${DERIVED_DATA:-build}" && pwd)
deadline=$((SECONDS + limit))
while kill -0 "$build" 2>/dev/null; do
  if ((SECONDS >= deadline)); then
    echo "::error::The unit tests did not finish within $limit seconds; sampling them before they are stopped."
    # Only this run's own test host: other processes on a shared Mac are none of its business.
    hosts="$derived/Build/Products/.*/MAPP\.app/Contents/MacOS/MAPP"
    pids=$(pgrep -f "$hosts" || true)
    {
      date -u
      uptime
      top -l 1 -o cpu -n 15
      ps -o pid,ppid,etime,pcpu,rss,command -p "$({ echo "$build"; echo "$pids"; } | grep . | paste -sd, -)"
    } >"$diagnostics/system.txt" 2>&1
    samples=()
    for pid in $pids; do
      sample "$pid" 5 -file "$diagnostics/sample-$pid.txt" >/dev/null 2>&1 &
      samples+=("$!")
    done
    # A bare `wait` would also wait for the test run itself, so only wait when a host was found.
    if ((${#samples[@]} > 0)); then
      wait "${samples[@]}"
    fi
    # The run goes first, so it cannot start a fresh host after the old one is stopped.
    kill "$build" 2>/dev/null
    pkill -f "$hosts" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$build" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$build" 2>/dev/null; then
      kill -9 "$build" 2>/dev/null
    fi
    wait "$build" 2>/dev/null
    exit 124
  fi
  sleep 5
done

wait "$build"
