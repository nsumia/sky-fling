extends RefCounted
## Original sound effects generated in code as AudioStreamWAV (16-bit mono). No audio assets.
const RATE := 22050
const PAD := 16  # slack samples past the end (Godot's resampler over-reads; avoids a SIGSEGV on Android)

static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize((n + PAD) * 2)
	for i in n:
		var v := int(clampf(samples[i], -1.0, 1.0) * 30000.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w

static func gen(kind: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var dur := 0.2
	match kind:
		"coin": dur = 0.18
		"launch": dur = 0.35
		"boost": dur = 0.5
		"crash": dur = 0.45
		"evolve": dur = 0.9
		"click": dur = 0.06
		"bounce": dur = 0.15
		"ring": dur = 0.3
		"fuel": dur = 0.25
		"claim": dur = 0.5
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var v := 0.0
		match kind:
			"coin":
				var f := 988.0 if u < 0.35 else 1319.0
				ph += TAU * f / RATE
				v = sin(ph) * (1.0 - u) * 0.5
			"launch":
				var f := 700.0 - 520.0 * u
				ph += TAU * f / RATE
				v = (sin(ph) * 0.5 + (rng.randf() - 0.5) * 0.25) * (1.0 - u)
			"boost":
				v = (rng.randf() - 0.5) * 0.7 * (1.0 - u) * minf(1.0, u * 12.0)
			"crash":
				var f := 120.0 * (1.0 - u * 0.7)
				ph += TAU * f / RATE
				v = ((rng.randf() - 0.5) * 0.8 + sin(ph) * 0.5) * pow(1.0 - u, 2.0)
			"evolve":
				var notes := [523.0, 659.0, 784.0, 1047.0]
				var f: float = notes[mini(3, int(u * 4.0))]
				ph += TAU * f / RATE
				v = sin(ph) * 0.4 * (1.0 - fmod(u * 4.0, 1.0) * 0.5)
			"click":
				ph += TAU * 600.0 / RATE
				v = sin(ph) * (1.0 - u) * 0.4
			"bounce":
				ph += TAU * (300.0 + 200.0 * u) / RATE
				v = sin(ph) * (1.0 - u) * 0.5
			"ring":
				ph += TAU * (500.0 + 900.0 * u) / RATE
				v = sin(ph) * (1.0 - u) * 0.45
			"fuel":
				ph += TAU * (400.0 + 300.0 * floor(u * 3.0)) / RATE
				v = sin(ph) * (1.0 - u) * 0.4
			"claim":
				ph += TAU * (600.0 + 600.0 * u) / RATE
				v = sin(ph) * 0.4 * (1.0 - u)
			_:
				v = 0.0
		out[i] = v
	return _wav(out)
