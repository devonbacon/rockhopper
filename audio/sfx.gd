extends Node
## Sound effects, an autoload: each made by the soundtrack's synth from its
## settings in Sounds, rendered once on a worker thread, and played here or
## out in the world. Game.sound() plays one for everyone in earshot.
##
## An effect is one instrument: a drum (kick, snare, hat), a note or a run
## of notes on the lead or bass, or filtered noise, which can loop while
## held (see hold()). `level` is its loudness, `vary` how many semitones it
## wanders each time, and `range` how far off it carries in metres; 0
## plays it flat, wherever you are. Nothing plays headless.

## An effect's been made (again), and can be played.
signal made(sound_name: String)

const RATE := 32000.0
## What an effect can be made with: the synth's instruments, or noise.
const INSTRUMENTS: Array[String] = ["snare", "kick", "hat", "lead", "bass", "noise"]
## Noise's settings, as Instruments.PARAMS has them: swept from `cutoff`
## to `sweep` through a resonant low-pass.
const NOISE := {
	"noise": {
		"length": [0.4, 0.05, 4.0],
		"cutoff": [1200.0, 50.0, 12000.0],
		"sweep": [1200.0, 50.0, 12000.0],
		"resonance": [0.5, 0.0, 1.95],
		"attack": [0.01, 0.001, 1.0],
		"decay": [0.2, 0.01, 4.0],
	},
}
## The most of one effect playing at once.
const MAX_EACH := 6
const RenderQueue := preload("res://audio/music.gd").Renderer

var volume := 0.8:
	set(value):
		volume = clampf(value, 0.0, 1.0)
		if _bus > 0:
			AudioServer.set_bus_volume_db(_bus, linear_to_db(maxf(volume, 0.0001)))
			AudioServer.set_bus_mute(_bus, volume <= 0.0)

var _bus := 0
var _renderer: RenderQueue
var _streams: Dictionary[String, AudioStreamWAV] = {}
var _players: Dictionary[String, Array] = {}
var _loops: Dictionary[String, AudioStreamPlayer] = {}
var _silent := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = DisplayServer.get_name() == "headless"
	if _silent:
		set_process(false)
		return
	_bus = AudioServer.bus_count
	AudioServer.add_bus(_bus)
	AudioServer.set_bus_name(_bus, "Sfx")
	AudioServer.set_bus_send(_bus, "Master")
	AudioServer.add_bus_effect(_bus, AudioEffectHardLimiter.new())
	var settings := ConfigFile.new()
	if settings.load("user://settings.cfg") == OK:
		volume = settings.get_value("audio", "sfx", volume)
	volume = volume
	_renderer = RenderQueue.new(RATE)
	for sound_name: String in Sounds.data.sfx:
		reload(sound_name)


func save_volume() -> void:
	var settings := ConfigFile.new()
	settings.load("user://settings.cfg")
	settings.set_value("audio", "sfx", volume)
	settings.save("user://settings.cfg")


## Makes an effect again from its settings in Sounds.
func reload(sound_name: String) -> void:
	if _silent or !Sounds.data.sfx.has(sound_name):
		return
	var def: Dictionary = Sounds.data.sfx[sound_name].duplicate(true)
	var synth := _renderer.synth
	_renderer.request(sound_name, func() -> Variant: return render(synth, def))


func _process(_delta: float) -> void:
	var done := _renderer.poll()
	for sound_name in done:
		var def: Dictionary = Sounds.data.sfx.get(sound_name, {})
		_streams[sound_name] = _wav(done[sound_name], def.get("loop", false))
		if _loops.has(sound_name):
			_loops[sound_name].stream = _streams[sound_name]
			_loops[sound_name].play()
		made.emit(sound_name)


## Plays an effect: at `at` in the world, or flat if it's INF or the effect
## carries no range.
func play(sound_name: StringName, at := Vector3.INF) -> void:
	var stream: AudioStreamWAV = _streams.get(sound_name)
	if _silent or !stream:
		return
	var def: Dictionary = Sounds.data.sfx[sound_name]
	var playing: Array = _players.get_or_add(sound_name, [])
	playing.assign(playing.filter(func(each: Variant) -> bool: return is_instance_valid(each)))
	if playing.size() >= MAX_EACH:
		return
	var vary := float(def.get("vary", 0.0))
	var reach := float(def.get("range", 0.0))
	var player: Node
	if at == Vector3.INF or reach <= 0.0:
		var flat := AudioStreamPlayer.new()
		flat.stream = stream
		flat.bus = "Sfx"
		flat.volume_db = linear_to_db(float(def.get("level", 0.5)))
		flat.pitch_scale = pow(2.0, randf_range(-vary, vary) / 12.0)
		flat.finished.connect(flat.queue_free)
		add_child(flat)
		flat.play()
		player = flat
	else:
		var placed := AudioStreamPlayer3D.new()
		placed.stream = stream
		placed.bus = "Sfx"
		placed.volume_db = linear_to_db(float(def.get("level", 0.5)))
		placed.pitch_scale = pow(2.0, randf_range(-vary, vary) / 12.0)
		placed.unit_size = reach / 6.0
		placed.max_distance = reach
		placed.finished.connect(placed.queue_free)
		add_child(placed)
		placed.global_position = at
		placed.play()
		player = placed
	playing.push_back(player)


