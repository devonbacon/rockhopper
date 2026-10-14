class_name ParamSlider
extends HBoxContainer
## One number in the sound editor: a slider to play with, a box for exact
## values, a tag saying whether it's set or the default, and a button to
## drop it back to the default. Wide ranges of positive numbers, like
## frequencies, slide logarithmically. From Real-Time Logistics.

signal changed(value: float)
signal reset

const SOURCE_COLORS := {
	"default": Color(0.5, 0.55, 0.6),
	"set": Color(0.6, 1.0, 0.6),
}

var _slider := HSlider.new()
var _box := SpinBox.new()
var _tag := Label.new()
var _reset := Button.new()


func _init(label_text: String, lowest: float, highest: float) -> void:
	add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 118
	label.clip_text = true
	add_child(label)

	var step := pow(10.0, floorf(log(highest - lowest) / log(10.0)) - 3.0)
	for range_control: Range in [_slider, _box]:
		range_control.min_value = lowest
		range_control.max_value = highest
		range_control.step = step
	# Values typed past the ends are fine; the slider just can't reach them.
	_box.allow_greater = true
	_box.allow_lesser = true
	_slider.exp_edit = lowest > 0.0 and highest / lowest >= 50.0
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.custom_minimum_size.x = 120
	add_child(_slider)
	_box.custom_minimum_size.x = 92
	_box.select_all_on_focus = true
	add_child(_box)
	_slider.value_changed.connect(func(value: float) -> void:
		_box.set_value_no_signal(value)
		changed.emit(value))
	_box.value_changed.connect(func(value: float) -> void:
		_slider.set_value_no_signal(value)
		changed.emit(value))

	_tag.custom_minimum_size.x = 54
	_tag.add_theme_font_size_override("font_size", 11)
	add_child(_tag)
	_reset.text = "↺"
	_reset.tooltip_text = "Back to the default"
	_reset.focus_mode = Control.FOCUS_NONE
	_reset.pressed.connect(func() -> void: reset.emit())
	add_child(_reset)


func set_value(value: float) -> void:
	_slider.set_value_no_signal(value)
	_box.set_value_no_signal(value)


## Whether the value's "set" or the "default"; and whether it can be
## dropped back to the default.
func set_source(source: String, resettable: bool) -> void:
	_tag.text = source
	_tag.modulate = SOURCE_COLORS.get(source, Color.WHITE)
	_reset.modulate.a = 1.0 if resettable else 0.0
	_reset.disabled = !resettable
