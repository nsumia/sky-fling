
## v3 STAGE B: realistic presentation (same branch, NOT pushed)
- [x] assets downloaded + licences verified on each page, ASSETS.md written (planes, nature, HDRIs, textures; 28 MB)
- [x] models.gd: glTF hulls loaded, oriented, measured; MB metal layer; plane3d model add-ons (livery, wing ext, tail, engine, prop) first pass
- [x] 1 planes per tier: tune add-ons (fuel/booster/gear fit, tier 0/1 look), plane3d test limits
- [x] 2 terrain PBR splat + 2D chunk grid
- [x] 3 water shader
- [x] 4 sky HDRI -> space
- [x] 5 trees, rocks (MultiMesh), billboard clouds
- [x] 6 fog + tonemapping
- [x] 7 Credits screen
- [x] 8 hangar studio
- [x] 9 asset + performance tests + 2 negatives (asset missing from ASSETS.md, draw-call budget)
- [x] 10 effects (wing-tip trails, speed lines, shake, splash/dust, coin sparkle), screenshots reviewed
- [x] 11 one clean tools/run_tests.sh (ALL TESTS PASSED, rc 0)
- [x] 12 APK (review-round rebuild) 52891876 B sha256 1354c3e0af3e676fec304c5375913a4b79050cb1b0fe82c32e4ee6579bff3910

## v3 review round 1 fixes + owner msg 1207 (no 60 s limit)
- [x] 60 s cap removed (Flight.safety_cap only in tests / bot sim), COST_MUL 1.8 + v_max 21 rebalance, tests: long flight, 10k flights end, negative
- [x] gl_compatibility shipped; speed lines only while boosting (+visual test); hangar banner/particles; jet add-ons subtle; green meadow; fog tuned
- [x] paper (generated grain) + balsa (Poly Haven plywood) PBR, soft smoke trail, pitch absolute test, Vojtěch Balák, README notes, space-plane screenshots
