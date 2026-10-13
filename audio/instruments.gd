class_name Instruments
extends RefCounted
## Renders the soundtrack's sounds ahead of time. Mixing finished sounds at
## play time is cheap enough for GDScript; synthesising them live wouldn't
## be.
##
## Each instrument makes its sound with one of a few models, picked by its
## settings' `model` (the first in PARAMS if none):
## - analog: band-limited oscillators through resonant filters and
##   envelopes, the way an analogue synth would.
## - pluck: a plucked string (Karplus-Strong): a burst of noise going round
##   a delay line one period long, losing its highs each time round.
## - fm: a sine whose phase another sine pushes about, for bells, electric
##   pianos and brass.
## - gong, tuned, metal: the drums' others; see each.
##
## Every sound is a stereo buffer at `rate` samples per second. Each
## instrument takes its settings (see Music), each
## model's under its name, falling back to the defaults here for anything
## left out. Brought over from Real-Time Logistics.

const LEAD_ANALOG := {
	"length": [0.3, 0.05, 3.0],
	"saw": [0.5, 0.0, 1.5],
	"pulse": [0.5, 0.0, 1.5],
	"sine": [0.0, 0.0, 1.5],
	"width": [0.25, 0.02, 0.98],
	"cutoff": [700.0, 100.0, 10000.0],
	"env": [4500.0, 0.0, 12000.0],
	"env_decay": [0.06, 0.005, 1.0],
	"attack": [0.003, 0.001, 0.5],
	"decay": [0.1, 0.01, 2.0],
	"resonance": [1.1, 0.0, 1.95],
	"vibrato": [0.0, 0.0, 1.0],
	"vibrato_rate": [5.0, 0.5, 12.0],
}
## `decay` is how long the string takes to die away; `damping` how much
## faster its highs go; `pick` how bright the pluck is, and `position` how
## far along the string, which hollows it out.
const PLUCK := {
	"length": [1.0, 0.1, 4.0],
	"decay": [1.0, 0.05, 8.0],
	"damping": [0.5, 0.0, 1.0],
	"pick": [3000.0, 100.0, 12000.0],
	"position": [0.15, 0.0, 0.5],
	"drive": [1.0, 0.5, 5.0],
	"tremolo": [0.0, 0.0, 1.0],
	"tremolo_rate": [5.0, 0.5, 12.0],
}
## `ratio` is the modulator's pitch against the note's, whole for tones and
## otherwise clangy; `index` how hard it pushes at the strike, settling to
## `sustain` over `index_decay` (rising to it, if it's more, like brass).
## `tine` adds an electric piano's ping; `detune` beats the sides against
## each other (Hz apart), like a gamelan's paired instruments.
const FM := {
	"length": [0.8, 0.05, 6.0],
	"ratio": [1.0, 0.25, 12.0],
	"index": [2.0, 0.0, 12.0],
	"sustain": [0.3, 0.0, 12.0],
	"index_decay": [0.15, 0.005, 3.0],
	"attack": [0.002, 0.001, 0.5],
	"decay": [0.5, 0.01, 6.0],
	"tine": [0.0, 0.0, 1.5],
	"detune": [0.0, 0.0, 12.0],
	"vibrato": [0.0, 0.0, 1.0],
	"vibrato_rate": [5.0, 0.5, 12.0],
	"tremolo": [0.0, 0.0, 1.0],
	"tremolo_rate": [4.0, 0.5, 12.0],
	"drive": [1.0, 0.5, 5.0],
}
## Seconds between a comp chord's notes, low to high: a strum or a roll.
const STRUM := { "strum": [0.012, 0.0, 0.15] }

## Every setting each instrument takes, by model: [default, lowest,
## highest]. The lowest and highest are only what the music editor offers.
static var PARAMS: Dictionary = _params()

var rate: float
var _noise := RandomNumberGenerator.new()


