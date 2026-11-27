extends RefCounted
## Credits text. CC-BY 3.0 attributions are mandatory (the asset test checks every CC-BY row of ASSETS.md appears here).
const CC_BY := [
	["Airplane (biplane)", "Poly by Google", "https://poly.pizza/m/8VysVKMXN2J"],
	["Small Airplane", "Vojtech Balak", "https://poly.pizza/m/7cvx6ex-xfL"],
	["Jet", "jeremy", "https://poly.pizza/m/6fyLMORhgGK"],
]
const CC0 := "Skies and terrain textures: Poly Haven (polyhaven.com), CC0. Models: Quaternius and Kenney (via Poly Pizza), CC0."
const LICENCE := "Licensed under CC BY 3.0 (creativecommons.org/licenses/by/3.0). Modifications: scaled, re-textured, with add-on parts."

static func text() -> String:
	var s := ""
	for c in CC_BY:
		s += "%s by %s\n%s\n\n" % [c[0], c[1], c[2]]
	return s + LICENCE + "\n\n" + CC0
