class_name Hud
extends CanvasLayer
## Readouts. Top left, meters for health, the battery, suit warmth and
## the jetpack. Top right, the pod's launch clock and a strip of the next
## day and night where you're standing. Bottom, the ore banked in the pod
## and in your pockets, and the rovers. In the middle, a
## crosshair that fills as you hold E, what E would do, a marker for the
## pod pinned to the screen's edge when it's out of view, and markers on
## drill rigs and blueprints, with how far along they are.

const PANEL := Color(0.04, 0.05, 0.07, 0.75)
const EDGE := Color(1, 1, 1, 0.12)
const DIM := Color(1, 1, 1, 0.55)
const BATTERY_COLOR := Color(1.0, 0.8, 0.3)
const WARM_COLOR := Color(1.0, 0.55, 0.25)
const COLD_COLOR := Color(0.55, 0.8, 1.0)
const FUEL_COLOR := Color(0.45, 0.9, 1.0)
const ORE_COLOR := Color(0.35, 0.88, 0.95)
const DAY_COLOR := Color(1.0, 0.82, 0.45)
const NIGHT_COLOR := Color(0.1, 0.13, 0.24)
const POD_COLOR := Color(1.0, 0.55, 0.25)
const ALERT := Color(1.0, 0.4, 0.3)
const HEALTH_COLOR := Color(1.0, 0.35, 0.35)
const FORECAST_STEPS := 120
const BLUEPRINT_COLOR := Color(0.45, 0.8, 1.0)

var game: Game

