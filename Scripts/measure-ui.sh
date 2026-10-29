#!/bin/zsh
# Runs the `Measure UI` plan and prints, besides the test's own `UI|` lines, the app's own: its signposts, launch
# milestones and slow events from the unified log, which a sandboxed UI test cannot read.
#
#   TEST_RUNNER_MARFA_API_URL=<address> TEST_RUNNER_MARFA_API_KEY=<key> Scripts/measure-ui.sh <derived data> [xcodebuild arguments]
#
# Further arguments go to xcodebuild, such as `-only-testing:MAPPUITests/SpeedMeasureTests/testLaunchWarm` or build
# settings. The test takes over the screen, so run it with no other UI test running.
set -u
derived=${1:?usage: measure-ui.sh <derived data path> [xcodebuild arguments]}
shift
dir=$(cd "$(dirname "$0")" && pwd)
log=$(mktemp -t mapp-measure-log)
out=$(mktemp -t mapp-measure-out)

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
rm -f "$log" "$out"
exit $result