static func _params() -> Dictionary:
	return {
		"bass": {
			"analog": {
				"length": [0.16, 0.03, 2.5],
				"detune": [0.0035, 0.0, 0.03],
				"sub": [0.8, 0.0, 1.5],
				"floor": [160.0, 20.0, 1000.0],
				"bright": [3200.0, 200.0, 12000.0],
				"dark": [1100.0, 100.0, 8000.0],
				"env": [0.045, 0.005, 1.0],
				"decay": [0.085, 0.01, 2.0],
				"resonance": [0.9, 0.0, 1.95],
				"drive": [1.4, 0.5, 5.0],
			},
			# The bass's open filter (`bright`) plucks harder or pushes harder.
			"pluck": PLUCK.merged({ "pick": [900.0, 100.0, 12000.0], "bright": [2500.0, 100.0, 12000.0], "drive": [1.2, 0.5, 5.0] }, true),
			"fm": FM.merged({ "length": [0.6, 0.05, 4.0], "index": [1.0, 0.0, 12.0], "bright": [2.5, 0.0, 12.0], "sustain": [0.2, 0.0, 12.0], "index_decay": [0.08, 0.005, 3.0], "decay": [0.3, 0.01, 6.0], "drive": [1.2, 0.5, 5.0] }, true),
		},
		"lead": { "analog": LEAD_ANALOG, "pluck": PLUCK, "fm": FM },
		# Chords played on a pattern, over the pad.
		"comp": { "fm": FM.merged(STRUM), "pluck": PLUCK.merged(STRUM), "analog": LEAD_ANALOG.merged(STRUM) },
		"pad": {
			"analog": {
				"loop": [4.0, 1.0, 8.0],
				"detune": [9.0, 0.0, 40.0],
				"width": [0.0, 0.0, 0.95],
				"cutoff": [700.0, 100.0, 8000.0],
				"sweep": [500.0, 0.0, 3000.0],
				"resonance": [0.3, 0.0, 1.95],
			},
			# An organ or electric piano held down: `sweep` breathes the index
			# once a loop.
			"fm": {
				"loop": [4.0, 1.0, 8.0],
				"detune": [6.0, 0.0, 40.0],
				"ratio": [1.0, 0.25, 12.0],
				"index": [1.0, 0.0, 8.0],
				"sweep": [0.5, 0.0, 4.0],
				"tremolo": [0.0, 0.0, 1.0],
				"tremolo_rate": [4.0, 0.25, 12.0],
			},
		},
		"kick": {
			"analog": {
				"length": [0.45, 0.1, 1.5],
				"low": [44.0, 20.0, 120.0],
				"high": [130.0, 0.0, 400.0],
				"sweep": [0.03, 0.005, 0.2],
				"decay": [0.22, 0.02, 1.0],
				"drive": [1.6, 0.5, 5.0],
				"click": [0.4, 0.0, 1.5],
			},
			"gong": {
				"length": [3.0, 0.3, 8.0],
				"pitch": [70.0, 25.0, 400.0],
				"ratio": [1.41, 0.25, 6.0],
				"index": [1.5, 0.0, 8.0],
				"decay": [1.5, 0.1, 6.0],
				"beat": [1.5, 0.0, 8.0],
				"strike": [0.3, 0.0, 1.5],
			},
		},
		"snare": {
			"analog": {
				"length": [0.3, 0.05, 1.5],
				"tone": [185.0, 60.0, 600.0],
				"noise": [1900.0, 300.0, 9000.0],
				"decay": [0.09, 0.01, 0.6],
			},
			# A pitched hit: woodblock, rimshot or, with a bend, a hand drum.
			"tuned": {
				"length": [0.3, 0.05, 1.5],
				"pitch": [220.0, 50.0, 4000.0],
				"bend": [0.5, 0.0, 2.0],
				"bend_time": [0.02, 0.002, 0.2],
				"decay": [0.12, 0.005, 1.0],
				"noise": [0.3, 0.0, 1.5],
				"band": [2500.0, 200.0, 12000.0],
				"noise_decay": [0.015, 0.002, 0.3],
			},
		},
		"hat": {
			"analog": {
				"cutoff": [7500.0, 1000.0, 16000.0],
				"ring": [1.0, 0.2, 5.0],
			},
			# Six square waves at clashing pitches: small cymbals, cowbells.
			"metal": {
				"pitch": [540.0, 100.0, 2500.0],
				"cutoff": [7000.0, 1000.0, 16000.0],
				"ring": [1.0, 0.2, 5.0],
			},
		},
	}


func _init(sample_rate: float) -> void:
	rate = sample_rate
	_noise.seed = 1982


## Which model an instrument's settings make its sound with.
static func model(p: Dictionary, instrument: String) -> String:
	var name := str(p.get("model", ""))
	return name if PARAMS[instrument].has(name) else PARAMS[instrument].keys()[0]


## An instrument's setting for its model, from a style's settings for it,
## or its default.
static func param(p: Dictionary, instrument: String, name: String) -> float:
	var at := model(p, instrument)
	var own: Variant = p.get(at)
	if own is Dictionary and own.has(name):
		return float(own[name])
	return float(PARAMS[instrument][at][name][0])




