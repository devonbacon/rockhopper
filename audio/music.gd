extends Node
## The soundtrack, an autoload: a synth score in D minor after Tron:
## Legacy, a pulsing sixteenth-note bass, arpeggios and huge low brass,
## with Deep Rock Galactic's rock drums and chugging guitar for when the
## swarm comes. The synth (Instruments) and the voice mixer are Real-Time
## Logistics'.
##
## The game sets how things stand (in_game, night, danger, alarm, final),
## and the score picks a mood from them each bar:
## - DAY: a wide pad and a soft eighth-note bass, with a quiet arpeggio
##   and hats every other phrase.
## - NIGHT: the bass pulses in sixteenths, pumping, the arpeggio runs, and
##   low brass swells on the chord changes; every other phrase the brass
##   plays the theme.
## - SWARM: rock drums, palm-muted guitar on a 3-3-2, the theme every
##   phrase over a doubled low brass, and a riser into every other phrase.
## - SIEGE (the pod under attack, or the last minute): four on the floor,
##   open hats, the arpeggio an octave up, a crash every phrase.
## It climbs a mood the next bar, with a crash, and comes back down only
## after four calmer bars, so a fight's music outlasts the fight a little.
##
## Every sound is rendered ahead of time on a worker thread; it starts
## once they're all ready. Nothing plays headless.

enum Mood { DAY, NIGHT, SWARM, SIEGE }

const RATE := 32000.0
const BPM := 116.0
## Chords, two bars each, eight bars a phrase: semitones from D, and minor
## or major.
const DAY_CHORDS := [[0, "m"], [-4, "M"], [3, "M"], [-2, "M"]]
const NIGHT_CHORDS := [[0, "m"], [-4, "M"], [-7, "m"], [-5, "M"]]
## The theme, over the night chords: [beat in the phrase, note, beats].
const THEME := [[0, 62, 3], [3, 65, 1], [4, 69, 4], [8, 70, 3], [11, 69, 1], [12, 65, 4], [16, 67, 3], [19, 70, 1], [20, 74, 4], [24, 73, 2], [26, 76, 2], [28, 69, 4]]
## Which of the six arpeggio tones each sixteenth plays: up and back down.
const ARP := [0, 1, 2, 3, 4, 5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 5]
## Bars calmer than the mood before it drops.
const CALM_BARS := 4
const PAD_FADE := 0.6

const PAD := { "model": "analog", "analog": { "loop": 4.0, "detune": 12.0, "cutoff": 800.0, "sweep": 600.0, "resonance": 0.4 } }
const BASS := { "analog": { "length": 0.14, "detune": 0.004, "sub": 0.9, "floor": 110.0, "bright": 2800.0, "dark": 850.0, "env": 0.04, "decay": 0.09, "resonance": 1.0, "drive": 1.7 } }
const ARP_SYNTH := { "analog": { "length": 0.22, "saw": 0.7, "pulse": 0.3, "width": 0.3, "cutoff": 900.0, "env": 3500.0, "env_decay": 0.05, "decay": 0.09, "resonance": 1.2 } }
## Brass rises into its note, as brass does: the index swells to `sustain`.
const BRASS := { "model": "fm", "fm": { "ratio": 1.0, "index": 0.6, "sustain": 2.4, "index_decay": 0.35, "attack": 0.07, "vibrato": 0.06, "vibrato_rate": 5.0, "drive": 1.6, "detune": 1.2 } }
const GUITAR_MUTE := { "model": "pluck", "pluck": { "length": 0.2, "decay": 0.3, "damping": 0.7, "pick": 1800.0, "position": 0.2, "drive": 4.5, "strum": 0.005 } }
const GUITAR_OPEN := { "model": "pluck", "pluck": { "length": 1.4, "decay": 2.5, "damping": 0.4, "pick": 3000.0, "position": 0.15, "drive": 5.0, "strum": 0.012 } }
const KICK := { "analog": { "length": 0.4, "low": 46.0, "high": 140.0, "drive": 2.0, "click": 0.5 } }
const SNARE := { "analog": { "tone": 180.0, "noise": 2200.0, "decay": 0.12 } }
const TOM := { "model": "tuned", "tuned": { "length": 1.4, "pitch": 62.0, "bend": 0.9, "bend_time": 0.06, "decay": 0.55, "noise": 0.25, "band": 700.0, "noise_decay": 0.03 } }
const HAT := { "analog": { "cutoff": 8000.0 } }
const LEVELS := { "pad": 0.3, "bass": 0.2, "arp": 0.1, "brass": 0.1, "low_brass": 0.08, "braam": 0.13, "guitar": 0.17, "kick": 0.32, "snare": 0.5, "hat": 0.08, "tom": 0.12, "crash": 0.18, "riser": 0.15 }

