class_name Commander
extends Node3D
## The commander's view from the pod: overhead on the crater. WASD or the
## screen edges pan, the wheel zooms, holding the middle button turns it,
## and X climbs back out. A placeholder until the commander can give
## orders.

const PAN_SPEED := 40.0
const EDGE := 12.0
const MIN_HEIGHT := 18.0
const MAX_HEIGHT := 140.0

var game: Game
var camera: Camera3D

var _height := 70.0
var _yaw := 0.0
var _label: Label
var _layer: CanvasLayer


func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 2000.0
	camera.fov = 55.0
	add_child(camera)
	_layer = CanvasLayer.new()
	add_child(_layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.position = Vector2(24, 20)
	_layer.add_child(_label)
	global_position = game.pod.global_position
	_place_camera()


func enter() -> void:
	visible = true
	_layer.visible = true
	camera.make_current()
	global_position = game.pod.global_position
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func leave() -> void:
	visible = false
	_layer.visible = false


func _process(delta: float) -> void:
	if !visible:
		return
	var pan := Vector2(_axis(KEY_D, KEY_A), _axis(KEY_S, KEY_W))
	var mouse := get_viewport().get_mouse_position()
	var size := get_viewport().get_visible_rect().size
	if DisplayServer.window_is_focused():
		if mouse.x < EDGE:
			pan.x -= 1.0
		elif mouse.x > size.x - EDGE:
			pan.x += 1.0
		if mouse.y < EDGE:
			pan.y -= 1.0
		elif mouse.y > size.y - EDGE:
			pan.y += 1.0
	var turn := Basis(Vector3.UP, _yaw)
	global_position += turn * Vector3(pan.x, 0, pan.y).limit_length(1.0) * PAN_SPEED * (_height / 70.0) * delta
	var flat := Vector2(global_position.x, global_position.z).limit_length(Terrain.FLOOR_RADIUS + 10.0)
	global_position = Vector3(flat.x, 0.0, flat.y)
	_place_camera()
	_label.text = "COMMAND    ore %d / %d    battery %d / %d    launch in %d:%02d\n[WASD / screen edge] pan    [wheel] zoom    [hold middle mouse] turn    [X] leave the pod" % [
		game.stock, Game.QUOTA, game.battery, game.capacity(), int(maxf(0.0, Game.MISSION - game.time)) / 60, int(maxf(0.0, Game.MISSION - game.time)) % 60]


func _unhandled_input(event: InputEvent) -> void:
	if !visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_height = maxf(MIN_HEIGHT, _height * 0.88)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_height = minf(MAX_HEIGHT, _height / 0.88)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_yaw -= event.relative.x * 0.005
	elif event is InputEventKey and event.pressed and !event.echo and event.physical_keycode == KEY_X:
		game.act(&"uncommand", [])


func _place_camera() -> void:
	var turn := Basis(Vector3.UP, _yaw)
	camera.global_position = global_position + turn * Vector3(0, _height, _height * 0.75)
	camera.look_at(global_position, Vector3.UP)


func _axis(positive: Key, negative: Key) -> float:
	return (1.0 if Input.is_physical_key_pressed(positive) else 0.0) - (1.0 if Input.is_physical_key_pressed(negative) else 0.0)
