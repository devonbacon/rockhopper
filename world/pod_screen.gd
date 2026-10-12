class_name PodScreen
extends Node3D
## The screen on the pod's side, Doom style: you use it where it is, by
## looking at a button on it and pressing E. It shows what's banked, the
## rovers, the battery and the launch clock, and has buttons to print a
## rover and to hand in what you carry. It answers on its own status line.
##
## It's a SubViewport of plain Controls, shown on a quad through a
## scanline shader.

## The quad's size in metres, and the viewport's in pixels, both 16:10.
const SIZE := Vector2(1.3, 0.8125)
const PIXELS := Vector2i(640, 400)
const BUTTONS := {&"rover": Rect2(24, 248, 592, 58), &"hand_in": Rect2(24, 318, 592, 58)}
const INK := Color(0.55, 0.95, 1.0)
const DIM := Color(0.35, 0.6, 0.68)
const ORANGE := Color(1.0, 0.5, 0.12)
const ALERT := Color(1.0, 0.4, 0.3)

var game: Game
## The button under the crosshair, or none.
var hover: StringName = &""

var _viewport: SubViewport
var _lines: Label
var _status: Label
var _status_time := 0.0
var _buttons := {}
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
	var title := _label("PROSPECTOR POD  //  FAB-2", 24, Color(0.05, 0.03, 0.02))
	title.position = Vector2(20, 6)
	_viewport.add_child(title)
	_lines = _label("", 26, INK)
	_lines.position = Vector2(24, 56)
	_viewport.add_child(_lines)
	_status = _label("", 22, ORANGE)
	_status.position = Vector2(24, 206)
	_viewport.add_child(_status)
	for action: StringName in BUTTONS:
		var rect: Rect2 = BUTTONS[action]
		var panel := Panel.new()
		panel.position = rect.position
		panel.size = rect.size
		var style := StyleBoxFlat.new()
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", style)
		_viewport.add_child(panel)
		var text := _label("", 26, INK)
		text.position = rect.position + Vector2(18, 12)
		_viewport.add_child(text)
		_buttons[action] = style
		_labels[action] = text
	var material := ShaderMaterial.new()
	material.shader = load("res://world/screen.gdshader")
	material.set_shader_parameter("screen", _viewport.get_texture())
	var quad := QuadMesh.new()
	quad.size = SIZE
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


## Whether a ray from `from` along `dir` lands on the screen; if it does,
## hover is the button it's on, if any.
func aim(from: Vector3, dir: Vector3) -> bool:
	hover = &""
	var normal := global_basis.z.normalized()
	var facing := dir.dot(normal)
	if facing >= 0.0:
		return false
	var t := (global_position - from).dot(normal) / facing
	var local := global_transform.affine_inverse() * (from + dir * t)
	var uv := Vector2(local.x / SIZE.x + 0.5, 0.5 - local.y / SIZE.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return false
	var pixel := uv * Vector2(PIXELS)
	for action: StringName in BUTTONS:
		if BUTTONS[action].has_point(pixel):
			hover = action
	return true


## Presses the button under the crosshair.
func press() -> void:
	match hover:
		&"rover":
			if game.print_rover():
				_say("ROVER PRINTED. %d ON THE ROSTER." % game.rovers.size())
			else:
				_say("NOT ENOUGH ORE BANKED: A ROVER NEEDS %d." % Fixture.COST[&"rover"])
		&"hand_in":
			if game.carried > 0:
				_say("%d ORE BANKED." % game.carried)
				game.hand_in()
			else:
				_say("NOTHING TO HAND IN.")


func _process(delta: float) -> void:
	if !game:
		return
	_status_time = maxf(0.0, _status_time - delta)
	_status.visible = _status_time > 0.0
	var out := 0
	for rover in game.rovers:
		if rover.task != Rover.Task.PARKED:
			out += 1
	var left := maxf(0.0, Game.MISSION - game.time)
	_lines.text = "ORE BANKED    %d / %d\nROVERS        %d  (%d HAULING)\nBATTERY       %d%%\nLAUNCH IN     %d:%02d" % [
		game.stock, Game.QUOTA, game.rovers.size(), out, roundi(game.battery / Game.BATTERY * 100.0), int(left) / 60, int(left) % 60]
	var can_print: bool = game.stock >= Fixture.COST[&"rover"]
	_style(&"rover", "PRINT ROVER   %d ORE" % Fixture.COST[&"rover"], can_print)
	_style(&"hand_in", "HAND IN ORE   %d CARRIED" % game.carried, game.carried > 0)


func _style(action: StringName, text: String, enabled: bool) -> void:
	var style: StyleBoxFlat = _buttons[action]
	var lit := hover == action
	var color := INK if enabled else DIM
	style.bg_color = Color(color, 0.25 if lit else 0.06)
	style.border_color = color if lit else Color(color, 0.5)
	_labels[action].text = ("> " if lit else "  ") + text
	_labels[action].modulate = color


func _say(text: String) -> void:
	_status.text = text
	_status_time = 2.5


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.modulate = color
	return label
