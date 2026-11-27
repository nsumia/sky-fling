#!/usr/bin/env bash
# THE test command. Headless Godot: unit, upgrades-matter, 10k-flight NaN stress (4 parallel shards), balance simulation,
# 3D plane builder (every part x level), 20 km chunk/node stress, UI + 3D smoke (real scene + input events), layout (720x1280 and 1080x2400), then the negative tests.
# Non-zero exit on: any godot non-zero exit or timeout, missing summary lines, any SCRIPT ERROR / parse error / ERROR line,
# or any negative test that is not detected.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
export SKYFLING_SAVE=user://test_run_save.json
$GODOT --headless --path . --import >/dev/null 2>&1 || true
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
reasons=()

run() { # name script tail_lines marker
  timeout "${TEST_TIMEOUT:-300}" $GODOT --headless --path . -s "res://tests/$2.gd" >"$dir/$1.log" 2>&1
  local rc=$?
  echo "--- $1 ---"
  tail -n "$3" "$dir/$1.log"
  [ "$rc" -eq 0 ] || reasons+=("$1 exited $rc")
  grep -qE "^== [0-9]+ passed, 0 failed ==" "$dir/$1.log" || reasons+=("$1 summary missing or failures")
  grep -q "^$4" "$dir/$1.log" || reasons+=("$1 marker '$4' missing")
}

run unit unit 4 "UNIT OK"
run upgrades upgrades 14 "UPGRADES OK"

echo "--- nan_stress (4 shards x 2500 flights = 10,000) ---"
for s in 0 1 2 3; do
  ( NAN_SHARD=$s NAN_N=2500 timeout "${TEST_TIMEOUT:-300}" $GODOT --headless --path . -s res://tests/nan_stress.gd >"$dir/nan$s.log" 2>&1; echo $? >"$dir/nan$s.rc" ) &
done
wait
for s in 0 1 2 3; do
  tail -n 3 "$dir/nan$s.log" | head -n 1
  [ "$(cat "$dir/nan$s.rc")" -eq 0 ] || reasons+=("nan shard $s exited $(cat "$dir/nan$s.rc")")
  grep -q "^NAN STRESS OK" "$dir/nan$s.log" || reasons+=("nan shard $s not OK")
done

run balance balance 14 "BALANCE OK"
run plane3d plane3d 4 "PLANE3D OK"
run chunks chunks 7 "CHUNKS OK"
run smoke smoke 3 "UI SMOKE OK"
run layout layout 4 "LAYOUT OK"

n=$(cat "$dir"/*.log | grep -cE "SCRIPT ERROR|Parse Error|Compile Error|^ERROR:" || true)
echo "SCRIPT ERROR / ERROR lines: $n"
if [ "$n" -ne 0 ]; then grep -hE "SCRIPT ERROR|Parse Error|Compile Error|^ERROR:" "$dir"/*.log | head -10; reasons+=("$n error lines"); fi

echo "--- negative tests ---"
if [ -z "${SKIP_NEGATIVE:-}" ]; then
  tools/negative_tests.sh 2>&1 | tee "$dir/neg.log"
  grep -q "^NEGATIVE TESTS OK" "$dir/neg.log" || reasons+=("negative tests failed")
fi

if [ ${#reasons[@]} -gt 0 ]; then
  echo "TESTS FAILED: ${reasons[*]}"
  exit 1
fi
echo "ALL TESTS PASSED"