static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## A note of a tonal instrument (bass, lead or comp), in its model. `bright`
## is the bass's open filter.
func tone(instrument: String, note: float, p: Dictionary, bright := false) -> PackedVector2Array:
	match model(p, instrument):
		"pluck":
			return _pluck(instrument, note, p, bright)
		"fm":
			return _fm(instrument, note, p, bright)
	if instrument == "bass":
		return _analog_bass(note, bright, p)
	return _analog_lead(instrument, note, p)


func bass(note: float, bright: bool, p: Dictionary) -> PackedVector2Array:
	return tone("bass", note, p, bright)


## Notes needn't be whole.
func lead(note: float, p: Dictionary) -> PackedVector2Array:
	return tone("lead", note, p)


## A chord struck, strummed or rolled from the bottom up.
func comp(notes: Array, p: Dictionary) -> PackedVector2Array:
	var gap := int(param(p, "comp", "strum") * rate)
	var sounds: Array[PackedVector2Array] = []
	var n := 0
	for i in notes.size():
		sounds.push_back(tone("comp", notes[i], p))
		n = maxi(n, sounds[i].size() + gap * i)
	var out := _buffer(n)
	var level := 1.0 / sqrt(notes.size())
	for i in sounds.size():
		var sound := sounds[i]
		var offset := gap * i
		for j in sound.size():
			out[offset + j] += sound[j] * level
	return out


## A bass pluck: two detuned saws and a square an octave down, through a
## resonant low-pass that snaps shut after each note. `bright` opens the
## filter further, for when the track is going hard.
func _analog_bass(note: float, bright: bool, p: Dictionary) -> PackedVector2Array:
	var n := int(param(p, "bass", "length") * rate)
	var out := _buffer(n)
	var hz := midi_hz(note)
	var detune: float = param(p, "bass", "detune")
	var sub: float = param(p, "bass", "sub")
	var phases := [0.0, 0.33, 0.61]
	var steps := [hz * (1.0 + detune) / rate, hz * (1.0 - detune) / rate, hz * 0.5 / rate]
	var filter := Svf.new(rate)
	var low: float = param(p, "bass", "floor")
	var peak: float = param(p, "bass", "bright") if bright else param(p, "bass", "dark")
	var sweep: float = param(p, "bass", "env")
	var decay: float = param(p, "bass", "decay")
	var resonance: float = param(p, "bass", "resonance")
	var drive: float = param(p, "bass", "drive")
	for i in n:
		var t := i / rate
		var x := 0.0
		for o in 3:
			phases[o] = fmod(phases[o] + steps[o], 1.0)
			x += (_pulse(phases[o], steps[o], 0.5) * sub) if o == 2 else _saw(phases[o], steps[o]) * 0.5
		var y := filter.low(x, low + (peak - low) * exp(-t / sweep), resonance)
		var amp := minf(t / 0.002, 1.0) * exp(-t / decay) * _tail(i, n, 0.01)
		out[i] = Vector2.ONE * tanh(y * amp * drive)
	return out


## A sustained chord as a seamless loop: each note a pair of detuned
## oscillators, one per side, through a low-pass that breathes once per
## loop (or, as fm, an organ whose brightness breathes). Every oscillator is
## nudged to a whole number of cycles per loop so it repeats without a
## seam; the voice playing it fades it in and out. It's the slowest sound
## to make by far, so it comes back as a Pad to render a stretch at a time.
func pad(notes: Array, p: Dictionary) -> Pad:
	return Pad.new(self, notes, p)


## A lead note, plucked through a filter: any mix of saw, pulse and sine,
## with a vibrato that comes in as it holds.
func _analog_lead(instrument: String, note: float, p: Dictionary) -> PackedVector2Array:
	var n := int(param(p, instrument, "length") * rate)
	var out := _buffer(n)
	var step := midi_hz(note) / rate
	var saw: float = param(p, instrument, "saw")
	var pulse: float = param(p, instrument, "pulse")
	var sine: float = param(p, instrument, "sine")
	var width: float = param(p, instrument, "width")
	var cutoff: float = param(p, instrument, "cutoff")
	var sweep: float = param(p, instrument, "env")
	var sweep_decay: float = param(p, instrument, "env_decay")
	var attack: float = param(p, instrument, "attack")
	var decay: float = param(p, instrument, "decay")
	var resonance: float = param(p, instrument, "resonance")
	var vibrato: float = param(p, instrument, "vibrato")
	var vibrato_rate: float = param(p, instrument, "vibrato_rate")
	var phase := 0.0
	var filter := Svf.new(rate)
	for i in n:
		var t := i / rate
		var bent := step * _vibrato(t, vibrato, vibrato_rate)
		phase = fmod(phase + bent, 1.0)
		var x := _saw(phase, bent) * saw + _pulse(phase, bent, width) * pulse + sin(TAU * phase) * sine
		var y := filter.low(x, cutoff + sweep * exp(-t / sweep_decay), resonance)
		var amp := minf(t / attack, 1.0) * exp(-t / decay) * _tail(i, n, 0.02)
		out[i] = Vector2.ONE * y * amp
	return out


