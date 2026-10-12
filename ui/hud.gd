class_name Hud
extends CanvasLayer
## Readouts: battery, suit warmth and jetpack, ore, the clocks, what E does,
## and where the pod is.

var game: Game

var _status: Label
var _clock: Label
var _prompt: Label
var _tool: Label
var _pod_marker: Label
var _outcome: Label
var _frost: ColorRect
var _frost_material: ShaderMaterial


func _ready() -> void:
	_frost_material = ShaderMaterial.new()
	_frost_material.shader = load("res://ui/frost.gdshader")
	_frost = ColorRect.new()
	_frost.material = _frost_material
	_frost.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frost)
	_status = _label(Vector2(24, 20), 20)
	_clock = _label(Vector2.ZERO, 20)
	_clock.anchor_left = 1.0
	_clock.anchor_right = 1.0
	_clock.offset_left = -24.0
	_clock.offset_right = -24.0
	_clock.offset_top = 20.0
	_clock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt = _centred(60, 22)
	_tool = _centred(-70, 18, true)
	_outcome = _centred(-160, 34)
	var crosshair := _centred(0, 20)
	crosshair.text = "+"
	_pod_marker = _label(Vector2.ZERO, 16)
	_pod_marker.modulate = Color(1.0, 0.6, 0.3)


func _label(pos: Vector2, size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


## A label across the screen's full width, its text centred, offset
## from the middle (or from the bottom) by offset.
func _centred(offset: float, size: int, from_bottom: bool = false) -> Label:
	var label := _label(Vector2.ZERO, size)
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 1.0 if from_bottom else 0.5
	label.anchor_bottom = label.anchor_top
	label.offset_left = 0.0
	label.offset_right = 0.0
	label.offset_top = offset
	label.offset_bottom = offset
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _process(_delta: float) -> void:
	var player := game.player
	var net := game.power_in - game.power_out
	_status.text = "BATTERY  %s %3d  %+.1f/s\nWARMTH   %s %3d  %s\nJETPACK  %s\n\nORE  %d carried   %d / %d handed in" % [
		_bar(game.battery / Game.BATTERY), game.battery, net,
		_bar(game.warmth / 100.0), game.warmth, ("in %s light" % game.lit_by) if game.lit_by != "" else "IN THE DARK",
		_bar(player.fuel / 100.0),
		game.carried, game.delivered, Game.QUOTA]
	var left := maxf(0.0, Game.MISSION - game.time)
	var crossing := game.sun.next_crossing(player.global_position.normalized())
	var sky := "Sun never sets here" if crossing[0] == INF and !crossing[1] else ("Sun never rises here" if crossing[0] == INF else ("%s in %s" % ["Sunrise" if crossing[1] else "Sunset", _clock_text(crossing[0])]))
	_clock.text = "POD LAUNCHES IN %s\n%s" % [_clock_text(left), sky]
	_clock.modulate = Color(1.0, 0.4, 0.3) if left < 60.0 else Color.WHITE
	_prompt.text = player.prompt + ("  " + _bar(player.progress, 10) if player.progress > 0.0 else "")
	var tool := "[1] lamp (%d ore)   [2] panel (%d ore)" % [Fixture.COST[&"lamp"], Fixture.COST[&"panel"]]
	if player.tool != &"":
		tool = "Building %s - left-click to place, right-click to stop" % player.tool
	_tool.text = tool + "\n[F] headlamp   [Hold E] use"
	_frost_material.set_shader_parameter("amount", clampf(1.0 - game.warmth / 70.0, 0.0, 1.0))
	_place_pod_marker()
	_outcome.visible = game.state != Game.State.PLAYING
	if _outcome.visible:
		_outcome.text = "%s\n\n[R] new asteroid   [Shift+R] same one" % game.outcome


func _place_pod_marker() -> void:
	var camera := game.player.camera
	var top := game.pod.global_position + game.pod.normal * 4.5
	_pod_marker.visible = !camera.is_position_behind(top)
	if _pod_marker.visible:
		_pod_marker.text = "POD %dm" % camera.global_position.distance_to(game.pod.global_position)
		_pod_marker.position = camera.unproject_position(top) - _pod_marker.size * Vector2(0.5, 1.0)


func _bar(fraction: float, width: int = 16) -> String:
	var filled := clampi(roundi(fraction * width), 0, width)
	return "[" + "|".repeat(filled) + ".".repeat(width - filled) + "]"


func _clock_text(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
