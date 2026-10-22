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
## The tempo, chords, theme, each mood's step patterns, the levels and the
## instruments are data, in Sounds; the sound editor changes them as it
## plays, and reload() makes again only the sounds whose settings changed.
## Every sound is rendered ahead of time on a worker thread; it starts
## once they're all ready. Nothing plays headless.

enum Mood { DAY, NIGHT, SWARM, SIEGE }

const RATE := 32000.0
const MOODS: Array[String] = ["day", "night", "swarm", "siege"]
## What each of the score's instruments is to the synth.
const KINDS := { "pad": "pad", "bass": "bass", "arp": "lead", "brass": "lead", "guitar_mute": "comp", "guitar_open": "comp", "kick": "kick", "snare": "snare", "tom": "snare", "hat": "hat" }
## What can be muted: the first part of a sound's name.
const PARTS: Array[String] = ["pad", "bass", "arp", "brass", "braam", "guitar", "kick", "snare", "hat", "tom", "crash", "riser"]
const NOTE_NAMES := { "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11 }
## Bars calmer than the mood before it drops.
const CALM_BARS := 4
const PAD_FADE := 0.6

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
## A mood to hold, or -1 to follow the game: the editor's, or mood=0-3.
var hold_mood := -1
## Parts silenced, by PARTS name: the editor's.
var muted: Dictionary[String, bool] = {}
var volume := 0.6:
	set(value):
		volume = clampf(value, 0.0, 1.0)
		if _bus > 0:
			AudioServer.set_bus_volume_db(_bus, linear_to_db(maxf(volume, 0.0001)))
			AudioServer.set_bus_mute(_bus, volume <= 0.0)

var bpm := 116.0
## Read from Sounds: [[semitones from D, third]], by "day" and "night".
var _chords := {}
## The theme's notes by the sixteenth of the phrase they start on:
## [beat, note, beats].
var _theme_at := {}
var _arp_order: Array[int] = []
var _levels: Dictionary = {}
var _patterns: Dictionary = {}
## The instruments' settings as last rendered, to see what's changed.
var _rendered := {}

var _bus := 0
var _delay: AudioEffectDelay
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
## Debug, from user args: a WAV to record the music to (record=path.wav,
## for record_for= seconds, then quit).
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
	_delay = AudioEffectDelay.new()
	_delay.dry = 1.0
	_delay.tap1_pan = -0.6
	_delay.tap2_pan = 0.6
	_delay.tap1_level_db = -9.0
	_delay.tap2_level_db = -12.0
	_delay.feedback_active = true
	_delay.feedback_level_db = -14.0
	_delay.feedback_lowpass = 3000.0
	AudioServer.add_bus_effect(wet_bus, _delay)
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
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts[0] == "mood" and parts.size() > 1:
			hold_mood = int(parts[1])
		elif parts[0] == "record" and parts.size() > 1:
			_record_to = parts[1]
		elif parts[0] == "solo" and parts.size() > 1:
			_solo = parts[1]
		elif parts[0] == "record_for" and parts.size() > 1:
			_record_for = float(parts[1])
	reload()


func save_volume() -> void:
	var settings := ConfigFile.new()
	settings.load("user://settings.cfg")
	settings.set_value("audio", "music", volume)
	settings.save("user://settings.cfg")


## Takes up the score as Sounds has it now, from the next sixteenth, and
## makes again whatever sounds that changes.
func reload() -> void:
	var score: Dictionary = Sounds.data.music
	var changed := {}
	var new_bpm := clampf(float(score.get("bpm", 116.0)), 30.0, 240.0)
	if new_bpm != bpm:
		# Brass notes are held for whole beats.
		changed["brass"] = true
	bpm = new_bpm
	var beat_ms := 60000.0 / bpm
	_delay.tap1_delay_ms = 0.75 * beat_ms
	_delay.tap2_delay_ms = 1.5 * beat_ms
	_delay.feedback_delay_ms = 1.5 * beat_ms
	for set_name: String in ["day", "night"]:
		_chords[set_name] = parse_chords(str(score.get(set_name + "_chords", "Dm")))
	_theme_at.clear()
	for note: Array in parse_theme(str(score.get("theme", ""))):
		_theme_at[int(note[0]) * 4] = note
	_arp_order.clear()
	for c in str(score.get("arp_order", "0")):
		if c.is_valid_int():
			_arp_order.push_back(clampi(int(c), 0, 5))
	if _arp_order.is_empty():
		_arp_order.push_back(0)
	_levels = score.get("levels", {})
	_patterns = score.get("patterns", {})
	var instruments: Dictionary = score.get("instruments", {})
	for key: String in KINDS:
		if instruments.get(key, {}) != _rendered.get(key, {}):
			changed[key] = true
	_rendered = instruments.duplicate(true)
	_request_all(changed)


## Chords as names, "Dm Bb F C": roots from G under D up to F♯, and minor
## with an m.
static func parse_chords(text: String) -> Array:
	var chords := []
	for word in text.split(" ", false):
		var root := _pitch_class(word)
		if root < 0:
			continue
		var offset := posmod(root - 2, 12)
		chords.push_back([offset - 12 if offset > 4 else offset, 3 if word.ends_with("m") else 4])
	return chords if !chords.is_empty() else [[0, 3]]


## The theme as notes and their lengths in beats, "D4:3 F4:1 -:2", a dash
## resting: [[beat it starts on, note, beats]].
static func parse_theme(text: String) -> Array:
	var notes := []
	var beat := 0
	for word in text.split(" ", false):
		var parts := word.split(":")
		var beats := maxi(int(parts[1]), 1) if parts.size() > 1 and parts[1].is_valid_int() else 1
		var pitch := _pitch_class(parts[0])
		var octave := parts[0].right(1)
		if pitch >= 0 and octave.is_valid_int():
			notes.push_back([beat, 12 * (int(octave) + 1) + pitch, beats])
		beat += beats
	return notes


## The pitch class a name starts with ("C#", "Bb", "E♭"), or -1.
static func _pitch_class(word: String) -> int:
	if word.is_empty() or !NOTE_NAMES.has(word[0].to_upper()):
		return -1
	var pitch: int = NOTE_NAMES[word[0].to_upper()]
	if word.length() > 1:
		if word[1] == "#" or word[1] == "♯":
			pitch += 1
		elif word[1] == "b" or word[1] == "♭":
			pitch -= 1
	return posmod(pitch, 12)


## How hard a pattern plays sixteenth `s`: "X" or "+" fully, 1-9 in tenths,
## anything else not at all.
static func hit(pattern: String, s: int) -> float:
	if pattern.is_empty():
		return 0.0
	var c := pattern[s % pattern.length()]
	if c == "X" or c == "+":
		return 1.0
	if c >= "1" and c <= "9":
		return (c.unicode_at(0) - 48) / 10.0
	return 0.0


## Where the music's up to, in beats.
func beats() -> float:
	return _beat


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
	if hold_mood >= 0:
		return clampi(hold_mood, 0, 3) as Mood
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
	var per_frame := bpm / 60.0 / RATE
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
	_voices = _voices.filter(func(v: Voice) -> bool: return !v.done and (v.gain > 0.0 or v.slope > 0.0 or v == _pad))
	_dry.push_buffer(dry)
	_wet.push_buffer(wet)
	_beat += n * per_frame


func _level(part: String) -> float:
	return float(_levels.get(part, 0.0))


## Starts whatever plays on sixteenth `step`, `at` frames into this block.
func _trigger(step: int, at: int) -> void:
	var bar := step / 16
	var s := step % 16
	var phrase := bar / 8
	var in_phrase := bar % 8
	if s == 0:
		_start_bar(bar, at)
	var chords: Array = _chords.night if mood >= Mood.NIGHT else _chords.day
	var chord: Array = chords[(in_phrase / 2) % chords.size()]
	var root: int = chord[0]
	var third: int = chord[1]
	var odd := phrase % 2 == 1
	var patterns: Dictionary = _patterns.get(MOODS[mood], {})

	# Bass: soft by day; by night a pulsing ostinato, pumping, that opens up
	# when the swarm comes.
	var strength := hit(patterns.get("bass", ""), s)
	if strength > 0.0:
		var octave := 12 if hit(patterns.get("octave", ""), s) > 0.0 else 0
		_play(_bass(38 + root + octave, mood >= Mood.SWARM), at, _level("bass") * strength, false, 0.0 if mood == Mood.DAY else 0.6)

	# Arpeggio: up and back down the chord over two octaves; by day only
	# every other phrase.
	var tones := [62 + root, 62 + root + third, 62 + root + 7, 74 + root, 74 + root + third, 74 + root + 7]
	var lift := 12 if mood == Mood.SIEGE else 0
	strength = hit(patterns.get("arp", ""), s)
	if strength > 0.0 and (mood != Mood.DAY or odd):
		var voice := _play("arp/%d" % (tones[_arp_order[s % _arp_order.size()]] + lift), at, _level("arp") * strength, true)
		if voice:
			voice.set_pan(-0.35 if s % 2 == 0 else 0.35)

	# Brass: the theme, doubled an octave down when the swarm's here; or a
	# low swell on the chord changes.
	var theme := mood >= Mood.SWARM or (mood == Mood.NIGHT and odd)
	var note: Variant = _theme_at.get(in_phrase * 16 + s)
	if theme and note != null:
		_play(_brass(note[1], note[2]), at, _level("brass"), true)
		if mood >= Mood.SWARM:
			_play(_brass(note[1] - 12, note[2]), at, _level("low_brass"), true)
	if s == 0 and in_phrase % 2 == 0 and ((mood == Mood.NIGHT and !odd) or (mood >= Mood.SWARM and in_phrase == 0)):
		_play("braam/%d" % root, at, _level("braam"), true)

	# Guitar: palm-muted, the power chord ringing out.
	strength = hit(patterns.get("guitar", ""), s)
	if strength > 0.0:
		_play("guitar/mute/%d" % root, at, _level("guitar") * strength)
	strength = hit(patterns.get("guitar_open", ""), s)
	if strength > 0.0:
		_play("guitar/open/%d" % root, at, _level("guitar") * strength)

	# Drums: hats by day only every other phrase; toms by night; a snare
	# roll into each phrase once the swarm's here.
	strength = hit(patterns.get("hat", ""), s)
	if strength > 0.0 and (mood != Mood.DAY or odd):
		_play("hat/closed", at, _level("hat") * strength)
	strength = hit(patterns.get("open_hat", ""), s)
	if strength > 0.0:
		_play("hat/open", at, _level("hat") * strength)
	strength = hit(patterns.get("kick", ""), s)
	if strength > 0.0:
		_play("kick", at, _level("kick") * strength)
	strength = hit(patterns.get("snare", ""), s)
	if strength > 0.0:
		_play("snare", at, _level("snare") * strength, true)
	if mood >= Mood.SWARM and in_phrase == 7 and s >= 8:
		_play("snare", at, _level("snare") * (0.3 + 0.05 * (s - 8)), true)
	if mood == Mood.NIGHT:
		if s == 0 and in_phrase % 2 == 0:
			_play("tom", at, _level("tom"), true)
		if s == 10 and in_phrase % 4 == 3:
			_play("tom", at, _level("tom") * 0.7, true)


## A new bar: the mood moves, the pad changes chord, and the cymbals mark
## the way in.
func _start_bar(bar: int, at: int) -> void:
	var wanted := _wanted()
	var was := mood
	if wanted > mood or hold_mood >= 0:
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
	var night_chords: Array = _chords.night
	if mood > was or (mood == Mood.SIEGE and in_phrase == 0):
		_play("crash", at, _level("crash"), true)
	if mood >= Mood.SWARM and was < Mood.SWARM:
		_play("guitar/open/%d" % night_chords[(in_phrase / 2) % night_chords.size()][0], at, _level("guitar") * 1.3)
	if mood >= Mood.SWARM and in_phrase == 7 and (bar / 8) % 2 == 1:
		_play("riser", at, _level("riser"), true)
	var chords: Array = _chords.night if mood >= Mood.NIGHT else _chords.day
	var pad_name := _pad_sound(chords[(in_phrase / 2) % chords.size()])
	var level: float = 0.0 if muted.has("pad") else _level("pad") * [1.0, 0.85, 0.65, 0.6][mood]
	if pad_name != _pad_name and _sounds.has(pad_name):
		if _pad:
			_pad.fade_to(0.0, PAD_FADE)
		_pad = _play(pad_name, at, 0.0, true, 0.5)
		if !_pad:
			return
		_pad.loop = true
		_pad.hi = level
		_pad.fade_to(level, PAD_FADE)
		_pad_name = pad_name
	elif _pad:
		if _pad_name == pad_name and _sounds.get(pad_name) != _pad.sound:
			# Made again since it started: swap it in where it's up to.
			_pad.sound = _sounds[pad_name]
			_pad.pos %= maxi(_pad.sound.size(), 1)
		_pad.fade_to(level, PAD_FADE)


func _pad_notes(chord: Array) -> Array:
	var root: int = chord[0]
	return [50 + root, 50 + root + chord[1], 50 + root + 7, 62 + root]


func _pad_sound(chord: Array) -> String:
	return "pad/%s" % "_".join(PackedStringArray(_pad_notes(chord).map(str)))


func _bass(note: int, bright: bool) -> String:
	return "bass/%d/%s" % [note, "bright" if bright else "dark"]


func _brass(note: int, beats: int) -> String:
	return "brass/%d/%d" % [note, beats]


## Asks for every sound the score can play that it hasn't got, and again
## for those of the instruments in `changed`.
func _request_all(changed: Dictionary) -> void:
	var synth := _renderer.synth
	var settings := func(key: String) -> Dictionary: return _rendered.get(key, {}).duplicate(true)
	var pad: Dictionary = settings.call("pad")
	var bass: Dictionary = settings.call("bass")
	var arp: Dictionary = settings.call("arp")
	var brass: Dictionary = settings.call("brass")
	var mute: Dictionary = settings.call("guitar_mute")
	var open: Dictionary = settings.call("guitar_open")
	var chords := {}
	for chord: Array in _chords.day + _chords.night:
		chords[str(chord)] = chord
	for chord: Array in chords.values():
		var root: int = chord[0]
		var third: int = chord[1]
		var pad_notes := _pad_notes(chord)
		_request(_pad_sound(chord), changed.has("pad"), func() -> Variant: return synth.pad(pad_notes, pad))
		for octave: int in [0, 12]:
			for bright: bool in [false, true]:
				var note := 38 + root + octave
				_request(_bass(note, bright), changed.has("bass"), func() -> Variant: return synth.bass(note, bright, bass))
		for base: int in [62, 74, 86]:
			for interval: int in [0, third, 7]:
				var note := base + root + interval
				_request("arp/%d" % note, changed.has("arp"), func() -> Variant: return synth.lead(note, arp))
		var power := [50 + root, 57 + root, 62 + root]
		_request("guitar/mute/%d" % root, changed.has("guitar_mute"), func() -> Variant: return synth.comp(power, mute))
		_request("guitar/open/%d" % root, changed.has("guitar_open"), func() -> Variant: return synth.comp(power, open))
		_request("braam/%d" % root, changed.has("brass"), func() -> Variant: return _render_braam(synth, root, brass))
	var seconds_per_beat := 60.0 / bpm
	for note: Array in _theme_at.values():
		for octave: int in [0, -12]:
			var pitch: int = note[1] + octave
			var beats: int = note[2]
			_request(_brass(pitch, beats), changed.has("brass"), func() -> Variant: return _render_brass(synth, pitch, beats * seconds_per_beat, brass))
	var kick: Dictionary = settings.call("kick")
	var snare: Dictionary = settings.call("snare")
	var tom: Dictionary = settings.call("tom")
	var hat: Dictionary = settings.call("hat")
	_request("kick", changed.has("kick"), func() -> Variant: return synth.kick(kick))
	_request("snare", changed.has("snare"), func() -> Variant: return synth.snare(snare))
	_request("tom", changed.has("tom"), func() -> Variant: return synth.snare(tom))
	_request("hat/closed", changed.has("hat"), func() -> Variant: return synth.hat(0.03, hat))
	_request("hat/open", changed.has("hat"), func() -> Variant: return synth.hat(0.16, hat))
	_request("crash", false, func() -> Variant: return synth.crash())
	_request("riser", false, func() -> Variant: return synth.riser())


## The settings for the model `p` makes its sound with, to change.
static func _own(p: Dictionary, instrument: String) -> Dictionary:
	var at := Instruments.model(p, instrument)
	var own: Dictionary = p.get(at, {}) if p.get(at) is Dictionary else {}
	p[at] = own
	return own


## A brass note held for `seconds`, swelling in.
static func _render_brass(synth: Instruments, note: int, seconds: float, brass: Dictionary) -> PackedVector2Array:
	var p := brass.duplicate(true)
	var own := _own(p, "lead")
	own.length = seconds + 0.15
	own.decay = seconds * 2.5
	return synth.lead(note, p)


## A huge low brass blast: root and fifth, two octaves down, swelling and
## dying over a couple of seconds.
static func _render_braam(synth: Instruments, root: int, brass: Dictionary) -> PackedVector2Array:
	var p := brass.duplicate(true)
	var own := _own(p, "lead")
	own.length = 2.6
	own.decay = 1.2
	own.attack = 0.12
	own.sustain = 4.0
	own.drive = 2.2
	var low := synth.lead(26 + root, p)
	var fifth := synth.lead(33 + root, p)
	var octave := synth.lead(38 + root, p)
	for i in low.size():
		low[i] = (low[i] + fifth[i] * 0.7 + octave[i] * 0.5) * 0.6
	return low


## Asks for a sound if it's not had or on its way, or if `again`.
func _request(sound_name: String, again: bool, render: Callable) -> void:
	if again or (!_sounds.has(sound_name) and !_requested.has(sound_name)):
		_requested[sound_name] = true
		_renderer.request(sound_name, render)


func _play(sound: String, at: int, gain: float, wet := false, duck := 0.0) -> Voice:
	if !_sounds.has(sound) or (_solo != "" and !sound.begins_with(_solo)):
		return null
	var voice := Voice.new()
	voice.sound = _sounds[sound]
	voice.start = at
	if muted.has(sound.get_slice("/", 0)):
		gain = 0.0
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
	# Generated, so it can't be a web build's sample.
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
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
## for, handing them back as they're done. Where there are no threads (the
## web build), it renders on the main thread instead, a few milliseconds a
## frame, so the game doesn't stop while a sound is made.
class Renderer:
	## Milliseconds a frame to spend rendering without a thread.
	const FRAME_BUDGET_MSEC := 4
	const PAD_STRETCH := 2048
	var synth: Instruments
	var _threaded := !OS.has_feature("nothreads")
	var _mutex := Mutex.new()
	## [[name, Callable]] waiting. A Callable gives the sound, or a Pad to
	## render it.
	var _queue: Array = []
	var _done: Dictionary[String, PackedVector2Array] = {}
	var _task := -1
	## Without a thread: the pad being rendered, and its name.
	var _pad: Instruments.Pad
	var _pad_name := ""

	func _init(rate: float) -> void:
		synth = Instruments.new(rate)

	func request(sound_name: String, render: Callable) -> void:
		_mutex.lock()
		_queue.push_back([sound_name, render])
		_mutex.unlock()

	## Returns what's finished since last time, and keeps the work going.
	func poll() -> Dictionary[String, PackedVector2Array]:
		if !_threaded:
			_work_for(FRAME_BUDGET_MSEC)
		elif _task >= 0 and WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
		_mutex.lock()
		var done := _done
		_done = {}
		var waiting := !_queue.is_empty()
		_mutex.unlock()
		if _threaded and _task < 0 and waiting:
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

	## Without a thread: renders for about `msec`, a sound or a stretch of
	## a pad at a time.
	func _work_for(msec: int) -> void:
		var until := Time.get_ticks_msec() + msec
		while Time.get_ticks_msec() < until:
			if _pad:
				if _pad.render(PAD_STRETCH):
					_done[_pad_name] = _pad.out
					_pad = null
				continue
			if _queue.is_empty():
				return
			var job: Array = _queue.pop_front()
			var sound: Variant = job[1].call()
			if sound is Instruments.Pad:
				_pad = sound
				_pad_name = job[0]
			else:
				_done[job[0]] = sound