## A plucked string (Karplus-Strong): a burst of filtered noise one period
## long, going round a delay line that loses a little, and its highs more,
## each time round.
func _pluck(instrument: String, note: float, p: Dictionary, bright: bool) -> PackedVector2Array:
	var n := int(param(p, instrument, "length") * rate)
	var out := _buffer(n)
	var hz := midi_hz(note)
	# Averaging with the sample before adds `damping` samples round the
	# loop; the delay's shortened to match, so it stays in tune.
	var damping := param(p, instrument, "damping") * 0.5
	var period := maxf(rate / hz - damping, 2.0)
	var whole := int(period)
	var frac := period - whole
	# What the loop keeps each time round, to fall 60 dB over `decay`.
	var keep := pow(0.001, 1.0 / (param(p, instrument, "decay") * hz))
	var pick := param(p, instrument, "bright") if bright else param(p, instrument, "pick")
	var smooth := 1.0 - exp(-TAU * pick / rate)
	var burst := PackedFloat32Array()
	burst.resize(whole)
	var e := 0.0
	for i in whole:
		e += smooth * (_noise.randf_range(-1.0, 1.0) - e)
		burst[i] = e
	# Plucked partway along, the string can't sound what has a node there.
	var position := int(param(p, instrument, "position") * whole)
	if position > 0:
		for i in range(whole - 1, position - 1, -1):
			burst[i] -= burst[i - position]
	var size := whole + 3
	var line := PackedFloat32Array()
	line.resize(size)
	var tremolo := param(p, instrument, "tremolo")
	var tremolo_rate := param(p, instrument, "tremolo_rate")
	var drive := param(p, instrument, "drive")
	var dc_in := 0.0
	var dc_out := 0.0
	# How loud its first moments are, to bring every note to the same level:
	# the pick's spike would say little about how loud the note sounds.
	var early := mini(int(0.15 * rate), n)
	var power := 0.0
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var a0 := line[posmod(i - whole, size)]
		var a1 := line[posmod(i - whole - 1, size)]
		var a2 := line[posmod(i - whole - 2, size)]
		var y := keep * ((1.0 - damping) * lerpf(a0, a1, frac) + damping * lerpf(a1, a2, frac))
		if i < whole:
			y += burst[i]
		line[i % size] = y
		# Without its DC, which the burst may have left going round.
		dc_out = y - dc_in + 0.995 * dc_out
		dc_in = y
		raw[i] = dc_out
		if i < early:
			power += dc_out * dc_out
	var level := 0.35 / maxf(sqrt(power / maxf(early, 1)), 0.0001)
	for i in n:
		var t := i / rate
		var amp := level * (1.0 - tremolo * 0.5 * (1.0 - cos(TAU * tremolo_rate * t))) * _tail(i, n, 0.02)
		out[i] = Vector2.ONE * tanh(raw[i] * amp * drive)
	return out


