#!/bin/zsh
# Runs the `Measure UI` plan and prints, besides the test's own `UI|` lines, the app's own: its signposts, launch
# milestones and slow events from the unified log, which a sandboxed UI test cannot read.
#
#   TEST_RUNNER_MARFA_API_URL=<address> TEST_RUNNER_MARFA_API_KEY=<key> TEST_RUNNER_MARFA_TEST_INSTANCE_ID=<instance_id> \
#     Scripts/measure-ui.sh <derived data> [xcodebuild arguments]
#
# The run writes to the server, so it starts only when the instance_id the server reports at its root (`GET <address>/`)
# is the one given: reading it from the server and passing it is the acknowledgement that this is a test instance.
#
# Further arguments go to xcodebuild, such as `-only-testing:MarfaMacUITests/SpeedMeasureTests/testLaunchWarm` or build
# settings. Add `SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule` for numbers close to a release's.
# The test takes over the screen and keyboard, so run it with no other UI test running, and against a test instance
# only, never a server that holds a person's data. The Debug-only `-MarfaMacKeepTestStore` flag keeps the copy the last
# launch left, which is how a warm launch is timed. UI testing's own queries of a library this size take seconds, so
# the tests click by coordinate and use shortcuts, and the signposts are the finer number.
#
# The run's own items (the articles it makes, and the one the typing test makes) are recorded by id when they are made,
# and only those are trashed and purged afterwards, with the instance's item count before and after. A run stopped
# before its end leaves them on the instance.
set -u
derived=${1:?usage: measure-ui.sh <derived data path> [xcodebuild arguments]}
shift
dir=$(cd "$(dirname "$0")" && pwd)

if [[ -z ${TEST_RUNNER_MARFA_API_URL:-} || -z ${TEST_RUNNER_MARFA_API_KEY:-} ]]; then
  echo "measure-ui.sh needs TEST_RUNNER_MARFA_API_URL and TEST_RUNNER_MARFA_API_KEY for a test instance." >&2
  exit 2
fi
reported=$(curl -fsS --max-time 10 "${TEST_RUNNER_MARFA_API_URL%/}/" 2>/dev/null \
  | python3 -c 'import json, sys; print(json.load(sys.stdin).get("instance_id", ""))' 2>/dev/null)
if [[ -z ${TEST_RUNNER_MARFA_TEST_INSTANCE_ID:-} || -z $reported || $reported != "$TEST_RUNNER_MARFA_TEST_INSTANCE_ID" ]]; then
  echo "Refusing to run: TEST_RUNNER_MARFA_TEST_INSTANCE_ID must be the instance_id that $TEST_RUNNER_MARFA_API_URL reports at its root, to say it is a test instance." >&2
  exit 2
fi

log=$(mktemp -t marfa-mac-measure-log)
out=$(mktemp -t marfa-mac-measure-out)
ids=$(mktemp -t marfa-mac-measure-ids)

# The ids of the items this run makes, the only ones it removes.
reach() { command -v marfa > /dev/null && [[ -n ${TEST_RUNNER_MARFA_API_URL:-} && -n ${TEST_RUNNER_MARFA_API_KEY:-} ]]; }
marfa_as_test() { MARFA_API_URL=$TEST_RUNNER_MARFA_API_URL MARFA_API_KEY=$TEST_RUNNER_MARFA_API_KEY MARFA_NO_KEYCHAIN=1 marfa "$@"; }
# Every item the instance holds, in every state.
count_items() {
  marfa_as_test items stats --by state --json 2> /dev/null | python3 -c 'import json, sys; print(sum(json.load(sys.stdin).values()))' 2> /dev/null
}

# The articles the large-item test opens, made once for the run when the command line can reach the instance.
if reach; then
  before=$(count_items)
  python3 "$dir/speed-fixtures.py" | while IFS= read -r properties; do
    id=$(marfa_as_test items create --type core.media.article --properties "$properties" --json 2> /dev/null | python3 "$dir/measure-ids.py" created)
    if [[ -n $id ]]; then echo "made $id" >> "$ids"; else echo "could not make a measuring article" >&2; fi
  done
fi

/usr/bin/log stream --signpost --level debug --style ndjson \
  --predicate 'subsystem BEGINSWITH "com.withmarfa.marfa"' > "$log" 2>/dev/null &
stream=$!
# The stream takes a moment to attach, and nothing has begun.
sleep 2

TEST_RUNNER_MARFA_MAC_MEASURE_UI=1 xcodebuild -project "$dir/../MarfaMac.xcodeproj" -scheme 'MarfaMac UI Tests' -testPlan 'Measure UI' \
  -destination 'platform=macOS' -derivedDataPath "$derived" "$@" test 2>&1 | tee "$out" | grep -E '^UI\||error:|measured \[|Test Case .* (passed|failed|skipped)|TEST (SUCCEEDED|FAILED)'
result=${pipestatus[1]}

# The stream writes in batches, so give it a moment to hand over the last events.
sleep 2
kill $stream
wait $stream 2>/dev/null
python3 "$dir/speed-report.py" "$log"

# The typing test makes one item in the app and prints its link, since the app is closed before it could push a
# delete; the articles were recorded above. Remove those and only those, each by its id.
if reach; then
  while IFS=$'\t' read -r id title; do
    # The id comes from a link, so it is checked against the item's title before it is recorded.
    [[ -n $id && -n $(marfa_as_test items get "$id" --json 2> /dev/null | python3 "$dir/measure-ids.py" titled "$title") ]] \
      && echo "made $id" >> "$ids" || echo "could not confirm the typing item behind '$title'; it stays" >&2
  done < <(python3 "$dir/measure-ids.py" made < "$out")
  removed=0
  for id in ${${(f)"$(<$ids)"}#made }; do
    marfa_as_test items trash "$id" > /dev/null 2>&1
    if marfa_as_test items purge "$id" > /dev/null 2>&1; then removed=$((removed + 1)); else echo "could not purge item $id" >&2; fi
  done
  echo "cleanup: the run made $(wc -l < "$ids" | tr -d ' ') items and removed $removed; the instance held ${before:-?} items before and holds $(count_items) after"
fi
rm -f "$ids"
rm -f "$log" "$out"
exit $result