## Set by the game.
var in_game := false
var night := false
## Spiders near you.
var danger := 0
## The pod's being bitten.
var alarm := false
## The last minute before launch.
var final := false

var mood := Mood.DAY
var volume := 0.6:
	set(value):
		volume = clampf(value, 0.0, 1.0)
		if _bus > 0:
			AudioServer.set_bus_volume_db(_bus, linear_to_db(maxf(volume, 0.0001)))
			AudioServer.set_bus_mute(_bus, volume <= 0.0)

var _bus := 0
var _dry: AudioStreamGeneratorPlayback
var _wet: AudioStreamGeneratorPlayback
var _renderer := Renderer.new(RATE)
var _sounds: Dictionary[String, PackedVector2Array] = {}
var _requested: Dictionary[String, bool] = {}
var _playing := false
var _voices: Array[Voice] = []
var _pad: Voice
var _pad_name := ""
## Beats written so far, and the next sixteenth to start.
var _beat := 0.0
var _step := 0
var _calm := 0
## The theme's notes by the sixteenth of the phrase they start on.
var _theme_at := {}
## Debug, from user args: a mood to hold (mood=0-3), and a WAV to record
## the music to (record=path.wav, for record_for= seconds, then quit).
var _force := -1
var _record_to := ""
var _record_for := 30.0
var _recorder: AudioEffectRecord
## Debug: only sounds whose names start with this play (solo=).
var _solo := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_bus = _make_bus("Music", "Master")
	AudioServer.add_bus_effect(_bus, AudioEffectHardLimiter.new())
	var wet_bus := _make_bus("MusicFx", "Music")
	var delay := AudioEffectDelay.new()
	delay.dry = 1.0
	delay.tap1_pan = -0.6
	delay.tap2_pan = 0.6
	delay.tap1_level_db = -9.0
	delay.tap2_level_db = -12.0
	delay.feedback_active = true
	delay.feedback_level_db = -14.0
	delay.feedback_lowpass = 3000.0
	var beat_ms := 60000.0 / BPM
	delay.tap1_delay_ms = 0.75 * beat_ms
	delay.tap2_delay_ms = 1.5 * beat_ms
	delay.feedback_delay_ms = 1.5 * beat_ms
	AudioServer.add_bus_effect(wet_bus, delay)
	var reverb := AudioEffectReverb.new()
	reverb.spread = 1.0
	reverb.room_size = 0.85
	reverb.damping = 0.4
	reverb.dry = 0.85
	reverb.wet = 0.35
	AudioServer.add_bus_effect(wet_bus, reverb)
	var settings := ConfigFile.new()
	if settings.load("user://settings.cfg") == OK:
		volume = settings.get_value("audio", "music", volume)
	volume = volume
	_dry = _make_player("Music")
	_wet = _make_player("MusicFx")
	for note: Array in THEME:
		_theme_at[int(note[0]) * 4] = note
	_request_all()
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts[0] == "mood" and parts.size() > 1:
			_force = int(parts[1])
		elif parts[0] == "record" and parts.size() > 1:
			_record_to = parts[1]
		elif parts[0] == "solo" and parts.size() > 1:
			_solo = parts[1]
		elif parts[0] == "record_for" and parts.size() > 1:
			_record_for = float(parts[1])


