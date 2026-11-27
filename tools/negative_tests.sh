#!/usr/bin/env bash
# Negative tests: sabotage the game in a throw-away copy and prove that the test suite DETECTS each sabotage.
# Exits non-zero if any mutation was not applied or was NOT detected (the test run stayed green).
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
root=$(pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# name | file | python-literal old | new | test script | extra env
mutations=(
  "broken wing stat (no lift gain)|scripts/core/stats.gd|\"area\": 1.0 + 0.22 * w|\"area\": 1.0|upgrades|"
  "dead engine (no thrust)|scripts/core/stats.gd|else 1.2 + 1.1 * e|else 0.0|upgrades|"
  "slingshot ignores level|scripts/core/stats.gd|\"v_max\": 19.0 + 2.4 * s|\"v_max\": 19.0|upgrades|"
  "corrupt-save guard removed|scripts/core/save_store.gd|if typeof(raw) != TYPE_DICTIONARY:|if false:|unit|"
  "buy allowed without coins|scripts/core/econ.gd|return c > 0 and d[\"coins\"] >= c|return c > 0|unit|"
  "costs 5x too cheap (balance)|scripts/core/cfg.gd|var c: float = p[\"base\"] * pow(p[\"growth\"], level - 1)|var c: float = 0.2 * p[\"base\"] * pow(p[\"growth\"], level - 1)|balance|"
  "boost button pushed off-screen (layout)|scripts/game/main.gd|bb.offset_right = -30|bb.offset_right = 200|layout|SKYFLING_SAVE=user://neg_layout.json"
  "zero mass gives NaN physics|scripts/core/flight.gd|var mass := p_mass|var mass := 0.0|nan_stress|NAN_N=40"
  "result screen never reached (smoke)|scripts/game/main.gd|state = \"result\"|state = \"flying\"|smoke|SKYFLING_SAVE=user://neg_smoke.json"
  "confirm dialog replaces the panel (reintroduced bug)|scripts/game/main.gd|_panel_box(0.85, false)|_panel_box(0.85, true)|smoke|SKYFLING_SAVE=user://neg_smoke2.json"
)

for spec in "${mutations[@]}"; do
  IFS='|' read -r name file old new test extra <<<"$spec"
  work="$tmp/copy"
  rm -rf "$work"
  mkdir -p "$work"
  tar --exclude=./build --exclude=./docs --exclude=./.git -cf - . | tar -xf - -C "$work"
  if ! python3 - "$work/$file" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if old not in s:
    sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
PY
  then
    echo "NEGATIVE NOT APPLIED: $name (pattern not found in $file)"
    fail=1
    continue
  fi
  ( cd "$work" && env $extra timeout 200 $GODOT --headless --path . --import >/dev/null 2>&1; env $extra timeout 240 $GODOT --headless --path . -s "res://tests/$test.gd" >"$tmp/neg.log" 2>&1 )
  rc=$?
  if [ "$rc" -ne 0 ] || grep -qE "SCRIPT ERROR" "$tmp/neg.log"; then
    echo "NEGATIVE DETECTED: $name  (test '$test' rc=$rc: $(grep -m1 -E '^FAIL|SCRIPT ERROR' "$tmp/neg.log" | cut -c1-90))"
  else
    echo "NEGATIVE MISSED: $name  (test '$test' stayed green)"
    fail=1
  fi
done
[ "$fail" -eq 0 ] && echo "NEGATIVE TESTS OK" || echo "NEGATIVE TESTS FAILED"
exit $fail