## Two-operator FM: a sine whose phase another pushes about, at `ratio` of
## its pitch. With `detune`, each side has its own pair, a little apart.
func _fm(instrument: String, note: float, p: Dictionary, bright: bool) -> PackedVector2Array:
	var n := int(param(p, instrument, "length") * rate)
	var out := _buffer(n)
	var hz := midi_hz(note)
	var ratio := param(p, instrument, "ratio")
	var index := param(p, instrument, "bright") if bright else param(p, instrument, "index")
	var sustain := param(p, instrument, "sustain")
	var index_decay := param(p, instrument, "index_decay")
	var attack := param(p, instrument, "attack")
	var decay := param(p, instrument, "decay")
	var tine := param(p, instrument, "tine")
	var detune := param(p, instrument, "detune")
	var vibrato := param(p, instrument, "vibrato")
	var vibrato_rate := param(p, instrument, "vibrato_rate")
	var tremolo := param(p, instrument, "tremolo")
	var tremolo_rate := param(p, instrument, "tremolo_rate")
	var drive := param(p, instrument, "drive")
	var left := [(hz - detune * 0.5) / rate, 0.0, 0.0]
	# Carrier and modulator start together on both sides: offset, a 1:1
	# pair would sit off centre.
	var right := [(hz + detune * 0.5) / rate, 0.25, 0.25]
	var tine_step := hz * 14.0 / rate
	var tine_phase := 0.0
	for i in n:
		var t := i / rate
		var bend := _vibrato(t, vibrato, vibrato_rate)
		var depth := sustain + (index - sustain) * exp(-t / index_decay)
		var l := _fm_step(left, bend, ratio, depth)
		var r := _fm_step(right, bend, ratio, depth) if detune > 0.0 else l
		var ping := 0.0
		if tine > 0.0 and t < 0.2:
			tine_phase = fmod(tine_phase + tine_step * bend, 1.0)
			ping = tine * sin(TAU * tine_phase) * exp(-t / 0.02)
		var amp := minf(t / attack, 1.0) * exp(-t / decay) * _tail(i, n, 0.02)
		amp *= 1.0 - tremolo * 0.5 * (1.0 - cos(TAU * tremolo_rate * t))
		out[i] = Vector2(tanh((l + ping) * amp * drive), tanh((r + ping) * amp * drive)) * 0.8
	return out


## Moves an FM pair ([carrier step, carrier phase, modulator phase]) on a
## frame, returning its sample.
static func _fm_step(pair: Array, bend: float, ratio: float, depth: float) -> float:
	var step: float = pair[0] * bend
	pair[1] = fmod(pair[1] + step, 1.0)
	pair[2] = fmod(pair[2] + step * ratio, 1.0)
	return sin(TAU * pair[1] + depth * sin(TAU * pair[2]))


## How far a held note's pitch is bent at `t`: a vibrato of `depth`
## semitones that swells in over its first quarter second.
static func _vibrato(t: float, depth: float, speed: float) -> float:
	if depth <= 0.0:
		return 1.0
	return pow(2.0, depth * minf(t / 0.25, 1.0) * sin(TAU * speed * t) / 12.0)


func kick(p: Dictionary) -> PackedVector2Array:
	if model(p, "kick") == "gong":
		return _gong(p)
	return _analog_kick(p)


## An electronic kick: a sine swept down fast, with a click on top.
func _analog_kick(p: Dictionary) -> PackedVector2Array:
	var n := int(param(p, "kick", "length") * rate)
	var out := _buffer(n)
	var low: float = param(p, "kick", "low")
	var high: float = param(p, "kick", "high")
	var sweep: float = param(p, "kick", "sweep")
	var decay: float = param(p, "kick", "decay")
	var drive: float = param(p, "kick", "drive")
	var click: float = param(p, "kick", "click")
	var phase := 0.0
	for i in n:
		var t := i / rate
		phase += (low + high * exp(-t / sweep)) / rate
		var body := sin(TAU * phase) * exp(-t / decay)
		var tick := _noise.randf_range(-1.0, 1.0) * exp(-t / 0.002) * click
		out[i] = Vector2.ONE * tanh((body + tick) * drive) * _tail(i, n, 0.03)
	return out


## A gong: a low FM clang whose overtones die before its hum does, each side
## a little apart so it beats, with the mallet's thud on top.
func _gong(p: Dictionary) -> PackedVector2Array:
	var n := int(param(p, "kick", "length") * rate)
	var out := _buffer(n)
	var pitch := param(p, "kick", "pitch")
	var beat := param(p, "kick", "beat")
	var ratio := param(p, "kick", "ratio")
	var index := param(p, "kick", "index")
	var decay := param(p, "kick", "decay")
	var strike := param(p, "kick", "strike")
	var left := [(pitch - beat * 0.5) / rate, 0.0, 0.0]
	var right := [(pitch + beat * 0.5) / rate, 0.0, 0.0]
	var thud := Svf.new(rate)
	for i in n:
		var t := i / rate
		var depth := index * exp(-t / (decay * 0.4))
		var amp := minf(t / 0.004, 1.0) * exp(-t / decay) * _tail(i, n, 0.1)
		var hit := thud.low(_noise.randf_range(-1.0, 1.0), 400.0, 0.5) * strike * exp(-t / 0.03)
		out[i] = Vector2(_fm_step(left, 1.0, ratio, depth) * amp + hit, _fm_step(right, 1.0, ratio, depth) * amp + hit) * 0.9
	return out


func snare(p: Dictionary) -> PackedVector2Array:
	if model(p, "snare") == "tuned":
		return _tuned(p)
	return _analog_snare(p)