func save_volume() -> void:
	var settings := ConfigFile.new()
	settings.load("user://settings.cfg")
	settings.set_value("audio", "music", volume)
	settings.save("user://settings.cfg")


func _process(_delta: float) -> void:
	var done := _renderer.poll()
	for sound_name in done:
		_requested.erase(sound_name)
		_sounds[sound_name] = done[sound_name]
	if !_playing:
		if !_requested.is_empty():
			return
		_playing = true
		if _record_to != "":
			_record()
	var frames := mini(_dry.get_frames_available(), _wet.get_frames_available())
	if frames > 0:
		_write(frames)


## Debug: records what the music bus plays, then saves it and quits.
func _record() -> void:
	_recorder = AudioEffectRecord.new()
	AudioServer.add_bus_effect(_bus, _recorder)
	_recorder.set_recording_active(true)
	await get_tree().create_timer(_record_for, true, false, true).timeout
	_recorder.set_recording_active(false)
	_recorder.get_recording().save_to_wav(_record_to)
	print("recorded ", _record_to)
	get_tree().quit()


## The mood things call for now.
func _wanted() -> Mood:
	if _force >= 0:
		return _force as Mood
	if !in_game:
		return Mood.DAY
	if alarm or final:
		return Mood.SIEGE
	if danger >= 3:
		return Mood.SWARM
	if night or danger > 0:
		return Mood.NIGHT
	return Mood.DAY


func _write(n: int) -> void:
	var dry := PackedVector2Array()
	dry.resize(n)
	var wet := PackedVector2Array()
	wet.resize(n)
	var per_frame := BPM / 60.0 / RATE
	while true:
		var at := ceili((_step / 4.0 - _beat) / per_frame)
		if at >= n:
			break
		_trigger(_step, maxi(at, 0))
		_step += 1
	# The pump: the bass and pad duck on every beat once night falls.
	var duck := PackedFloat32Array()
	duck.resize(n)
	if mood >= Mood.NIGHT:
		for i in n:
			duck[i] = exp(-7.0 * fposmod(_beat + i * per_frame, 1.0))
	for voice in _voices:
		_mix(voice, wet if voice.wet else dry, duck, n)
	_voices = _voices.filter(func(v: Voice) -> bool: return !v.done and (v.gain > 0.0 or v.slope > 0.0))
	_dry.push_buffer(dry)
	_wet.push_buffer(wet)
	_beat += n * per_frame