## Keeps a looping effect going while `on`.
func hold(sound_name: StringName, on: bool) -> void:
	if _silent:
		return
	var player: AudioStreamPlayer = _loops.get(sound_name)
	if on and !player:
		var stream: AudioStreamWAV = _streams.get(sound_name)
		if !stream:
			return
		player = AudioStreamPlayer.new()
		player.stream = stream
		player.bus = "Sfx"
		player.volume_db = linear_to_db(float(Sounds.data.sfx[sound_name].get("level", 0.5)))
		add_child(player)
		player.play()
		_loops[sound_name] = player
	elif !on and player:
		player.queue_free()
		_loops.erase(sound_name)


## An effect's sound, from its settings, its loudest moment brought to
## just under full so `level` alone says how loud it is.
static func render(synth: Instruments, def: Dictionary) -> PackedVector2Array:
	var sound := _render(synth, def)
	var peak := 0.0
	for v in sound:
		peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
	if peak > 0.0:
		for i in sound.size():
			sound[i] *= 0.9 / peak
	return sound


static func _render(synth: Instruments, def: Dictionary) -> PackedVector2Array:
	var settings: Dictionary = def.get("settings", {})
	match str(def.get("instrument", "snare")):
		"kick":
			return synth.kick(settings)
		"hat":
			return synth.hat(float(def.get("decay", 0.05)), settings)
		"noise":
			return _noise(synth, settings, def.get("loop", false))
		"lead", "bass":
			return _notes(synth, def)
	return synth.snare(settings)


## A note, or a run of them `gap` seconds apart, as semitones from `note`.
static func _notes(synth: Instruments, def: Dictionary) -> PackedVector2Array:
	var instrument := str(def.instrument)
	var settings: Dictionary = def.get("settings", {})
	var root := float(def.get("note", 60.0))
	var offsets: Array = def.get("notes", [0])
	var gap := int(float(def.get("gap", 0.0)) * synth.rate)
	var sounds: Array[PackedVector2Array] = []
	var n := 0
	for i in offsets.size():
		sounds.push_back(synth.tone(instrument, root + float(offsets[i]), settings))
		n = maxi(n, sounds[i].size() + gap * i)
	var out := PackedVector2Array()
	out.resize(n)
	for i in sounds.size():
		var sound := sounds[i]
		for j in sound.size():
			out[gap * i + j] += sound[j]
	return out


static func _noise_param(p: Dictionary, name: String) -> float:
	var own: Variant = p.get("noise")
	if own is Dictionary and own.has(name):
		return float(own[name])
	return float(NOISE.noise[name][0])


## Noise through a resonant low-pass sweeping from `cutoff` to `sweep`. As
## a loop it holds steady, its end faded into its start.
static func _noise(synth: Instruments, p: Dictionary, loop: bool) -> PackedVector2Array:
	var rate := synth.rate
	var n := int(_noise_param(p, "length") * rate)
	var fade := int(0.05 * rate) if loop else 0
	var cutoff := _noise_param(p, "cutoff")
	var sweep := _noise_param(p, "sweep")
	var resonance := _noise_param(p, "resonance")
	var attack := _noise_param(p, "attack")
	var decay := _noise_param(p, "decay")
	var left := Instruments.Svf.new(rate)
	var right := Instruments.Svf.new(rate)
	var rng := RandomNumberGenerator.new()
	var out := PackedVector2Array()
	out.resize(n + fade)
	for i in n + fade:
		var t := i / rate
		var at := cutoff * pow(sweep / cutoff, minf(float(i) / n, 1.0))
		var amp := 1.0 if loop else minf(t / attack, 1.0) * exp(-maxf(t - attack, 0.0) / decay) * clampf((n - i) / (0.01 * rate), 0.0, 1.0)
		out[i] = Vector2(left.low(rng.randf_range(-1.0, 1.0), at, resonance), right.low(rng.randf_range(-1.0, 1.0), at, resonance)) * amp * 0.6
	if loop:
		for i in fade:
			var x := float(i) / fade
			out[i] = out[i] * x + out[n + i] * (1.0 - x)
		out.resize(n)
	return out


static func _wav(sound: PackedVector2Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(sound.size() * 4)
	for i in sound.size():
		bytes.encode_s16(i * 4, int(clampf(sound[i].x, -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(sound[i].y, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = int(RATE)
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = sound.size()
	return wav
