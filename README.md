# Sky Fling

Fling a paper plane from a slingshot, grab coins, bolt on better parts and evolve it all the way to a Space Plane.
Reach Space, rebirth for Stars, and go even farther. A portrait mobile game made with Godot 4 (GDScript).
No ads, no in-app purchases, no third-party assets: all art and sound are generated in code.

![launch](docs/screenshots/launch.png) ![meadow](docs/screenshots/flight_meadow.png) ![sea](docs/screenshots/flight_sea.png) ![desert](docs/screenshots/flight_desert.png)
![mountains](docs/screenshots/flight_mountains.png) ![clouds](docs/screenshots/flight_clouds.png) ![space](docs/screenshots/flight_space.png) ![hangar](docs/screenshots/hangar.png) ![evolved](docs/screenshots/evolved.png)

## 3D (v2)
The game is rendered in real 3D (Godot Mobile renderer, 2x MSAA (`rendering/anti_aliasing/quality/msaa_3d=1`), no shadows, one cheap blob shadow). Every model is built in code from
primitive meshes (`scripts/game/mesh_builder.gd`): the plane (7 tier silhouettes, every part level looks different), the slingshot
(9 levels, stretching bands, 3D aim arc), pickups and hazards, and procedural terrain chunks per zone (pooled and freed as you fly,
so memory stays flat). Chase camera, landing camera, rotating hangar turntable. The 2D HUD and menus overlay the 3D view.

## True 3D flight (v3, stage A)
Flight is fully 3D (`scripts/core/flight.gd`): yaw/pitch/roll, lift on the banked up axis, auto-coordinated turns (bank limit 60 deg), auto-level, soft stall (~15 deg), terrain heightmap collision (`scripts/core/terrain.gd`), a 3D pickup corridor around the launch heading. Camera is behind the plane. Realistic assets come in stage B.

## Controls
| Action | Touch | Keyboard / mouse |
|---|---|---|
| Aim and launch | Drag the pouch: distance = power, down = climb, sideways = heading (flies the opposite way) | Mouse drag |
| Pitch / bank | Stick bottom left: pull back = climb, push = dive, left / right = bank and turn. Option: phone tilt (Controls) | S, Down = climb; W, Up = dive; A / D = bank |
| Boost rocket | BOOST button | Space |
| Pause / back | Pause button, Android back | Esc |

Controls dialog (Menu or Pause): stick or phone tilt (falls back to the stick when the sensor reads zero), invert pitch, calibrate tilt; saved with the game.

## Features
- Physics flight (gravity, drag, lift by angle of attack, stalls, fuel, boost charges), fixed 60 Hz step, seeded worlds.
- 8 upgradable parts (wings, tail, body, engine, fuel tank, booster, slingshot, skids), 5-8 levels each with geometric prices; each level changes the plane's look.
- 7 plane tiers: Paper plane, Balsa glider, Biplane, Prop plane, Jet, Rocket plane, Space plane, with an "Evolved!" celebration.
- 8 sky zones (Meadow, Hills, Sea, Desert, Mountains, Clouds, Upper Air, Space); Space has low gravity and thin air.
- Pickups and hazards: coins and coin lines, fuel cans, boost rings, updrafts, balloons, birds, storm clouds.
- 3 rolling missions, 34 trophies, daily reward with streak, best-flights page, records.
- Rebirth after reaching Space (600 m height): Stars buy permanent perks (coin boost, spare fuel, cheaper parts, head start).
- Versioned autosave in `user://`, corrupt saves start fresh, reset option with confirmation. Generated SFX with a mute toggle.

## Install the Android APK
`tools/build_apk.sh` builds `build/SkyFling.apk` (arm64-v8a, debug-signed). Copy it to the phone and open it
(allow "install unknown apps"), or `adb install build/SkyFling.apk`.
Needs Godot 4.7.2 with export templates, JDK 17 and the Android SDK (paths at the top of the script).

## Web build
`godot --headless --path . --export-release Web build/web/index.html` (single-threaded; any static host works).

## Develop
- Rules and balance live in `scripts/core/*` (pure scripts, headless-testable); UI in `scripts/game/*`.
- **One test command:** `tools/run_tests.sh` (unit, upgrades-matter, 10,000-flight NaN stress, balance simulation,
  UI smoke with real input events, layout at 720x1280 and 1080x2400, plus negative tests that sabotage the code and must be caught).
- `tools/shots.sh` captures the screenshots under Xvfb.

## License
MIT

## v3 look and credits
Realistic presentation: glTF aircraft with code-built upgrade add-ons, PBR terrain (Poly Haven textures) in a 2D tile grid, HDRI sky fading into space, water shader, MultiMesh trees and rocks, billboard clouds, AgX tonemapping, fog, studio hangar.
All third-party assets (CC0 or CC-BY 3.0) are listed in ASSETS.md and shown in Menu > Credits. CC-BY attributions:
Airplane (biplane) by Poly by Google, Small Airplane by Vojtěch Balák, Jet by jeremy, via Poly Pizza (https://poly.pizza), licensed CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/). Modifications: scaled, re-textured, with add-on parts.
Skies and terrain textures: Poly Haven (CC0). Models: Quaternius and Kenney (CC0).

### Notes
- Renderer: the project ships and is tested with `gl_compatibility` (OpenGL), not the Mobile (Vulkan) renderer.
- There is no flight-time limit. A flight ends on a landing or crash, or when the plane has come to rest (fuel and boosts are finite, gravity never vanishes). Tests and the bot sim use a hidden safety cap only.
- Trees, rocks and cacti are scenery only: they have no collision, the plane flies through them.
- Distance is the straight horizontal distance from the launch point, so flying sideways counts as distance too.