## Starts whatever plays on sixteenth `step`, `at` frames into this block.
func _trigger(step: int, at: int) -> void:
	var bar := step / 16
	var s := step % 16
	var phrase := bar / 8
	var in_phrase := bar % 8
	if s == 0:
		_start_bar(bar, at)
	var chords := NIGHT_CHORDS if mood >= Mood.NIGHT else DAY_CHORDS
	var chord: Array = chords[in_phrase / 2]
	var root: int = chord[0]
	var third := 3 if chord[1] == "m" else 4
	var odd := phrase % 2 == 1

	# Bass: soft eighths by day; a pulsing sixteenth ostinato by night, the
	# octave on each beat's third sixteenth.
	if mood == Mood.DAY:
		if s % 2 == 0:
			_play(_bass(38 + root, false), at, LEVELS.bass * (0.85 if s % 4 == 0 else 0.6), false, 0.0)
	else:
		var octave := 12 if s % 4 == 2 else 0
		_play(_bass(38 + root + octave, mood >= Mood.SWARM), at, LEVELS.bass * (1.0 if s % 4 == 0 else 0.75), false, 0.6)

	# Arpeggio: up and back down the chord over two octaves.
	var tones := [62 + root, 62 + root + third, 62 + root + 7, 74 + root, 74 + root + third, 74 + root + 7]
	var lift := 12 if mood == Mood.SIEGE else 0
	var arp_on := mood >= Mood.NIGHT or (odd and s % 2 == 0)
	if arp_on:
		var voice := _play("arp/%d" % (tones[ARP[s]] + lift), at, LEVELS.arp * (1.0 if s % 4 == 0 else 0.7), true)
		if voice:
			voice.set_pan(-0.35 if s % 2 == 0 else 0.35)

	# Brass: the theme, doubled an octave down when the swarm's here; or a
	# low swell on the chord changes.
	var theme := mood >= Mood.SWARM or (mood == Mood.NIGHT and odd)
	var note: Variant = _theme_at.get(in_phrase * 16 + s)
	if theme and note != null:
		_play(_brass(note[1], note[2]), at, LEVELS.brass, true)
		if mood >= Mood.SWARM:
			_play(_brass(note[1] - 12, note[2]), at, LEVELS.low_brass, true)
	if s == 0 and in_phrase % 2 == 0 and ((mood == Mood.NIGHT and !odd) or (mood >= Mood.SWARM and in_phrase == 0)):
		_play("braam/%d" % root, at, LEVELS.braam, true)

	# Guitar: palm-muted eighths, the power chord ringing on a 3-3-2.
	if mood >= Mood.SWARM and s % 2 == 0:
		var open := s == 0 or s == 6 or s == 12
		_play(("guitar/open/%d" if open else "guitar/mute/%d") % root, at, LEVELS.guitar * (1.0 if open else 0.7))

	# Drums.
	match mood:
		Mood.DAY:
			if odd and s % 2 == 0:
				_play("hat/closed", at, LEVELS.hat * 0.5)
		Mood.NIGHT:
			_play("hat/closed", at, LEVELS.hat * (0.6 if s % 2 == 1 else 0.35))
			if s == 0 and in_phrase % 2 == 0:
				_play("tom", at, LEVELS.tom, true)
			if s == 10 and in_phrase % 4 == 3:
				_play("tom", at, LEVELS.tom * 0.7, true)
		_:
			var kicks := [0, 4, 8, 10, 12] if mood == Mood.SIEGE else [0, 8, 10]
			if kicks.has(s):
				_play("kick", at, LEVELS.kick)
			if s == 4 or s == 12:
				_play("snare", at, LEVELS.snare, true)
			if in_phrase == 7 and s >= 8:
				_play("snare", at, LEVELS.snare * (0.3 + 0.05 * (s - 8)), true)
			if s % 2 == 0:
				_play("hat/closed", at, LEVELS.hat)
			if mood == Mood.SIEGE and s % 4 == 2:
				_play("hat/open", at, LEVELS.hat * 0.9)


## A new bar: the mood moves, the pad changes chord, and the cymbals mark
## the way in.
func _start_bar(bar: int, at: int) -> void:
	var wanted := _wanted()
	var was := mood
	if wanted > mood:
		mood = wanted
		_calm = 0
	elif wanted < mood:
		_calm += 1
		if _calm >= CALM_BARS:
			mood = wanted
			_calm = 0
	else:
		_calm = 0
	var in_phrase := bar % 8
	if mood > was or (mood == Mood.SIEGE and in_phrase == 0):
		_play("crash", at, LEVELS.crash, true)
	if mood >= Mood.SWARM and was < Mood.SWARM:
		_play("guitar/open/%d" % NIGHT_CHORDS[in_phrase / 2][0], at, LEVELS.guitar * 1.3)
	if mood >= Mood.SWARM and in_phrase == 7 and (bar / 8) % 2 == 1:
		_play("riser", at, LEVELS.riser, true)
	var pad_name := "pad/%s/%d" % ["night" if mood >= Mood.NIGHT else "day", in_phrase / 2]
	if pad_name != _pad_name and _sounds.has(pad_name):
		if _pad:
			_pad.fade_to(0.0, PAD_FADE)
		var level: float = LEVELS.pad * [1.0, 0.85, 0.65, 0.6][mood]
		_pad = _play(pad_name, at, 0.0, true, 0.5)
		if !_pad:
			return
		_pad.loop = true
		_pad.hi = level
		_pad.fade_to(level, PAD_FADE)
		_pad_name = pad_name
	elif _pad:
		_pad.fade_to(LEVELS.pad * [1.0, 0.85, 0.65, 0.6][mood], PAD_FADE)


