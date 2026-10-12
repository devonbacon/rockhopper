class_name Screen
extends Node3D
## Doom-style in-world screen: look at a button, press E. The owner sets
## size, title and buttons before adding it, then the callables.

const PIXELS := Vector2i(640, 400)
const INK := Color(0.55, 0.95, 1.0)
const DIM := Color(0.35, 0.6, 0.68)
const ORANGE := Color(1.0, 0.5, 0.12)
const BUTTON_HEIGHT := 52.0
const BUTTON_GAP := 8.0

var size_m := Vector2(1.3, 0.8125)
var title := ""
var buttons: Array[StringName] = []
var info := func() -> String: return ""
## action -> [text, enabled, current]
var button := func(_action: StringName) -> Array: return ["", true, false]
## action -> reply for the status line, or ""
var pressed := func(_action: StringName) -> String: return ""
var hover: StringName = &""

var _viewport: SubViewport
var _lines: Label
var _status: Label
var _status_time := 0.0
var _rects := {}
var _styles := {}
var _labels := {}


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = PIXELS
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var back := ColorRect.new()
	back.color = Color(0.02, 0.04, 0.07)
	back.size = PIXELS
	_viewport.add_child(back)
	var header := ColorRect.new()
	header.color = ORANGE
	header.size = Vector2(PIXELS.x, 44)
	_viewport.add_child(header)
	var heading := _label(title, 24, Color(0.05, 0.03, 0.02))
	heading.position = Vector2(20, 6)
	_viewport.add_child(heading)
	_lines = _label("", 26, INK)
	_lines.position = Vector2(24, 54)
	_viewport.add_child(_lines)
	var top := PIXELS.y - 16.0 - buttons.size() * BUTTON_HEIGHT - (buttons.size() - 1) * BUTTON_GAP
	_status = _label("", 22, ORANGE)
	_status.position = Vector2(24, top - 34.0)
	_viewport.add_child(_status)
	for i in buttons.size():
		var rect := Rect2(24, top + i * (BUTTON_HEIGHT + BUTTON_GAP), PIXELS.x - 48, BUTTON_HEIGHT)
		var panel := Panel.new()
		panel.position = rect.position
		panel.size = rect.size
		var style := StyleBoxFlat.new()
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", style)
		_viewport.add_child(panel)
		var text := _label("", 26, INK)
		text.position = rect.position + Vector2(18, 9)
		_viewport.add_child(text)
		_rects[buttons[i]] = rect
		_styles[buttons[i]] = style
		_labels[buttons[i]] = text
	var material := ShaderMaterial.new()
	material.shader = load("res://world/screen.gdshader")
	material.set_shader_parameter("screen", _viewport.get_texture())
	var quad := QuadMesh.new()
	quad.size = size_m
	var display := MeshInstance3D.new()
	display.mesh = quad
	display.material_override = material
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(display)
	var glow := OmniLight3D.new()
	glow.light_color = INK
	glow.omni_range = 2.5
	glow.light_energy = 0.35
	glow.position = Vector3(0, 0, 0.4)
	add_child(glow)


## Distance along the ray to the screen, or INF if it misses. Sets hover.
func aim(from: Vector3, dir: Vector3) -> float:
	hover = &""
	var normal := global_basis.z.normalized()
	var facing := dir.dot(normal)
	if facing >= 0.0:
		return INF
	var t := (global_position - from).dot(normal) / facing
	if t < 0.0:
		return INF
	var local := global_transform.affine_inverse() * (from + dir * t)
	var uv := Vector2(local.x / size_m.x + 0.5, 0.5 - local.y / size_m.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return INF
	var pixel := uv * Vector2(PIXELS)
	for action: StringName in _rects:
		if _rects[action].has_point(pixel):
			hover = action
	return t


func press() -> void:
	if hover == &"":
		return
	var reply: String = pressed.call(hover)
	if reply != "":
		_status.text = reply
		_status_time = 2.5


func _process(delta: float) -> void:
	_status_time = maxf(0.0, _status_time - delta)
	_status.visible = _status_time > 0.0
	_lines.text = info.call()
	for action: StringName in _styles:
		var state: Array = button.call(action)
		var style: StyleBoxFlat = _styles[action]
		var lit := hover == action
		var color := (ORANGE if state[2] else INK) if state[1] else DIM
		style.bg_color = Color(color, 0.3 if lit else (0.18 if state[2] else 0.06))
		style.border_color = color if lit or state[2] else Color(color, 0.5)
		_labels[action].text = ("> " if lit else "  ") + state[0]
		_labels[action].modulate = color


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.modulate = color
	return label
