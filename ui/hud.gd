class_name Hud
extends CanvasLayer
## Readouts. Top left, meters for health, the battery, suit warmth and
## the jetpack. Top right, the pod's launch clock and a strip of the next
## day and night where you're standing. Bottom, what's in the pod (ore
## against the quota, alloy, research under way) and what you carry (ore
## and flares). In the middle, a
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
const ALLOY_COLOR := Color(0.78, 0.82, 0.95)
const STOCK_WIDTH := 300.0
const POCKET_WIDTH := 150.0

var game: Game

var _meters := {}
var _launch: Label
var _launch_title: Label
var _sky: Label
var _strip: Control
var _stock: Control
var _notice: Label
var _hint: Label
var _prompt: Label
var _overlay: Control
var _outcome: PanelContainer
var _outcome_text: Label
var _frost_material: ShaderMaterial
var _hurt_material: ShaderMaterial
var _pause: Control
var _lobby_button: Button
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
	_lobby_button.visible = Net.leading()
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
	var music := HBoxContainer.new()
	music.add_theme_constant_override("separation", 12)
	var music_label := _label(18)
	music_label.text = "Music"
	music.add_child(music_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Music.volume
	slider.custom_minimum_size = Vector2(190, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(value: float) -> void: Music.volume = value)
	slider.drag_ended.connect(func(_changed: bool) -> void: Music.save_volume())
	music.add_child(slider)
	column.add_child(music)
	var effects := HBoxContainer.new()
	effects.add_theme_constant_override("separation", 12)
	var effects_label := _label(18)
	effects_label.text = "Effects"
	effects.add_child(effects_label)
	var effects_slider := HSlider.new()
	effects_slider.min_value = 0.0
	effects_slider.max_value = 1.0
	effects_slider.step = 0.05
	effects_slider.value = Sfx.volume
	effects_slider.custom_minimum_size = Vector2(190, 32)
	effects_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	effects_slider.value_changed.connect(func(value: float) -> void: Sfx.volume = value)
	effects_slider.drag_ended.connect(func(_changed: bool) -> void: Sfx.save_volume())
	effects.add_child(effects_slider)
	column.add_child(effects)
	for entry: Array in [["Resume", func() -> void: set_paused(false)],
			["Back to the lobby", func() -> void:
				get_tree().paused = false
				game.lobby_act(&"to_lobby", [])],
			["Leave" if Net.networked() else "Back to the menu", func() -> void:
				get_tree().paused = false
				Net.leave()
				get_tree().change_scene_to_file("res://menu/menu.tscn")],
			["Sound editor (F2)", func() -> void:
				set_paused(false)
				SoundEditor.toggle()],
			["Quit", func() -> void: get_tree().quit()]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(260, 48)
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(entry[1])
		column.add_child(button)
		if entry[0] == "Back to the lobby":
			_lobby_button = button
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
		_outcome_text.text = "%s\n\n%s" % [game.outcome, "Back to the lobby shortly, on a new asteroid." if Net.networked() else "[R] new asteroid    [Shift+R] same one"]
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
	var source: String = {"sun": "in sunlight", "lamp": "by a lamp", "base": "by the base's lights", "vent": "by a vent", "pod": "by the pod"}.get(game.lit_by, "IN THE DARK")
	_set_meter(&"warmth", warmth, "%d   %s" % [game.warmth, source], COLD_COLOR if game.lit_by == "" else Color.WHITE)
	var player := game.player
	_meters[&"fuel"].row.visible = game.equipped(&"jetpack")
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
	title.text = "ON THE ROCK"
	_launch_title = title
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
	if game.launch_at < INF:
		_launch_title.text = "POD LAUNCHES IN"
		_launch.text = _clock_text(maxf(0.0, game.launch_at - game.time))
		_launch.modulate = ALERT
	else:
		_launch_title.text = "ON THE ROCK"
		_launch.text = _clock_text(game.time)
		_launch.modulate = Color.WHITE
	var lit_now := !_forecast.is_empty() and _forecast[0]
	var change := _forecast.find(!lit_now)
	if _forecast.is_empty():
		_sky.text = ""
	elif change < 0:
		_sky.text = "The sun won't leave you here" if lit_now else "The sun won't reach you here"
	else:
		_sky.text = "%s in %s" % ["Sunset" if lit_now else "Sunrise", _clock_text(Sun.TURN * change / float(FORECAST_STEPS))]
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
	var launch := (game.launch_at - game.time) / Sun.TURN
	if launch < 1.0:
		_strip.draw_rect(Rect2(width * launch - 1.5, -3, 3, _strip.size.y + 6), ALERT)
	_strip.draw_rect(Rect2(0, -3, 2, _strip.size.y + 6), Color.WHITE)


func _build_bottom() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_stock = Control.new()
	_stock.custom_minimum_size = Vector2(STOCK_WIDTH + POCKET_WIDTH, 92)
	_stock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stock.draw.connect(_draw_stock)
	row.add_child(_panel(_stock))
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
	var labs := game.built.filter(func(f: Fixture) -> bool: return f.kind == &"lab" and f.researching != &"").size()
	_stock.custom_minimum_size.y = 92 + 22 * labs
	_stock.queue_redraw()
	var attack := "[LMB] fire    [RMB] aim" if game.player.weapon == &"gun" else "[LMB] smash / build"
	_hint.text = "%s    %s%s[Q] flare    [G] ping    [E] use    [F] headlamp    [Esc] pause" % [attack, "[1/2/wheel] rifle/hammer    " if game.equipped(&"gun") else "", "[MMB] grapple    " if game.equipped(&"grapple") else ""]


## The pod's stock: ore filling towards the quota, alloy, and each lab's
## research; then what you're carrying, and your flares.
func _draw_stock() -> void:
	var font := _stock.get_theme_default_font()
	var met := game.stock >= Game.QUOTA
	var ore_tint := DAY_COLOR if met else ORE_COLOR
	_stock.draw_string(font, Vector2(0, 12), "IN THE POD", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	var number := str(game.stock)
	_stock.draw_string(font, Vector2(0, 44), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ore_tint)
	var after := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x + 8.0
	_stock.draw_string(font, Vector2(after, 44), "/ %d ore%s" % [Game.QUOTA, "  quota met" if met else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, DIM)
	var bar := Rect2(0, 54, STOCK_WIDTH - 24, 8)
	_stock.draw_rect(bar, Color(1, 1, 1, 0.08))
	_stock.draw_rect(Rect2(bar.position, Vector2(bar.size.x * minf(float(game.stock) / Game.QUOTA, 1.0), bar.size.y)), ore_tint)
	for quarter: float in [0.25, 0.5, 0.75]:
		_stock.draw_line(Vector2(bar.size.x * quarter, bar.position.y), Vector2(bar.size.x * quarter, bar.end.y), PANEL, 2.0)
	_draw_gem(Vector2(6, 80), 6.0, ALLOY_COLOR)
	_stock.draw_string(font, Vector2(18, 86), "%d alloy" % game.alloy, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ALLOY_COLOR if game.alloy > 0 else DIM)
	var y := 92.0
	for lab in game.built:
		if lab.kind != &"lab" or lab.researching == &"":
			continue
		var upgrade: Dictionary = Game.UPGRADES[lab.researching]
		var done: float = clampf(lab.research_time / upgrade.time, 0.0, 1.0)
		var stalled := "  OFF" if !lab.enabled else ("  NO POWER" if lab.unpowered else "")
		_stock.draw_string(font, Vector2(0, y + 15), "%s%s" % [String(upgrade.name).capitalize(), stalled], HORIZONTAL_ALIGNMENT_LEFT, 150, 14, ALERT if stalled != "" else Color.WHITE)
		var track := Rect2(156, y + 7, STOCK_WIDTH - 220, 6)
		_stock.draw_rect(track, Color(1, 1, 1, 0.08))
		_stock.draw_rect(Rect2(track.position, Vector2(track.size.x * done, track.size.y)), BLUEPRINT_COLOR)
		_stock.draw_string(font, Vector2(track.end.x + 6, y + 15), "%d%%" % roundi(done * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
		y += 22.0
	var x := STOCK_WIDTH
	_stock.draw_line(Vector2(x - 12, 2), Vector2(x - 12, _stock.size.y - 2), EDGE, 1.0)
	_stock.draw_string(font, Vector2(x, 12), "CARRYING", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	var carrying := ORE_COLOR if game.carried > 0 else DIM
	_draw_gem(Vector2(x + 9, 34), 9.0, carrying)
	_stock.draw_string(font, Vector2(x + 26, 44), "%d ore%s" % [game.carried, "  + ammo box" if game.ammo_box else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, carrying if !game.ammo_box else DAY_COLOR)
	_stock.draw_string(font, Vector2(x, 72), "FLARES", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	for i in Game.FLARES_MAX:
		var at := Vector2(x + 7 + i * 18, 84)
		if i < game.flares_left:
			_stock.draw_circle(at, 6, DAY_COLOR)
		else:
			_stock.draw_arc(at, 6, 0, TAU, 16, DIM, 1.5)


func _draw_gem(at: Vector2, radius: float, color: Color) -> void:
	_stock.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius * 0.8, 0), at + Vector2(0, radius), at + Vector2(-radius * 0.8, 0)]), color)


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
	elif kind == &"armory":
		canvas.draw_rect(Rect2(centre + Vector2(-25, -10), Vector2(50, 30)), Color(0.42, 0.44, 0.46) * tint)
		canvas.draw_rect(Rect2(centre + Vector2(-26, -14), Vector2(52, 5)), Color(1.0, 0.45, 0.1) * tint)
		canvas.draw_rect(Rect2(centre + Vector2(-20, -5), Vector2(40, 22)), dark)
		for i in 3:
			canvas.draw_rect(Rect2(centre + Vector2(-16 + i * 12, -3), Vector2(8, 18)), white)
			canvas.draw_rect(Rect2(centre + Vector2(-15 + i * 12, -1), Vector2(6, 3)), Color(1.0, 0.45, 0.1) * tint)
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
	elif kind == &"pylon":
		canvas.draw_line(centre + Vector2(0, -20), centre + Vector2(0, 22), white, 3.0)
		canvas.draw_line(centre + Vector2(-12, -18), centre + Vector2(12, -18), gold, 3.0)
		canvas.draw_line(centre + Vector2(-26, -10), centre + Vector2(-12, -18), Color(0.5, 0.5, 0.52) * tint, 1.5)
		canvas.draw_line(centre + Vector2(12, -18), centre + Vector2(26, -10), Color(0.5, 0.5, 0.52) * tint, 1.5)
		canvas.draw_rect(Rect2(centre + Vector2(-6, 18), Vector2(12, 4)), Color(1.0, 0.45, 0.1) * tint)
	elif kind == &"foundry":
		canvas.draw_rect(Rect2(centre + Vector2(-24, -6), Vector2(48, 26)), white)
		canvas.draw_rect(Rect2(centre + Vector2(-25, -9), Vector2(50, 4)), gold)
		canvas.draw_rect(Rect2(centre + Vector2(-18, -24), Vector2(8, 16)), dark)
		canvas.draw_rect(Rect2(centre + Vector2(-9, 6), Vector2(18, 10)), Color(1.0, 0.5, 0.15) * tint)
	elif kind == &"turret":
		canvas.draw_rect(Rect2(centre + Vector2(-14, 4), Vector2(28, 18)), white)
		canvas.draw_rect(Rect2(centre + Vector2(-14, 8), Vector2(28, 3)), Color(1.0, 0.45, 0.1) * tint)
		canvas.draw_rect(Rect2(centre + Vector2(-10, -10), Vector2(18, 10)), gold)
		canvas.draw_line(centre + Vector2(6, -6), centre + Vector2(26, -14), dark, 4.0)
	elif kind == &"barricade":
		canvas.draw_rect(Rect2(centre + Vector2(-24, -12), Vector2(48, 30)), white)
		canvas.draw_rect(Rect2(centre + Vector2(-24, -4), Vector2(48, 4)), Color(1.0, 0.45, 0.1) * tint)
		canvas.draw_rect(Rect2(centre + Vector2(-24, 8), Vector2(48, 4)), Color(1.0, 0.45, 0.1) * tint)
		canvas.draw_rect(Rect2(centre + Vector2(-27, -14), Vector2(5, 34)), dark)
		canvas.draw_rect(Rect2(centre + Vector2(22, -14), Vector2(5, 34)), dark)
	elif kind == &"tap":
		canvas.draw_circle(centre + Vector2(0, -22), 9, Color(0.85, 0.8, 0.75, 0.35) * tint)
		canvas.draw_circle(centre + Vector2(6, -30), 7, Color(0.85, 0.8, 0.75, 0.25) * tint)
		canvas.draw_rect(Rect2(centre + Vector2(-6, -16), Vector2(12, 14)), dark)
		canvas.draw_rect(Rect2(centre + Vector2(-20, -2), Vector2(40, 22)), white)
		canvas.draw_rect(Rect2(centre + Vector2(-20, 4), Vector2(40, 4)), Color(1.0, 0.45, 0.1) * tint)
		canvas.draw_line(centre + Vector2(-13, -6), centre + Vector2(-13, 20), gold, 2.5)
		canvas.draw_line(centre + Vector2(13, -6), centre + Vector2(13, 20), gold, 2.5)
		canvas.draw_rect(Rect2(centre + Vector2(-24, 20), Vector2(48, 3)), Color(1.0, 0.4, 0.1) * tint)
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
	for ping in game.pings:
		_draw_ping(centre, ping)
	_draw_rig_markers()
	_draw_blueprint_markers()
	_draw_damage_markers()


func _draw_blueprint_markers() -> void:
	var camera := game.player.camera
	var font := _overlay.get_theme_default_font()
	for plan in game.blueprints:
		var top := plan.global_position + plan.normal * 2.6
		if camera.is_position_behind(top) or camera.global_position.distance_to(top) > 70.0:
			continue
		var at := camera.unproject_position(top)
		var text := "BUILD %s %d/%d%s" % [String(Fixture.NAMES[plan.kind]).to_upper(), plan.hits, plan.hits_needed(), "" if game.can_pay(plan) else "  BANK SHORT"]
		_overlay.draw_rect(Rect2(at - Vector2(6, 6), Vector2(12, 12)), BLUEPRINT_COLOR, false, 2.0)
		_overlay.draw_string_outline(font, at + Vector2(-80, -14), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 13, 4, Color(0, 0, 0, 0.7))
		_overlay.draw_string(font, at + Vector2(-80, -14), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 13, BLUEPRINT_COLOR)


## A bar over anything built that's been bitten, so it's patched up.
func _draw_damage_markers() -> void:
	var camera := game.player.camera
	for fixture: Fixture in game.built + [game.pod]:
		if fixture.health >= fixture.max_health - 0.5:
			continue
		var top := fixture.global_position + fixture.normal * Hud.bar_height(fixture)
		if camera.is_position_behind(top) or camera.global_position.distance_to(top) > 60.0:
			continue
		draw_health_bar(_overlay, camera.unproject_position(top) + Vector2(0, 10), fixture.health / fixture.max_health)


## How high over something its health bar goes.
static func bar_height(fixture: Fixture) -> float:
	if fixture.kind == &"pod":
		return 5.4
	if fixture.kind == &"drill":
		return 4.6
	return Fixture.CABLE_HEIGHT.get(fixture.kind, Fixture.GHOST_LIFT.get(fixture.kind, 1.0) * 2.0 + 0.4) + 0.4


## A small health bar centred on at: green, going yellow, then red.
static func draw_health_bar(canvas: CanvasItem, at: Vector2, fraction: float) -> void:
	var size := Vector2(46, 6)
	var box := Rect2(at - size * 0.5, size)
	var color := Color(1.0, 0.3, 0.25).lerp(Color(1.0, 0.8, 0.3), clampf(fraction * 2.0, 0.0, 1.0)).lerp(Color(0.4, 1.0, 0.45), clampf(fraction * 2.0 - 1.0, 0.0, 1.0))
	canvas.draw_rect(box.grow(1.5), Color(0, 0, 0, 0.7))
	canvas.draw_rect(Rect2(box.position, Vector2(size.x * clampf(fraction, 0.0, 1.0), size.y)), color)


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
	var text := "POD %dm" % distance
	var color := POD_COLOR
	if game.pod.health < game.pod.max_health:
		text += "  HULL %d%%" % roundi(game.pod.health / game.pod.max_health * 100.0)
		color = ALERT
	_overlay.draw_string_outline(font, at + Vector2(-80, -16), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 14, 4, Color(0, 0, 0, 0.7))
	_overlay.draw_string(font, at + Vector2(-80, -16), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 14, color)


## A ping, pinned to the screen's edge when it's out of view, fading out.
func _draw_ping(centre: Vector2, ping: Dictionary) -> void:
	var camera := game.player.camera
	var spot: Vector3 = ping.position
	var at := camera.unproject_position(spot)
	var margin := 60.0
	var bounds := Rect2(Vector2(margin, margin), _overlay.size - Vector2(margin, margin) * 2.0)
	var behind := camera.is_position_behind(spot)
	if behind or !bounds.has_point(at):
		var dir := at - centre
		if behind:
			dir = -dir
		dir = dir.normalized() if dir.length() > 0.01 else Vector2.DOWN
		var scale := minf(absf((bounds.size.x * 0.5) / dir.x) if dir.x != 0.0 else INF, absf((bounds.size.y * 0.5) / dir.y) if dir.y != 0.0 else INF)
		at = centre + dir * scale
	var fade := clampf((Game.PING_TIME - ping.age) / 1.5, 0.0, 1.0)
	var color := Color(DAY_COLOR if ping.commander else FUEL_COLOR, fade)
	_overlay.draw_arc(at, 9.0, 0, TAU, 20, color, 2.0)
	_overlay.draw_circle(at, 3.0, color)
	var text := "%s  %dm" % ["COMMANDER" if ping.commander else String(ping.name).to_upper(), camera.global_position.distance_to(spot)]
	var font := _overlay.get_theme_default_font()
	_overlay.draw_string_outline(font, at + Vector2(-80, -16), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 13, 4, Color(0, 0, 0, 0.7 * fade))
	_overlay.draw_string(font, at + Vector2(-80, -16), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 13, color)


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