func _bass(note: int, bright: bool) -> String:
	return "bass/%d/%s" % [note, "bright" if bright else "dark"]


func _brass(note: int, beats: int) -> String:
	return "brass/%d/%d" % [note, beats]


## Asks for every sound the score can play.
func _request_all() -> void:
	var synth := _renderer.synth
	for set_name: String in ["day", "night"]:
		var chords: Array = DAY_CHORDS if set_name == "day" else NIGHT_CHORDS
		for i in chords.size():
			var root: int = chords[i][0]
			var third := 3 if chords[i][1] == "m" else 4
			var pad_notes := [50 + root, 50 + root + third, 50 + root + 7, 62 + root]
			_request("pad/%s/%d" % [set_name, i], func() -> Variant: return synth.pad(pad_notes, PAD))
			for octave: int in [0, 12]:
				for bright: bool in [false, true]:
					var note := 38 + root + octave
					_request(_bass(note, bright), func() -> Variant: return synth.bass(note, bright, BASS))
			for base: int in [62, 74, 86]:
				for interval: int in [0, third, 7]:
					var note := base + root + interval
					_request("arp/%d" % note, func() -> Variant: return synth.lead(note, ARP_SYNTH))
			var power := [50 + root, 57 + root, 62 + root]
			_request("guitar/mute/%d" % root, func() -> Variant: return synth.comp(power, GUITAR_MUTE))
			_request("guitar/open/%d" % root, func() -> Variant: return synth.comp(power, GUITAR_OPEN))
			_request("braam/%d" % root, func() -> Variant: return _render_braam(synth, root))
	for note: Array in THEME:
		for octave: int in [0, -12]:
			var pitch: int = note[1] + octave
			var beats: int = note[2]
			_request(_brass(pitch, beats), func() -> Variant: return _render_brass(synth, pitch, beats))
	_request("kick", func() -> Variant: return synth.kick(KICK))
	_request("snare", func() -> Variant: return synth.snare(SNARE))
	_request("tom", func() -> Variant: return synth.snare(TOM))
	_request("hat/closed", func() -> Variant: return synth.hat(0.03, HAT))
	_request("hat/open", func() -> Variant: return synth.hat(0.16, HAT))
	_request("crash", func() -> Variant: return synth.crash())
	_request("riser", func() -> Variant: return synth.riser())


## A brass note held for `beats`, swelling in.
static func _render_brass(synth: Instruments, note: int, beats: int) -> PackedVector2Array:
	var seconds := beats * 60.0 / BPM
	var p: Dictionary = BRASS.duplicate(true)
	p.fm.length = seconds + 0.15
	p.fm.decay = seconds * 2.5
	return synth.lead(note, p)


## A huge low brass blast: root and fifth, two octaves down, swelling and
## dying over a couple of seconds.
static func _render_braam(synth: Instruments, root: int) -> PackedVector2Array:
	var p: Dictionary = BRASS.duplicate(true)
	p.fm.length = 2.6
	p.fm.decay = 1.2
	p.fm.attack = 0.12
	p.fm.sustain = 4.0
	p.fm.drive = 2.2
	var low := synth.lead(26 + root, p)
	var fifth := synth.lead(33 + root, p)
	var octave := synth.lead(38 + root, p)
	for i in low.size():
		low[i] = (low[i] + fifth[i] * 0.7 + octave[i] * 0.5) * 0.6
	return low


func _request(sound_name: String, render: Callable) -> void:
	if !_sounds.has(sound_name) and !_requested.has(sound_name):
		_requested[sound_name] = true
		_renderer.request(sound_name, render)


