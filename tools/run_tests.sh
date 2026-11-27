#!/usr/bin/env bash
# THE test command. Headless Godot: unit, upgrades-matter, 10k-flight NaN stress (4 parallel shards), balance simulation,
# 3D plane builder (every part x level), assets/licence test, draw-call + triangle budget (headless count and Xvfb renderer counters), 20 km tile/node stress, UI + 3D smoke (real scene + input events), layout (720x1280 and 1080x2400), then the negative tests.
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
run flight3d flight3d 12 "FLIGHT3D OK"

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
run flights flights 6 "FLIGHTS OK"
run assets assets 4 "ASSETS OK"
run perf perf 12 "PERF OK"
run visual visual 6 "VISUAL OK"
run smoke smoke 3 "UI SMOKE OK"
run layout layout 4 "LAYOUT OK"

# the same perf test with a real (software GL) renderer: RenderingServer draw-call / primitive counters
XV="$HOME/opt/xvfb/usr/bin"
if [ -x "$XV/Xvfb" ] || command -v Xvfb >/dev/null 2>&1; then
  export PATH="$XV:$PATH"
  if ! pgrep -f "Xvfb :98" >/dev/null; then (Xvfb :98 -screen 0 720x1280x24 >/dev/null 2>&1 &); sleep 2; fi
  echo "--- perf (real renderer under Xvfb, gl_compatibility) ---"
  DISPLAY=:98 timeout "${TEST_TIMEOUT:-300}" $GODOT --rendering-method gl_compatibility --display-driver x11 --resolution 720x1280 --path . -s res://tests/perf.gd >"$dir/perfx.log" 2>&1
  rcx=$?
  grep -E "^PERF|^FAIL" "$dir/perfx.log"
  [ "$rcx" -eq 0 ] || reasons+=("perf (Xvfb) exited $rcx")
  grep -q "^PERF OK" "$dir/perfx.log" || reasons+=("perf (Xvfb) not OK")
  grep -q "RenderingServer counters: max draw calls" "$dir/perfx.log" || reasons+=("perf (Xvfb) printed no renderer counters")
else
  echo "perf under a real renderer: NOT VERIFIED (no Xvfb)"
fi

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