var _meters := {}
var _launch: Label
var _sky: Label
var _strip: Control
var _ore: Label
var _carried: Label
var _rovers: Label
var _notice: Label
var _hint: Label
var _prompt: Label
var _overlay: Control
var _outcome: PanelContainer
var _outcome_text: Label
var _frost_material: ShaderMaterial
var _hurt_material: ShaderMaterial
var _pause: Control
## Where you stand, whether the sun reaches you at even steps over the next
## turn, refreshed every so often.
var _forecast: Array[bool] = []
var _forecast_age := 99.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_frost_material = ShaderMaterial.new()
	_frost_material.shader = load("res://ui/frost.gdshader")
	var frost := ColorRect.new()
	frost.material = _frost_material
	_fill(frost)
	add_child(frost)
	_hurt_material = ShaderMaterial.new()
	_hurt_material.shader = _frost_material.shader
	_hurt_material.set_shader_parameter("tint", Color(0.9, 0.05, 0.02))
	var hurt := ColorRect.new()
	hurt.material = _hurt_material
	_fill(hurt)
	add_child(hurt)
	_overlay = Control.new()
	_fill(_overlay)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_build_meters()
	_build_clock()
	_build_bottom()
	_prompt = _label(20)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_prompt, Vector2(0.5, 0.5), Vector2(0, 46), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	add_child(_prompt)
	_notice = _label(18, DAY_COLOR)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_notice, Vector2(0.5, 0.5), Vector2(0, 90), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	add_child(_notice)
	_outcome_text = _label(30)
	_outcome_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outcome = _panel(_outcome_text, 28)
	_place(_outcome, Vector2(0.5, 0.4), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	add_child(_outcome)
	_build_pause()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and !event.echo and event.physical_keycode == KEY_ESCAPE:
		set_paused(!get_tree().paused)
		get_viewport().set_input_as_handled()


func set_paused(paused: bool) -> void:
	get_tree().paused = paused and !Net.networked()
	_pause.visible = paused
	var commanding := game.commander_view != null and game.commander_view.visible
	if commanding:
		visible = paused
	var playing := game.state == Game.State.PLAYING
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if !paused and playing and !commanding else Input.MOUSE_MODE_VISIBLE


func _build_pause() -> void:
	_pause = ColorRect.new()
	_pause.color = Color(0, 0, 0, 0.55)
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	add_child(_pause)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	var title := _label(34)
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	for entry: Array in [["Resume", func() -> void: set_paused(false)],
			["Leave" if Net.networked() else "New map", func() -> void:
				get_tree().paused = false
				if Net.networked():
					Net.leave()
					get_tree().change_scene_to_file("res://menu/menu.tscn")
				else:
					get_tree().reload_current_scene()],
			["Quit", func() -> void: get_tree().quit()]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(260, 48)
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(entry[1])
		column.add_child(button)
	var panel := _panel(column, 24)
	_place(panel, Vector2(0.5, 0.45), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_pause.add_child(panel)


func _process(delta: float) -> void:
	_forecast_age += delta
	if _forecast_age > 0.4:
		_forecast_age = 0.0
		_forecast = game.sun.forecast(game.player.camera.global_position, game.get_world_3d().direct_space_state, FORECAST_STEPS)
	_update_meters()
	_update_clock()
	_update_bottom()
	var player := game.player
	_prompt.text = player.prompt
	_prompt.visible = player.prompt != ""
	_frost_material.set_shader_parameter("amount", clampf(1.0 - game.warmth / 70.0, 0.0, 1.0))
	_hurt_material.set_shader_parameter("amount", maxf(game.hurt * 0.7, clampf(1.0 - game.health / 40.0, 0.0, 1.0) * 0.5))
	_notice.text = player.notice
	_notice.modulate.a = clampf(player.notice_time, 0.0, 1.0)
	_outcome.visible = game.state != Game.State.PLAYING
	if _outcome.visible:
		_outcome_text.text = "%s\n\n[R] new asteroid    [Shift+R] same one" % game.outcome
	_overlay.queue_redraw()


func _build_meters() -> void:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	for meter: Array in [[&"health", "HEALTH", HEALTH_COLOR], [&"battery", "BATTERY", BATTERY_COLOR], [&"warmth", "WARMTH", WARM_COLOR], [&"fuel", "JETPACK", FUEL_COLOR]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var title := _label(15, DIM)
		title.text = meter[1]
		title.custom_minimum_size.x = 82
		row.add_child(title)
		var fill := StyleBoxFlat.new()
		fill.bg_color = meter[2]
		fill.set_corner_radius_all(3)
		var back := StyleBoxFlat.new()
		back.bg_color = Color(1, 1, 1, 0.08)
		back.set_corner_radius_all(3)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(240, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", back)
		row.add_child(bar)
		var value := _label(15)
		value.custom_minimum_size.x = 170
		row.add_child(value)
		rows.add_child(row)
		_meters[meter[0]] = {bar = bar, fill = fill, value = value, row = row}
	var panel := _panel(rows)
	_place(panel, Vector2.ZERO, Vector2(20, 20), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END)
	add_child(panel)


func announce(text: String) -> void:
	game.player.notice = text
	game.player.notice_time = 3.5


func _update_meters() -> void:
	_set_meter(&"health", game.health / game.max_health(), "%d" % game.health, ALERT if game.hurt > 0.0 else Color.WHITE)
	var net := game.power_in - game.power_out
	_set_meter(&"battery", game.battery / game.capacity(), "%d / %d   %+.1f/s" % [game.battery, game.capacity(), net], ALERT if net < 0.0 else Color.WHITE)
	var warmth := game.warmth / 100.0
	_meters[&"warmth"].fill.bg_color = COLD_COLOR.lerp(WARM_COLOR, warmth)
	var source := "in sunlight" if game.lit_by == "sun" else ("by a lamp" if game.lit_by == "lamp" else ("by the pod" if game.lit_by == "pod" else "IN THE DARK"))
	_set_meter(&"warmth", warmth, "%d   %s" % [game.warmth, source], COLD_COLOR if game.lit_by == "" else Color.WHITE)
	var player := game.player
	_meters[&"fuel"].row.visible = game.has(&"jetpack")
	_set_meter(&"fuel", player.fuel / 100.0, "burning" if player.jetting else "", Color.WHITE)


func _set_meter(meter: StringName, fraction: float, text: String, color: Color) -> void:
	var parts: Dictionary = _meters[meter]
	parts.bar.max_value = 1.0
	parts.bar.value = fraction
	parts.value.text = text
	parts.value.modulate = color


func _build_clock() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	var title := _label(13, DIM)
	title.text = "POD LAUNCHES IN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(title)
	_launch = _label(30)
	_launch.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_launch)
	_sky = _label(15)
	_sky.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_sky)
	_strip = Control.new()
	_strip.custom_minimum_size = Vector2(260, 12)
	_strip.draw.connect(_draw_strip)
	column.add_child(_strip)
	var caption := _label(12, DIM)
	caption.text = "now                                    one turn ahead"
	column.add_child(caption)
	var panel := _panel(column)
	_place(panel, Vector2(1, 0), Vector2(-20, 20), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	add_child(panel)


func _update_clock() -> void:
	var left := maxf(0.0, Game.MISSION - game.time)
	_launch.text = _clock_text(left)
	_launch.modulate = ALERT if left < 60.0 else Color.WHITE
	var lit_now := !_forecast.is_empty() and _forecast[0]
	var change := _forecast.find(!lit_now)
	if _forecast.is_empty():
		_sky.text = ""
	elif change < 0:
		_sky.text = "The sun won't leave you here" if lit_now else "The sun won't reach you here"
	else:
		_sky.text = "%s in %s" % ["Sunset" if lit_now else "Sunrise", _clock_text(Sun.DAY * change / float(FORECAST_STEPS))]
	_sky.modulate = COLD_COLOR if lit_now else DAY_COLOR
	_strip.queue_redraw()


## One turn of the sky where you stand, sun bright and shadow dark, with
## the pod's launch marked if it falls inside it.
func _draw_strip() -> void:
	var width := _strip.size.x
	var steps := _forecast.size()
	for i in steps:
		var x := width * i / float(steps)
		_strip.draw_rect(Rect2(x, 0, width / steps + 0.5, _strip.size.y), DAY_COLOR if _forecast[i] else NIGHT_COLOR)
	var launch := (Game.MISSION - game.time) / Sun.DAY
	if launch < 1.0:
		_strip.draw_rect(Rect2(width * launch - 1.5, -3, 3, _strip.size.y + 6), ALERT)
	_strip.draw_rect(Rect2(0, -3, 2, _strip.size.y + 6), Color.WHITE)


func _build_bottom() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var ore_column := VBoxContainer.new()
	ore_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_ore = _label(26, ORE_COLOR)
	ore_column.add_child(_ore)
	_carried = _label(14, DIM)
	ore_column.add_child(_carried)
	_rovers = _label(14, DIM)
	ore_column.add_child(_rovers)
	var ore_panel := _panel(ore_column)
	ore_panel.custom_minimum_size = Vector2(210, 104)
	row.add_child(ore_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	_hint = _label(14, DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)
	_place(column, Vector2(0.5, 1), Vector2(0, -20), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	add_child(column)


func _update_bottom() -> void:
	_ore.text = "%d / %d in pod" % [game.stock, Game.QUOTA]
	_ore.modulate = DAY_COLOR if game.stock >= Game.QUOTA else ORE_COLOR
	_carried.text = "carrying %d" % game.carried
	var out := 0
	for rover in game.rovers:
		if rover.task != Rover.Task.PARKED:
			out += 1
	_rovers.text = "%d rovers, %d out" % [game.rovers.size(), out]
	for lab in game.built:
		if lab.kind == &"lab" and lab.researching != &"":
			var upgrade: Dictionary = Game.UPGRADES[lab.researching]
			_rovers.text += "\n%s %d%%%s" % [String(upgrade.name).capitalize(), roundi(lab.research_time / upgrade.time * 100.0), " (no power)" if lab.unpowered else ""]
	var attack := "[LMB] fire    [RMB] aim" if game.player.weapon == &"gun" else "[LMB] smash / build"
	_hint.text = "%s    [1/2/wheel] gun/hammer    [G] grapple    [E] use    [F] headlamp    [Esc] pause" % attack


## A buildable's icon, about 50 px across, centred on centre.
static func draw_icon(canvas: CanvasItem, kind: StringName, centre: Vector2, tint: Color) -> void:
	var white := Color(0.88, 0.88, 0.86) * tint
	var gold := Color(0.85, 0.62, 0.22) * tint
	var dark := Color(0.15, 0.15, 0.17) * tint
	if kind == &"lab":
		canvas.draw_rect(Rect2(centre + Vector2(-24, -8), Vector2(48, 26)), white)
		canvas.draw_rect(Rect2(centre + Vector2(-25, -11), Vector2(50, 4)), gold)
		canvas.draw_rect(Rect2(centre + Vector2(-12, -2), Vector2(24, 14)), Color(0.3, 0.8, 0.9) * tint)
		canvas.draw_line(centre + Vector2(14, -11), centre + Vector2(14, -22), white, 2.0)
		canvas.draw_arc(centre + Vector2(14, -24), 6, PI * 0.1, PI * 0.9, 8, white, 2.0)
	elif kind == &"battery":
		canvas.draw_rect(Rect2(centre + Vector2(-22, -12), Vector2(44, 28)), white)
		canvas.draw_rect(Rect2(centre + Vector2(-22, -7), Vector2(44, 5)), gold)
		canvas.draw_rect(Rect2(centre + Vector2(-14, -18), Vector2(6, 6)), dark)
		canvas.draw_rect(Rect2(centre + Vector2(8, -18), Vector2(6, 6)), dark)
		canvas.draw_rect(Rect2(centre + Vector2(-14, 2), Vector2(28, 10)), Color(0.4, 1.0, 0.35) * tint)
	elif kind == &"drill":
		canvas.draw_line(centre + Vector2(-20, 20), centre + Vector2(0, -16), white, 3.0)
		canvas.draw_line(centre + Vector2(20, 20), centre + Vector2(0, -16), white, 3.0)
		canvas.draw_line(centre + Vector2(0, -12), centre + Vector2(0, 22), Color(0.5, 0.5, 0.52) * tint, 3.0)
		canvas.draw_rect(Rect2(centre + Vector2(-9, -24), Vector2(18, 11)), gold)
	elif kind == &"lamp":
		canvas.draw_circle(centre + Vector2(0, -12), 13, Color(1.0, 0.75, 0.4, 0.18) * tint)
		canvas.draw_line(centre + Vector2(0, -8), centre + Vector2(0, 18), Color(0.7, 0.7, 0.72) * tint, 3.0)
		canvas.draw_rect(Rect2(centre + Vector2(-9, 16), Vector2(18, 4)), Color(0.7, 0.7, 0.72) * tint)
		canvas.draw_circle(centre + Vector2(0, -12), 6, Color(1.0, 0.85, 0.55) * tint)
	else:
		var face := PackedVector2Array([centre + Vector2(-22, -4), centre + Vector2(14, -16), centre + Vector2(24, -4), centre + Vector2(-12, 8)])
		canvas.draw_line(centre + Vector2(1, 2), centre + Vector2(1, 20), Color(0.7, 0.7, 0.72) * tint, 3.0)
		canvas.draw_colored_polygon(face, Color(0.2, 0.32, 0.75) * tint)
		canvas.draw_polyline(face + PackedVector2Array([face[0]]), Color(0.7, 0.75, 0.85) * tint, 1.5)
		canvas.draw_line(face[0].lerp(face[1], 0.5), face[3].lerp(face[2], 0.5), Color(0.7, 0.75, 0.85, 0.6) * tint, 1.0)


## The crosshair, filling as E's held, and the pod's marker.
func _draw_overlay() -> void:
	if _overlay.size.x < 200.0:
		return
	var centre := _overlay.size * 0.5
	var player := game.player
	_overlay.draw_circle(centre, 2.5, Color(1, 1, 1, 0.85))
	if player.weapon == &"gun":
		var camera := player.camera
		var bloom := tan(deg_to_rad(player.spread)) / tan(deg_to_rad(camera.fov * 0.5)) * _overlay.size.y * 0.5 + 5.0
		for side in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			_overlay.draw_line(centre + side * bloom, centre + side * (bloom + 8.0), Color(1, 1, 1, 0.8), 2.0)
	if player.progress > 0.0:
		_overlay.draw_arc(centre, 16, 0, TAU, 32, Color(1, 1, 1, 0.15), 3.0)
		_overlay.draw_arc(centre, 16, -PI * 0.5, -PI * 0.5 + TAU * minf(player.progress, 1.0), 32, ORE_COLOR, 3.0)
	elif player.prompt != "":
		_overlay.draw_arc(centre, 10, 0, TAU, 24, Color(1, 1, 1, 0.5), 1.5)
	_draw_pod_marker(centre)
	_draw_rig_markers()
	_draw_blueprint_markers()


func _draw_blueprint_markers() -> void:
	var camera := game.player.camera
	var font := _overlay.get_theme_default_font()
	for plan in game.blueprints:
		var top := plan.global_position + plan.normal * 2.6
		if camera.is_position_behind(top) or camera.global_position.distance_to(top) > 70.0:
			continue
		var at := camera.unproject_position(top)
		var text := "BUILD %s %d/%d" % [String(Fixture.NAMES[plan.kind]).to_upper(), plan.hits, plan.hits_needed()]
		_overlay.draw_rect(Rect2(at - Vector2(6, 6), Vector2(12, 12)), BLUEPRINT_COLOR, false, 2.0)
		_overlay.draw_string_outline(font, at + Vector2(-80, -14), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 13, 4, Color(0, 0, 0, 0.7))
		_overlay.draw_string(font, at + Vector2(-80, -14), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 13, BLUEPRINT_COLOR)


func _draw_rig_markers() -> void:
	var camera := game.player.camera
	var font := _overlay.get_theme_default_font()
	for rig in game.built:
		if rig.kind != &"drill":
			continue
		var top := rig.global_position + rig.normal * 4.6
		if camera.is_position_behind(top):
			continue
		var at := camera.unproject_position(top)
		var color := ORE_COLOR if rig.stalled == "" else (COLD_COLOR if rig.stalled == "dark" else DAY_COLOR)
		var text := "RIG %d/%d%s" % [rig.stored, Fixture.HOPPER, "" if rig.stalled == "" else "  " + rig.stalled.to_upper()]
		_overlay.draw_arc(at, 7, 0, TAU, 16, color, 2.0)
		_overlay.draw_string_outline(font, at + Vector2(-60, -14), text, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, 4, Color(0, 0, 0, 0.7))
		_overlay.draw_string(font, at + Vector2(-60, -14), text, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, color)


func _draw_pod_marker(centre: Vector2) -> void:
	var camera := game.player.camera
	var top := game.pod.global_position + game.pod.normal * 4.5
	var at := camera.unproject_position(top)
	var margin := 60.0
	var bounds := Rect2(Vector2(margin, margin), _overlay.size - Vector2(margin, margin) * 2.0)
	var pinned := camera.is_position_behind(top) or !bounds.has_point(at)
	if pinned:
		var dir := at - centre
		if camera.is_position_behind(top):
			dir = -dir
		dir = dir.normalized() if dir.length() > 0.01 else Vector2.DOWN
		var scale := minf(absf((bounds.size.x * 0.5) / dir.x) if dir.x != 0.0 else INF, absf((bounds.size.y * 0.5) / dir.y) if dir.y != 0.0 else INF)
		at = centre + dir * scale
	var r := 8.0
	var diamond := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
	_overlay.draw_colored_polygon(diamond, Color(POD_COLOR, 0.35))
	_overlay.draw_polyline(diamond + PackedVector2Array([diamond[0]]), POD_COLOR, 2.0)
	var distance := camera.global_position.distance_to(game.pod.global_position)
	var font := _overlay.get_theme_default_font()
	_overlay.draw_string_outline(font, at + Vector2(-60, -16), "POD %dm" % distance, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, 4, Color(0, 0, 0, 0.7))
	_overlay.draw_string(font, at + Vector2(-60, -16), "POD %dm" % distance, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, POD_COLOR)


func _label(size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _panel(content: Control, margin: int = 14) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)
	return panel


## Pins a control to a point on the screen (anchor, as a fraction of it),
## offset by pixels, growing the given ways as its content needs room.
func _place(control: Control, anchor: Vector2, offset: Vector2, grow_x: Control.GrowDirection, grow_y: Control.GrowDirection) -> void:
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	control.offset_left = offset.x
	control.offset_right = offset.x
	control.offset_top = offset.y
	control.offset_bottom = offset.y
	control.grow_horizontal = grow_x
	control.grow_vertical = grow_y
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _fill(control: Control) -> void:
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _clock_text(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
