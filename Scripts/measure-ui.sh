#!/bin/zsh
# Runs the `Measure UI` plan and prints, besides the test's own `UI|` lines, the app's own: its signposts, launch
# milestones and slow events from the unified log, which a sandboxed UI test cannot read.
#
#   TEST_RUNNER_MARFA_API_URL=<address> TEST_RUNNER_MARFA_API_KEY=<key> Scripts/measure-ui.sh <derived data> [xcodebuild arguments]
#
# Further arguments go to xcodebuild, such as `-only-testing:MAPPUITests/SpeedMeasureTests/testLaunchWarm` or build
# settings. Add `SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule` for numbers close to a release's.
# The test takes over the screen and keyboard, so run it with no other UI test running, and against a test instance
# only, never a server that holds a person's data. The Debug-only `-MAPPKeepTestStore` flag keeps the copy the last
# launch left, which is how a warm launch is timed. UI testing's own queries of a library this size take seconds, so
# the tests click by coordinate and use shortcuts, and the signposts are the finer number.
set -u
derived=${1:?usage: measure-ui.sh <derived data path> [xcodebuild arguments]}
shift
dir=$(cd "$(dirname "$0")" && pwd)
log=$(mktemp -t mapp-measure-log)
out=$(mktemp -t mapp-measure-out)

# The articles the large-item test opens, made once for the run when the command line can reach the instance.
if command -v marfa > /dev/null && [[ -n ${TEST_RUNNER_MARFA_API_URL:-} && -n ${TEST_RUNNER_MARFA_API_KEY:-} ]]; then
  (
    export MARFA_API_URL=$TEST_RUNNER_MARFA_API_URL MARFA_API_KEY=$TEST_RUNNER_MARFA_API_KEY MARFA_NO_KEYCHAIN=1
    python3 "$dir/speed-fixtures.py" | while IFS= read -r properties; do
      marfa items create --type core.media.article --properties "$properties" > /dev/null || echo "could not make a measuring article" >&2
    done
  )
fi

/usr/bin/log stream --signpost --level debug --style ndjson \
  --predicate 'subsystem BEGINSWITH "com.withmarfa.mapp"' > "$log" 2>/dev/null &
stream=$!
# The stream takes a moment to attach, and nothing has begun.
sleep 2

TEST_RUNNER_MAPP_MEASURE_UI=1 xcodebuild -project "$dir/../MAPP.xcodeproj" -scheme 'MAPP UI Tests' -testPlan 'Measure UI' \
  -destination 'platform=macOS' -derivedDataPath "$derived" "$@" test 2>&1 | tee "$out" | grep -E '^UI\||error:|measured \[|Test Case .* (passed|failed|skipped)|TEST (SUCCEEDED|FAILED)'
result=${pipestatus[1]}

# The stream writes in batches, so give it a moment to hand over the last events.
sleep 2
kill $stream
wait $stream 2>/dev/null
python3 "$dir/speed-report.py" "$log"

# The typing test leaves its one note on the instance, since the app is closed before it could push a delete, and the
# large-item test's articles are made above. Remove them (and any an earlier, interrupted run left) with the command
# line, which reaches only what the key reaches.
if command -v marfa > /dev/null && [[ -n ${TEST_RUNNER_MARFA_API_URL:-} && -n ${TEST_RUNNER_MARFA_API_KEY:-} ]]; then
  export MARFA_API_URL=$TEST_RUNNER_MARFA_API_URL MARFA_API_KEY=$TEST_RUNNER_MARFA_API_KEY MARFA_NO_KEYCHAIN=1
  for id in ${(f)"$(marfa search 'Speed measure' --type core.note --state any --tier all 2>/dev/null \
      | awk '$3 == "core.note" && $0 ~ /Speed measure [0-9A-F]+$/ { print $2 }')"} \
      ${(f)"$(marfa search 'Speed open' --type core.media.article --state any --tier all 2>/dev/null \
      | awk '$3 == "core.media.article" && $0 ~ /Speed open (short|long|pictures|long field)$/ { print $2 }')"}; do
    marfa items delete "$id" > /dev/null 2>&1
    marfa items purge "$id" > /dev/null 2>&1 || echo "could not remove the measuring note $id" >&2
  done
fi
rm -f "$log" "$out"
exit $result