## A snare: band-passed noise over a short tone.
func _analog_snare(p: Dictionary) -> PackedVector2Array:
	var n := int(param(p, "snare", "length") * rate)
	var out := _buffer(n)
	var tone_hz: float = param(p, "snare", "tone")
	var band: float = param(p, "snare", "noise")
	var decay: float = param(p, "snare", "decay")
	var filter := Svf.new(rate)
	for i in n:
		var t := i / rate
		var noise := filter.band(_noise.randf_range(-1.0, 1.0), band, 0.4) * exp(-t / decay)
		var body := sin(TAU * tone_hz * t) * exp(-t / 0.05) * 0.5
		out[i] = Vector2.ONE * (noise * 1.3 + body) * _tail(i, n, 0.02)
	return out


## A pitched hit: a sine struck `bend` octaves sharp and falling to pitch,
## with a click of band-passed noise.
func _tuned(p: Dictionary) -> PackedVector2Array:
	var n := int(param(p, "snare", "length") * rate)
	var out := _buffer(n)
	var pitch := param(p, "snare", "pitch")
	var bend := param(p, "snare", "bend")
	var bend_time := param(p, "snare", "bend_time")
	var decay := param(p, "snare", "decay")
	var noise := param(p, "snare", "noise")
	var band := param(p, "snare", "band")
	var noise_decay := param(p, "snare", "noise_decay")
	var filter := Svf.new(rate)
	var phase := 0.0
	for i in n:
		var t := i / rate
		phase = fmod(phase + pitch * pow(2.0, bend * exp(-t / bend_time)) / rate, 1.0)
		var body := sin(TAU * phase) * exp(-t / decay)
		var click := filter.band(_noise.randf_range(-1.0, 1.0), band, 0.6) * noise * exp(-t / noise_decay)
		out[i] = Vector2.ONE * (body + click * 1.3) * minf(t / 0.0005, 1.0) * _tail(i, n, 0.02)
	return out


## A hat; `decay` sets how open it rings. High-passed noise, or as metal,
## six clashing square waves.
func hat(decay: float, p: Dictionary) -> PackedVector2Array:
	var ring := decay * param(p, "hat", "ring")
	var n := int((ring * 5.0 + 0.01) * rate)
	var out := _buffer(n)
	var cutoff: float = param(p, "hat", "cutoff")
	var filter := Svf.new(rate)
	if model(p, "hat") == "metal":
		var pitch := param(p, "hat", "pitch")
		var steps := PackedFloat64Array()
		var phases := PackedFloat64Array()
		for r in [1.0, 1.4471, 1.617, 1.9265, 2.5028, 2.6637]:
			steps.push_back(pitch * r / rate)
			phases.push_back(_noise.randf())
		var tone_filter := Svf.new(rate)
		for i in n:
			var t := i / rate
			var x := 0.0
			for o in 6:
				phases[o] = fmod(phases[o] + steps[o], 1.0)
				x += _pulse(phases[o], steps[o], 0.5)
			x = filter.high(tone_filter.band(x, cutoff, 0.6), cutoff * 0.5, 0.2)
			out[i] = Vector2.ONE * x * 0.3 * exp(-t / ring) * _tail(i, n, 0.005)
		return out
	for i in n:
		var t := i / rate
		var x := filter.high(_noise.randf_range(-1.0, 1.0), cutoff, 0.2)
		out[i] = Vector2.ONE * x * exp(-t / ring) * _tail(i, n, 0.005)
	return out


## A low, uneasy hum as a seamless two-second loop: a note and one half a
## cycle a second off it, beating against each other, with a little edge.
## Both land on whole cycles per loop, so it's rarely quite in tune.
func drone(note: float) -> PackedVector2Array:
	var n := int(2.0 * rate)
	var out := _buffer(n)
	var hz := roundf(midi_hz(note) * 2.0) / 2.0
	for i in n:
		var t := i / rate
		var a := sin(TAU * hz * t) + 0.3 * sin(TAU * 2.0 * hz * t) + 0.12 * sin(TAU * 3.0 * hz * t)
		var b := sin(TAU * (hz + 0.5) * t) + 0.3 * sin(TAU * 2.0 * (hz + 0.5) * t)
		out[i] = Vector2(a + 0.6 * b, 0.6 * a + b) * 0.35
	return out