func _play(sound: String, at: int, gain: float, wet := false, duck := 0.0) -> Voice:
	if !_sounds.has(sound) or (_solo != "" and !sound.begins_with(_solo)):
		return null
	var voice := Voice.new()
	voice.sound = _sounds[sound]
	voice.start = at
	voice.gain = gain
	voice.hi = gain
	voice.wet = wet
	voice.duck = duck
	_voices.push_back(voice)
	return voice


func _mix(voice: Voice, out: PackedVector2Array, duck: PackedFloat32Array, n: int) -> void:
	var sound := voice.sound
	var size := sound.size()
	var pos := voice.pos
	var gain := voice.gain
	var slope := voice.slope
	var lo := voice.lo
	var hi := voice.hi
	var pan := voice.pan
	var ducking := voice.duck
	for i in range(voice.start, n):
		if pos >= size:
			if !voice.loop:
				voice.done = true
				break
			pos -= size
		out[i] += sound[pos] * pan * (gain * (1.0 - ducking * duck[i]))
		pos += 1
		gain = clampf(gain + slope, lo, hi)
	voice.pos = pos
	voice.gain = gain
	voice.start = 0


func _make_bus(bus_name: String, send: String) -> int:
	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send)
	return index


func _make_player(bus_name: String) -> AudioStreamGeneratorPlayback:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate_mode = AudioStreamGenerator.MIX_RATE_CUSTOM
	stream.mix_rate = RATE
	stream.buffer_length = 0.1
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus_name
	add_child(player)
	player.play()
	return player.get_stream_playback()


## One sound playing.
class Voice:
	var sound: PackedVector2Array
	## Where it's up to, in frames.
	var pos := 0
	## Frames into the current block before it starts.
	var start := 0
	## Whether it goes round again at the end (pads).
	var loop := false
	var done := false
	## Its level, and how that's moving: per frame, and the bounds it
	## moves between.
	var gain := 1.0
	var slope := 0.0
	var lo := 0.0
	var hi := 1.0
	## Whether it goes through the delay and reverb.
	var wet := false
	## How much the pump ducks it.
	var duck := 0.0
	var pan := Vector2.ONE

	## Moves its level to `level` over `seconds`, and holds it there.
	func fade_to(level: float, seconds: float) -> void:
		slope = (level - gain) / maxf(seconds * RATE, 1.0)
		lo = minf(level, gain)
		hi = maxf(level, gain)

	func set_pan(side: float) -> void:
		pan = Vector2(minf(1.0, 1.0 - side), minf(1.0, 1.0 + side))


## Renders sounds on a worker thread, one after another in the order asked
## for, handing them back as they're done.
class Renderer:
	const PAD_STRETCH := 2048
	var synth: Instruments
	var _mutex := Mutex.new()
	## [[name, Callable]] waiting. A Callable gives the sound, or a Pad to
	## render it.
	var _queue: Array = []
	var _done: Dictionary[String, PackedVector2Array] = {}
	var _task := -1

	func _init(rate: float) -> void:
		synth = Instruments.new(rate)

	func request(sound_name: String, render: Callable) -> void:
		_mutex.lock()
		_queue.push_back([sound_name, render])
		_mutex.unlock()

	## Returns what's finished since last time, and keeps the work going.
	func poll() -> Dictionary[String, PackedVector2Array]:
		if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
		_mutex.lock()
		var done := _done
		_done = {}
		var waiting := !_queue.is_empty()
		_mutex.unlock()
		if _task < 0 and waiting:
			_task = WorkerThreadPool.add_task(_work, false, "Render music")
		return done

	func _work() -> void:
		while true:
			_mutex.lock()
			if _queue.is_empty():
				_mutex.unlock()
				return
			var job: Array = _queue.pop_front()
			_mutex.unlock()
			var sound: Variant = job[1].call()
			if sound is Instruments.Pad:
				while !sound.render(PAD_STRETCH):
					pass
				sound = sound.out
			_mutex.lock()
			_done[job[0]] = sound
			_mutex.unlock()
