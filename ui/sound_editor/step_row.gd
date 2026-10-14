class_name StepRow
extends Control
## A bar of sixteenths to click in, for one of the score's patterns (see
## Music.hit): left-click turns a step on or off, dragging along paints,
## and right-click (or dragging with it) sets a step's strength by how high
## up it's clicked. The sixteenth being heard lights up.
##
## With `octave`, steps are only on or off, written "+". From Real-Time
## Logistics.

signal changed(pattern: String)

const STEPS := 16
const GAP := 3.0

var octave := false
var color := Color(1.0, 0.6, 0.2)
## Each step's strength, 0 to 1, in tenths.
var _levels := PackedFloat32Array()
## While dragging: what the left button is painting (on or off), or -1;
## and whether the right button is setting strengths.
var _painting := -1
var _shaping := false


func _init() -> void:
	custom_minimum_size = Vector2(16 * 22, 30)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_levels.resize(STEPS)


func set_pattern(pattern: String) -> void:
	for i in STEPS:
		_levels[i] = Music.hit(pattern, i)
	queue_redraw()


func pattern() -> String:
	var out := ""
	for level in _levels:
		if level <= 0.0:
			out += "."
		elif octave:
			out += "+"
		elif level >= 0.95:
			out += "X"
		else:
			out += str(clampi(roundi(level * 10.0), 1, 9))
	return out


func _process(_delta: float) -> void:
	# For the playhead.
	if is_visible_in_tree():
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var step := _step_at(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and step >= 0:
				_painting = 0 if _levels[step] > 0.0 else 1
				_paint(step)
			elif !event.pressed:
				_painting = -1
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and !octave:
			_shaping = event.pressed
			if event.pressed and step >= 0:
				_shape(step, event.position.y)
			accept_event()
		elif event.pressed and !octave and step >= 0 and _levels[step] > 0.0 and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var nudge := 0.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1
			_set_level(step, clampf(snappedf(_levels[step] + nudge, 0.1), 0.1, 1.0))
			accept_event()
	elif event is InputEventMouseMotion:
		var step := _step_at(event.position)
		if step < 0:
			return
		if _painting >= 0:
			_paint(step)
		elif _shaping:
			_shape(step, event.position.y)


func _paint(step: int) -> void:
	_set_level(step, float(_painting))


func _shape(step: int, y: float) -> void:
	_set_level(step, clampf(snappedf(1.0 - y / size.y, 0.1), 0.1, 1.0))


func _set_level(step: int, level: float) -> void:
	if is_equal_approx(_levels[step], level):
		return
	_levels[step] = level
	queue_redraw()
	changed.emit(pattern())


func _step_at(at: Vector2) -> int:
	if at.x < 0.0 or at.x >= size.x:
		return -1
	return clampi(int(at.x / size.x * STEPS), 0, STEPS - 1)


func _draw() -> void:
	var width := size.x / STEPS
	var playing := posmod(int(floor(Music.beats() * 4.0)), STEPS)
	for i in STEPS:
		var cell := Rect2(i * width + GAP / 2.0, 0.0, width - GAP, size.y)
		# Beats a little brighter than the steps between, so the bar reads.
		var base := 0.1 if i % 4 == 0 else 0.05
		draw_rect(cell, Color(color, base))
		if _levels[i] > 0.0:
			var height := size.y * (1.0 if octave else _levels[i])
			draw_rect(Rect2(cell.position.x, size.y - height, cell.size.x, height), Color(color, 0.35 + 0.5 * _levels[i]))
		if i == playing:
			draw_rect(cell, Color(1, 1, 1, 0.5), false, 1.0)
		if octave and _levels[i] > 0.0:
			draw_string(get_theme_default_font(), cell.position + Vector2(cell.size.x / 2.0 - 4.0, size.y / 2.0 + 5.0), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.BLACK)