## Noise swept up through a band-pass, swelling to a sudden stop: the lift
## into something new. Played at whatever speed makes it last a bar.
func riser() -> PackedVector2Array:
	var n := int(2.0 * rate)
	var out := _buffer(n)
	var left := Svf.new(rate)
	var right := Svf.new(rate)
	for i in n:
		var x := float(i) / n
		var at := 300.0 * pow(7000.0 / 300.0, x)
		var amp := x * x * _tail(i, n, 0.004)
		out[i] = Vector2(left.band(_noise.randf_range(-1.0, 1.0), at, 1.2), right.band(_noise.randf_range(-1.0, 1.0), at, 1.2)) * amp
	return out


## A wide crash cymbal: bright noise, different each side, ringing out.
func crash() -> PackedVector2Array:
	var n := int(2.5 * rate)
	var out := _buffer(n)
	var left := Svf.new(rate)
	var right := Svf.new(rate)
	for i in n:
		var t := i / rate
		var amp := exp(-t / 0.7) * _tail(i, n, 0.1)
		out[i] = Vector2(left.high(_noise.randf_range(-1.0, 1.0), 4500.0, 0.3), right.high(_noise.randf_range(-1.0, 1.0), 4500.0, 0.3)) * amp
	return out




static func _buffer(n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(n)
	return out


## A saw with its step smoothed (PolyBLEP), so high notes don't alias.
static func _saw(phase: float, step: float) -> float:
	return 2.0 * phase - 1.0 - _blep(phase, step)


static func _pulse(phase: float, step: float, width: float) -> float:
	return _saw(phase, step) - _saw(fmod(phase + width, 1.0), step)


static func _blep(t: float, dt: float) -> float:
	if t < dt:
		t /= dt
		return t + t - t * t - 1.0
	if t > 1.0 - dt:
		t = (t - 1.0) / dt
		return t * t + t + t + 1.0
	return 0.0


## Fades the last `seconds` of a sound so it doesn't end on a click.
func _tail(i: int, n: int, seconds: float) -> float:
	return clampf((n - i) / (seconds * rate), 0.0, 1.0)


## A state-variable filter (Zavalishin's TPT form), stable while its
## cutoff sweeps. `resonance` runs 0 to just under 2.
class Svf:
	## Resonance stops short of 2, where the filter would run away.
	const MAX_RESONANCE := 1.9
	var rate: float
	var _ic1 := 0.0
	var _ic2 := 0.0
	var _v1 := 0.0
	var _v2 := 0.0
	var _k := 2.0
	## Coefficients, kept until the cutoff or resonance changes.
	var _cutoff := -1.0
	var _resonance := -1.0
	var _a1 := 0.0
	var _a2 := 0.0
	var _a3 := 0.0

	func _init(sample_rate: float) -> void:
		rate = sample_rate

	func low(x: float, cutoff: float, resonance: float) -> float:
		_run(x, cutoff, resonance)
		return _v2

	func band(x: float, cutoff: float, resonance: float) -> float:
		_run(x, cutoff, resonance)
		return _v1

	func high(x: float, cutoff: float, resonance: float) -> float:
		_run(x, cutoff, resonance)
		return x - _k * _v1 - _v2

	func _run(x: float, cutoff: float, resonance: float) -> void:
		if cutoff != _cutoff or resonance != _resonance:
			_cutoff = cutoff
			_resonance = resonance
			var g := tan(PI * clampf(cutoff, 20.0, rate * 0.45) / rate)
			# At 2 or more it feeds back without end, and the NaNs it blows up
			# into would jam the delay and reverb for good.
			_k = 2.0 - minf(resonance, MAX_RESONANCE)
			_a1 = 1.0 / (1.0 + g * (g + _k))
			_a2 = g * _a1
			_a3 = g * _a2
		var v3 := x - _ic2
		_v1 = _a1 * _ic1 + _a2 * v3
		_v2 = _ic2 + _a2 * _ic1 + _a3 * v3
		_ic1 = 2.0 * _v1 - _ic1
		_ic2 = 2.0 * _v2 - _ic2


## A pad being rendered (see pad()), a stretch at a time, so it can be
## spread over frames where there's no thread to render it on.
class Pad:
	## Seconds of the loop's end played in first, so the filters have
	## settled into it by the time it starts over.
	const SETTLE := 0.25
	## The loop, once render() says it's done.
	var out: PackedVector2Array
	var _rate: float
	var _loop: float
	var _n: int
	## The next frame to render, counting from the start of the settling.
	var _i := 0
	var _settle: int
	var _phases := PackedFloat64Array()
	var _steps := PackedFloat64Array()
	## As fm: each oscillator's modulator, and how it moves.
	var _fm := false
	var _mod_phases := PackedFloat64Array()
	var _mod_steps := PackedFloat64Array()
	var _index: float
	var _tremolo: float
	var _tremolo_rate: float
	var _width: float
	var _left: Svf
	var _right: Svf
	var _cutoff: float
	var _sweep: float
	var _resonance: float
	var _level: float

	func _init(synth: Instruments, notes: Array, p: Dictionary) -> void:
		_rate = synth.rate
		_fm = Instruments.model(p, "pad") == "fm"
		_loop = Instruments.param(p, "pad", "loop")
		_n = int(_loop * _rate)
		_settle = mini(int(SETTLE * _rate), _n)
		out = Instruments._buffer(_n)
		var cents: float = Instruments.param(p, "pad", "detune")
		var ratio := Instruments.param(p, "pad", "ratio") if _fm else 0.0
		for note in notes:
			for side in [-1.0, 1.0]:
				var hz := roundf(Instruments.midi_hz(note + side * cents / 100.0) * _loop) / _loop
				var step := hz / _rate
				# Where it'll be as the settling starts, so it runs on into
				# the loop just as it would coming round again.
				_phases.push_back(fposmod(synth._noise.randf() + step * (_n - _settle), 1.0))
				_steps.push_back(step)
				if _fm:
					var mod_step := maxf(roundf(hz * ratio * _loop), 1.0) / _loop / _rate
					_mod_phases.push_back(fposmod(synth._noise.randf() + mod_step * (_n - _settle), 1.0))
					_mod_steps.push_back(mod_step)
		_sweep = Instruments.param(p, "pad", "sweep")
		_level = 0.5 / notes.size()
		if _fm:
			_index = Instruments.param(p, "pad", "index")
			_tremolo = Instruments.param(p, "pad", "tremolo")
			_tremolo_rate = maxf(roundf(Instruments.param(p, "pad", "tremolo_rate") * _loop), 1.0) / _loop
			return
		_width = Instruments.param(p, "pad", "width")
		_left = Svf.new(_rate)
		_right = Svf.new(_rate)
		_cutoff = Instruments.param(p, "pad", "cutoff")
		_resonance = Instruments.param(p, "pad", "resonance")

	## Renders up to `frames` more of it; true once it's all done.
	func render(frames: int) -> bool:
		if _fm:
			return _render_fm(frames)
		var count := _phases.size()
		var stop := mini(_i + frames, _settle + _n)
		for i in range(_i, stop):
			# Where in the loop this frame falls.
			var at := i - _settle + (_n if i < _settle else 0)
			var l := 0.0
			var r := 0.0
			for o in count:
				var step := _steps[o]
				var phase := _phases[o] + step
				if phase >= 1.0:
					phase -= 1.0
				_phases[o] = phase
				var s := Instruments._pulse(phase, step, _width) if _width > 0.0 else Instruments._saw(phase, step)
				if o % 2 == 0:
					l += s
				else:
					r += s
			# Only moves every 64 frames, so the filter needn't recalculate.
			var t := float(at - at % 64) / _rate
			var cutoff := _cutoff + _sweep * sin(TAU * t / _loop - PI / 2.0)
			var y := Vector2(_left.low(l, cutoff, _resonance), _right.low(r, cutoff, _resonance)) * _level
			if i >= _settle:
				out[at] = y
		_i = stop
		return _i >= _settle + _n

	## As render(), as fm. Nothing here has settling to do, but the phases
	## start where the analog pad's would, so it's rendered the same way.
	func _render_fm(frames: int) -> bool:
		var count := _phases.size()
		var stop := mini(_i + frames, _settle + _n)
		for i in range(_i, stop):
			var at := i - _settle + (_n if i < _settle else 0)
			var t := float(at) / _rate
			var depth := maxf(_index + _sweep * sin(TAU * t / _loop - PI / 2.0), 0.0)
			var l := 0.0
			var r := 0.0
			for o in count:
				var phase := fmod(_phases[o] + _steps[o], 1.0)
				var mod_phase := fmod(_mod_phases[o] + _mod_steps[o], 1.0)
				_phases[o] = phase
				_mod_phases[o] = mod_phase
				var s := sin(TAU * phase + depth * sin(TAU * mod_phase))
				if o % 2 == 0:
					l += s
				else:
					r += s
			var amp := _level * (1.0 - _tremolo * 0.5 * (1.0 - cos(TAU * _tremolo_rate * t)))
			if i >= _settle:
				out[at] = Vector2(l, r) * amp
		_i = stop
		return _i >= _settle + _n
