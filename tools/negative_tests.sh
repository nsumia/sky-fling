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
  "3D: gear level does not change the mesh|scripts/game/plane3d.gd|var gr: int = P[\"gear\"]|var gr: int = mini(1, P[\"gear\"])|plane3d|"
  "3D: part levels ignored by the plane builder|scripts/game/plane3d.gd|p[c] = int(lv.get(c, 0))|p[c] = 0|plane3d|"
  "3D: terrain chunk leak (chunks never freed)|scripts/game/view3d.gd|if idx < lo or idx > hi:|if false:|chunks|"
  "3D: camera does not follow the plane|scripts/game/view3d.gd|var want := _clear_ground(p - hd * back|var want := _clear_ground(Vector3.ZERO - hd * back|chunks|"
  "3D: no coordinated turn (bank target ignored)|scripts/core/flight.gd|var rtarget := roll_in * BANK_MAX|var rtarget := roll_in * 0.0|flight3d|"
  "3D: no auto-level of the wings|scripts/core/flight.gd|else LEVEL_K * sqrt(p_stab / 1.1)|else 0.0|flight3d|"
  "3D: terrain ignored (flat ground at 0)|scripts/core/flight.gd|var gh := Terrain.ground(x, z)|var gh := 0.0|flight3d|"
  "3D: tail gives no pitch authority|scripts/core/stats.gd|\"auth\": 4.2 + 0.5 * t|\"auth\": 4.2|flight3d|"
  "3D: right roll turns the wrong way (lift axis mirrored)|scripts/core/flight.gd|return u0 * cos(phi) + r0 * sin(phi)|return u0 * cos(phi) - r0 * sin(phi)|flight3d|"
  "3D: joystick pull-back does not climb|scripts/core/controls.gd|var p := s.y            # finger below the centre (pulled back) = nose up|var p := -s.y|flight3d|"
  "3D: pickups spread only in a line (no lateral spread)|scripts/core/world.gd|return (rng.randf() + rng.randf() - 1.0) * half_width(u)|return 0.0 * half_width(u)|flight3d|"
  "3D: hangar model not rebuilt after a purchase|scripts/game/view3d.gd|if sig != last_levels_sig:|if false:|smoke|SKYFLING_SAVE=user://neg_smoke3.json"
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
