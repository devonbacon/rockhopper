class_name Player
extends CharacterBody3D
## You, in first person, inside the hologram wall.
##
## WASD walks (Shift runs), Space jumps, and holding Space in the air burns
## the jetpack, which refills on the ground. Left mouse fires, or swings
## the hammer, which also mines, puts up the commander's blueprints and
## patches up the pod and anything damaged. Q throws a flare; G pings what
## you're looking at for everyone; middle mouse, once researched, grapples. E
## is use: tap it at the pod to hand in ore, on a button on a screen to
## press it, or at a rig to empty its hopper; hold it on ore or a deposit
## to mine it, or on something built to pick it back up. E on a cable
## overhead grabs it and rides it the way you're facing, hanging off to
## the right; at a junction you carry on down whichever cable's nearest
## the way you're looking, and you drop off short of a dead end. E again
## or Space lets go. F toggles the headlamp.
##
## Soldiers lay the cables, with the hammer out: right mouse on a pylon,
## rig, foundry, turret or the pod (built or a blueprint) pays one out
## behind you; on another, it ties it on, and on open ground it puts a
## pylon blueprint there for it. A cable to a blueprint goes up once both
## ends are built. Right mouse on a cable turns it round; held, it cuts
## it.

const LAYER := 4
const GRAVITY := 5.0
const WALK := 3.5
const RUN := 6.0
const RUNNER_WALK := 5.0
const RUNNER_RUN := 8.5
const ACCEL := 30.0
const AIR_ACCEL := 10.0
const SLIDE_BOOST := 3.0
## Top speed sliding, and slide-jumping off it: low until you've
## got blade runners.
const SLIDE_MAX := 8.0
const RUNNER_SLIDE_MAX := 16.0
const SLIDE_FRICTION := 2.0
const SLIDE_SLOPE := 1.6
const SLIDE_STEER := 4.0
## Jumping out of a slide speeds you up, in blade runners.
const SLIDE_JUMP_BOOST := 1.1
## Without them, in the air you slow towards running speed this fast.
const AIR_DRAG := 2.0
const SLIDE_COOLDOWN := 0.8
const STRAFE_TILT := 2.5
const JUMP := 4.5
const JET := 11.0
const JET_DRAIN := 35.0
## The jetpack won't push you up faster than this.
const JET_RISE := 5.0
const JET_REFILL := 45.0
const REACH := 4.5
## How far off you can aim at what a cable ties to, and how long R's held
## to cut one.
const CABLE_REACH := 10.0
const CUT_TIME := 0.8
const BUILD_REACH := 8.0
const MINE_TIME := 1.5
const PICK_UP_TIME := 0.5
const FIRE_EVERY := 0.32
const FOV := 80.0
const ADS_FOV := 52.0
const ADS_SPEED := 2.4
const HIP_GUN := Vector3(0.2, -0.17, -0.36)
const ADS_GUN := Vector3(0.0, -0.1, -0.3)
## Bloom, in degrees: the cone shots land in. It rests wider moving, grows
## with each shot, and settles back.
const HIP_SPREAD := 1.2
const ADS_SPREAD := 0.15
const MOVING_SPREAD := 2.5
const HIP_KICK := 0.9
const ADS_KICK := 0.35
const MAX_SPREAD := 7.0
const SETTLE := 9.0
const DAMAGE := 10.0
const GUN_RANGE := 60.0
const HAMMER_EVERY := 0.75
## Two blows kill a spider; each knocks it back a little and stuns it.
const HAMMER_DAMAGE := 15.0
const HAMMER_KNOCK := 4.0
const HAMMER_STUN := 1.0
const HAMMER_REACH := 3.2
const GRAPPLE_RANGE := 25.0
const GRAPPLE_PULL := 14.0
const GRAPPLE_MAX := 10.0
## After letting go, or yanking a spider, before it'll fire again.
const GRAPPLE_COOLDOWN := 5.0
const ZIP_SPEED := 11.0
## How far a cable can be from the crosshair's line to grab it.
const ZIP_GRAB := 0.7
## How far short of a dead end you let go.
const ZIP_DROP := 2.0
const FLARE_EVERY := 0.5
const PING_RANGE := 300.0
## How far out from the middle you can go: the hologram wall.
const BOUNDS := Terrain.FLOOR_RADIUS - 0.6
const SENSITIVITY := 0.0025
const HEIGHT := 1.8

var game: Game
var camera: Camera3D
var headlamp: SpotLight3D
var fuel := 100.0
var weapon := &"hammer"
var hooked := false
## The cable you're riding, how far along, and which way.
var zip: Link
var _zip_at := 0.0
var _zip_dir := 1.0
## Which side of the cable you hang off, eased round at junctions.
var _zip_side := Vector3.ZERO
var _jump_was_down := false
## What E would do now, and how far through a hold it is, for the HUD.
var prompt := ""
var progress := 0.0
var jetting := false
## A line of feedback for the HUD, and how long it's still shown.
var notice := ""
var notice_time := 0.0

var _head: Node3D
var _pitch := 0.0
var pitch: float:
	get: return _pitch
var _use_target: Fixture
var _use_held := 0.0
var _use_was_down := false
var _screen: Screen
var _cooldown := 0.0
var _recoil := 0.0
var aiming := false
var sliding := false
var _slide_cooldown := 0.0
var _crouch := 0.0
var debug_aim := false
var spread := HIP_SPREAD
var _ads := 0.0
var _gun: Node3D
var _muzzle: Node3D
var _muzzle_light: OmniLight3D
var _hammer: Node3D
var _swing := 0.0
var _hook_point := Vector3.ZERO
var _hook_cooldown := 0.0
var _rope: MeshInstance3D
var _rope_flash := 0.0
var _yank_from := Vector3.ZERO
var _flare_cooldown := 0.0
## Where the cable you're paying out runs from, if you are.
var reel: Fixture
var _reel_line: MeshInstance3D
var _r_was_down := false
var _cut_held := 0.0
## The cable lit up under the crosshair.
var _lit: Link
## What R would do, added to the prompt.
var _cable_hint := ""
var _space_was_down := false


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = Terrain.ROCK_LAYER | Fixture.LAYER
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.4
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = HEIGHT
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = HEIGHT * 0.5
	add_child(collider)
	_head = Node3D.new()
	_head.position.y = HEIGHT - 0.15
	add_child(_head)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 1500.0
	_head.add_child(camera)
	headlamp = SpotLight3D.new()
	headlamp.light_color = Color(0.85, 0.92, 1.0)
	headlamp.spot_range = 11.0
	headlamp.spot_angle = 20.0
	headlamp.light_energy = 1.6
	headlamp.position = Vector3(0.2, -0.1, 0)
	camera.add_child(headlamp)
	_build_gun()
	_build_hammer()
	_gun.visible = false
	_hammer.visible = true
	_rope = _line(Color(1.0, 0.6, 0.2))
	_reel_line = _line(Link.ORE)


## Turns the body so its up points away from the centre, keeping where it
## faces as near as it can.
func align_up() -> void:
	var up := Terrain.up_at(global_position)
	var b := global_basis.orthonormalized()
	var angle := b.y.angle_to(up)
	if angle > 0.0001:
		b = Basis(b.y.cross(up).normalized(), angle) * b
	global_basis = b.orthonormalized()
	up_direction = up


func look(pitch: float) -> void:
	_pitch = pitch
	_head.rotation.x = _pitch


func _unhandled_input(event: InputEvent) -> void:
	if !game or game.state != Game.State.PLAYING or SoundEditor.open:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		var sensitivity := SENSITIVITY * camera.fov / FOV
		rotate_object_local(Vector3.UP, -event.relative.x * sensitivity)
		look(clampf(_pitch - event.relative.y * sensitivity, -1.5, 1.5))
	elif event is InputEventMouseButton and event.pressed:
		if !captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_switch(&"hammer" if weapon == &"gun" else &"gun", false)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_throw_hook()
	elif event is InputEventKey and event.pressed and !event.echo:
		match event.physical_keycode:
			KEY_F: headlamp.visible = !headlamp.visible
			KEY_1: _switch(&"gun")
			KEY_2: _switch(&"hammer")
			KEY_G: _ping()
			KEY_Q: _throw_flare()


func _physics_process(delta: float) -> void:
	align_up()
	var downed := game.down_left >= 0.0
	var playing := game.state == Game.State.PLAYING and !SoundEditor.open and !downed
	if weapon == &"gun" and !game.equipped(&"gun"):
		_switch(&"hammer")
	if is_instance_valid(zip):
		_ride(delta, playing)
	else:
		zip = null
		_walk(delta, playing)
	_hook_cooldown = maxf(0.0, _hook_cooldown - delta)
	_flare_cooldown = maxf(0.0, _flare_cooldown - delta)
	_draw_rope(delta)
	Sfx.hold(&"jet", jetting)
	Sfx.hold(&"zip", zip != null)
	_swing = maxf(0.0, _swing - delta / HAMMER_EVERY)
	_hammer.rotation.x = -1.3 * sin(_swing * PI) if _swing > 0.0 else 0.0
	notice_time = maxf(0.0, notice_time - delta)
	_cooldown = maxf(0.0, _cooldown - delta)
	_recoil = maxf(0.0, _recoil - delta * 12.0)
	_muzzle_light.light_energy = _recoil * 3.0
	_gun.position = HIP_GUN.lerp(ADS_GUN, _ads) + Vector3(0, 0, _recoil * 0.04)
	var moving := clampf((velocity - up_direction * velocity.dot(up_direction)).length() / RUN, 0.0, 1.0)
	var rest := lerpf(HIP_SPREAD, ADS_SPREAD, _ads) * (0.6 if game.has(&"stabiliser") else 1.0) + moving * MOVING_SPREAD * lerpf(1.0, 0.3, _ads)
	if !is_on_floor():
		rest += 2.0
	spread = move_toward(spread, rest, SETTLE * delta) if spread > rest else rest
	if !playing or !is_instance_valid(reel):
		reel = null
	var space := Input.is_physical_key_pressed(KEY_SPACE)
	if downed:
		prompt = "DOWN  %d s\nHold on: another soldier can hold E on you to get you up\n[Space] Give up and go back to the pod" % ceili(game.down_left)
		progress = 0.0
		if space and !_space_was_down and !SoundEditor.open:
			game.act(&"give_up", [])
	_space_was_down = space
	_reel_line.visible = reel != null
	if reel:
		_stretch(_reel_line, reel.cable_point(), camera.global_transform * Vector3(0.2, -0.3, -0.3))
	if playing:
		_cable_hint = ""
		_use(delta)
		if _cable_hint != "":
			prompt = _cable_hint if prompt == "" else prompt + "\n" + _cable_hint
		var trigger := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if trigger and _cooldown <= 0.0:
			if weapon == &"gun":
				_fire()
			else:
				_smash()


## Hanging under a cable, sliding along it and on through junctions; off
## short of a dead end, or on Space, carrying the speed.
func _ride(delta: float, playing: bool) -> void:
	aiming = false
	sliding = false
	jetting = false
	_ads = move_toward(_ads, 0.0, delta * 7.0)
	camera.fov = lerpf(FOV + 6.0, ADS_FOV, _ads)
	var jump := playing and Input.is_physical_key_pressed(KEY_SPACE)
	var start := zip.start()
	var span := start.distance_to(zip.end())
	var along := (zip.end() - start) / span
	_zip_at += _zip_dir * ZIP_SPEED * delta
	velocity = along * _zip_dir * ZIP_SPEED
	var jumped := jump and !_jump_was_down
	_jump_was_down = jump
	var left := span - _zip_at if _zip_dir > 0.0 else _zip_at
	var node := zip.to if _zip_dir > 0.0 else zip.from
	var next: Link = _next_cable(node, along * _zip_dir) if left < ZIP_DROP else null
	if !playing or jumped or (left < ZIP_DROP and !next):
		let_go(jump)
		return
	if left <= 0.0:
		_zip_dir = 1.0 if next.from == node else -1.0
		zip = next
		start = zip.start()
		span = start.distance_to(zip.end())
		along = (zip.end() - start) / span
		_zip_at = -left if _zip_dir > 0.0 else span + left
	var right := (along * _zip_dir).cross(up_direction).normalized()
	_zip_side = _zip_side.lerp(right, 1.0 - exp(-6.0 * delta))
	global_position = start + along * _zip_at - up_direction * Link.HANG + _zip_side * Link.SIDE


## The strung cable off node, other than the one you're on, that runs
## closest to the way you're looking, if any runs within 80 degrees of it
## and on ahead of you.
func _next_cable(node: Fixture, heading: Vector3) -> Link:
	var look := -camera.global_basis.z
	look -= up_direction * look.dot(up_direction)
	var best: Link = null
	var best_dot := cos(deg_to_rad(80.0))
	for link in game.links:
		if link == zip or link.blueprint or (link.from != node and link.to != node):
			continue
		var out := ((link.end() - link.start()) * (1.0 if link.from == node else -1.0)).normalized()
		var flat := out - up_direction * out.dot(up_direction)
		var dot := flat.normalized().dot(look.normalized())
		if dot > best_dot and out.dot(heading) > -0.5:
			best_dot = dot
			best = link
	return best


func _grab(link: Link, at: float) -> void:
	hooked = false
	zip = link
	var span := link.length()
	_zip_at = clampf(at, 0.7, span - 0.7)
	var along := (link.end() - link.start()) / span
	var ahead := -global_basis.z
	_zip_dir = 1.0 if along.dot(ahead) >= 0.0 else -1.0
	_zip_side = (along * _zip_dir).cross(up_direction).normalized()
	_jump_was_down = Input.is_physical_key_pressed(KEY_SPACE)
	Sfx.play(&"latch")
	_say("Riding the cable: [E] or [Space] to let go")


func let_go(jump := false) -> void:
	zip = null
	velocity *= 0.8
	if jump:
		velocity += up_direction * JUMP * 0.6


## The cable the crosshair's on, within reach, strung or still a
## blueprint: [link, metres along, how far off], or [] for none.
func _aim_cable(reach: float, plans := false) -> Array:
	var from := camera.global_position
	var dir := -camera.global_basis.z
	var best: Array = []
	for link in game.links:
		if link.blueprint != plans:
			continue
		var near: Array = link.nearest_to_ray(from, dir)
		if near[0] < ZIP_GRAB and near[2] < reach and (best.is_empty() or near[2] < best[2]):
			best = [link, near[1], near[2]]
	return best


## On foot, or in the air: walking, running, sliding, jumping, the jetpack
## and the grapple.
func _walk(delta: float, playing: bool) -> void:
	var up := up_direction
	var vertical := up * velocity.dot(up)
	var horizontal := velocity - vertical
	var input := Vector2.ZERO
	if playing:
		input = Vector2(_axis(KEY_D, KEY_A), _axis(KEY_W, KEY_S)).limit_length(1.0)
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	aiming = playing and weapon == &"gun" and (debug_aim or captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	_ads = move_toward(_ads, 1.0 if aiming else 0.0, delta * 7.0)
	var rush := clampf((horizontal.length() - RUN) * 1.2, 0.0, 12.0)
	camera.fov = lerpf(FOV + rush, ADS_FOV, _ads)
	var walk := RUNNER_WALK if game.equipped(&"runners") else WALK
	var speed := ADS_SPEED if aiming else ((RUNNER_RUN if game.equipped(&"runners") else RUN) if Input.is_physical_key_pressed(KEY_SHIFT) else walk)
	var wish_dir := global_basis.x * input.x - global_basis.z * input.y
	var wish := wish_dir * speed
	var jump_held := playing and Input.is_physical_key_pressed(KEY_SPACE)
	var crouch := playing and !aiming and (Input.is_physical_key_pressed(KEY_C) or Input.is_physical_key_pressed(KEY_CTRL))
	_slide_cooldown = maxf(0.0, _slide_cooldown - delta)
	jetting = false
	if hooked:
		_reel(delta, playing)
	if is_on_floor() and !hooked:
		var ground_speed := horizontal.length()
		var slide_max := RUNNER_SLIDE_MAX if game.equipped(&"runners") else SLIDE_MAX
		if !sliding and crouch and ground_speed > walk * 0.9:
			sliding = true
			if _slide_cooldown <= 0.0:
				horizontal = horizontal.normalized() * minf(ground_speed + SLIDE_BOOST, slide_max)
				_slide_cooldown = SLIDE_COOLDOWN
		if sliding and (!crouch or ground_speed < walk * 0.6):
			sliding = false
		if sliding:
			var gravity := -up * GRAVITY
			var normal := get_floor_normal()
			var downhill := gravity - normal * gravity.dot(normal)
			horizontal += (downhill - up * downhill.dot(up)) * SLIDE_SLOPE * delta
			horizontal = horizontal.move_toward(Vector3.ZERO, SLIDE_FRICTION * delta)
			horizontal = (horizontal + wish_dir * SLIDE_STEER * delta).limit_length(slide_max)
		else:
			horizontal = horizontal.move_toward(wish, ACCEL * delta)
		fuel = minf(100.0, fuel + JET_REFILL * delta)
		if jump_held:
			vertical = up * JUMP
			if sliding and game.equipped(&"runners"):
				horizontal = (horizontal * SLIDE_JUMP_BOOST).limit_length(slide_max)
	else:
		sliding = false
		jetting = jump_held and fuel > 0.0 and game.equipped(&"jetpack")
		var control := AIR_ACCEL + (JET * 0.6 if jetting else 0.0)
		var target := speed * (1.2 if jetting else 1.0)
		if !game.equipped(&"runners") and !jetting and !hooked and horizontal.length() > RUN:
			horizontal = horizontal.limit_length(maxf(RUN, horizontal.length() - AIR_DRAG * delta))
		if input != Vector2.ZERO:
			var along := horizontal.dot(wish_dir.normalized())
			if along < target:
				horizontal += wish_dir.normalized() * minf(target - along, control * delta)
		if jetting:
			if vertical.dot(up) < JET_RISE:
				vertical += up * JET * delta
			fuel = maxf(0.0, fuel - JET_DRAIN * (0.6 if game.has(&"tanks") else 1.0) * delta)
	_crouch = move_toward(_crouch, 1.0 if sliding else 0.0, delta * 8.0)
	_head.position.y = lerpf(HEIGHT - 0.15, 0.95, _crouch)
	var side := clampf(horizontal.dot(global_basis.x) / RUN, -1.0, 1.0)
	camera.rotation.z = lerpf(camera.rotation.z, -side * deg_to_rad(STRAFE_TILT), minf(1.0, delta * 10.0))
	vertical -= up * GRAVITY * delta
	velocity = horizontal + vertical
	if hooked:
		var pull := (_hook_point - global_position).normalized()
		velocity = (velocity + pull * GRAPPLE_PULL * delta).limit_length(GRAPPLE_MAX)
	var flat := Vector2(global_position.x, global_position.z)
	if flat.length() > BOUNDS and Vector2(velocity.x, velocity.z).dot(flat) > 0.0:
		var out := Vector3(flat.x, 0.0, flat.y).normalized()
		velocity -= out * velocity.dot(out)
	move_and_slide()


func _axis(positive: Key, negative: Key) -> float:
	return (1.0 if Input.is_physical_key_pressed(positive) else 0.0) - (1.0 if Input.is_physical_key_pressed(negative) else 0.0)


## What the crosshair's on, within reach.
func _aim(reach: float) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * reach
	var query := PhysicsRayQueryParameters3D.create(from, to, Terrain.ROCK_LAYER | Fixture.LAYER, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


func _use(delta: float) -> void:
	var hit := _aim(REACH)
	var target: Fixture = hit.collider if !hit.is_empty() and hit.collider is Fixture else null
	var down := Input.is_physical_key_pressed(KEY_E)
	var pressed := down and !_use_was_down
	var released := !down and _use_was_down
	_use_was_down = down
	if target != _use_target:
		_use_target = target
		_use_held = 0.0
	prompt = ""
	progress = 0.0
	if zip:
		prompt = "[E] / [Space] Let go"
		if pressed:
			let_go()
		return
	var fallen := _fallen_ahead()
	if fallen != 0:
		prompt = "%s is down\n[Hold E] Get them up" % game.name_of(fallen)
		_hold(down, delta, Game.REVIVE_TIME, func() -> void: game.act(&"revive", [fallen]))
		return
	if _lay_cable(delta):
		return
	if _aim_screen():
		if _screen.hover != &"":
			var described: String = _screen.describe.call(_screen.hover)
			prompt = described if described != "" else "[E] " + String(_screen.button.call(_screen.hover)[0]).capitalize()
			if pressed:
				Sfx.play(&"press")
				_screen.press()
		return
	var cable := _aim_cable(REACH + 2.0)
	if !cable.is_empty() and (!target or cable[2] < camera.global_position.distance_to(hit.position)):
		prompt = "[E] Ride the cable"
		if pressed:
			_grab(cable[0], cable[1])
		return
	var plan := _aim_cable(HAMMER_REACH + 1.0, true)
	if !plan.is_empty() and (!target or plan[2] < camera.global_position.distance_to(hit.position)):
		var link: Link = plan[0]
		if link.from.blueprint or link.to.blueprint:
			prompt = "Cable blueprint\nBuild both ends first"
		else:
			prompt = "Cable blueprint\n%s" % ("[LMB] Hammer it up" if weapon == &"hammer" else "[2] Hammer it up")
		return
	if !target:
		return
	if target.blueprint:
		var cost := Game.price(target.blow_cost(), target.blow_cost(true))
		prompt = "%s blueprint: %d / %d\n%s%s" % [Fixture.NAMES[target.kind], target.hits, target.hits_needed(), "[LMB] Hammer it up" if weapon == &"hammer" else "[2] Hammer it up", "" if target.blow_cost() + target.blow_cost(true) == 0 else (" (%s from the pod)" % cost if game.can_pay(target) else "\nNot enough in the pod: %s a blow" % cost)]
		return
	match target.kind:
		&"deposit":
			prompt = "[Hold E] Mine" + ("" if target.rig == null else "    a rig's on it")
			_hold(down, delta, MINE_TIME, func() -> void: game.act(&"mine", [target.net_id]))
		&"drill":
			var why: String = {"": "drilling", "dark": "too dark to drill", "full": "hopper full", "off": "switched off"}[target.stalled]
			prompt = "Rig: %d / %d, %s\n[E] Empty hopper    [Hold E] Pick up" % [target.stored, Fixture.HOPPER, why]
			# A tap empties the hopper; holding on picks the rig up.
			if released and _use_held < 0.3 and target.stored > 0:
				game.act(&"empty_rig", [target.net_id])
			_hold(down, delta, PICK_UP_TIME * 2.0, func() -> void: game.act(&"pick_up", [target.net_id]))
			if progress < 0.3 / (PICK_UP_TIME * 2.0):
				progress = 0.0
		&"pod":
			prompt = ("[E] Hand in %d ore" % game.carried) if game.carried > 0 else ("Drop pod: %d ore banked" % game.stock)
			if target.health < target.max_health:
				prompt += "\nHull %d%%: hammer it to patch it up" % roundi(target.health / target.max_health * 100.0)
			if pressed:
				game.act(&"hand_in", [])
		&"ore":
			prompt = "[Hold E] Mine ore (%d)" % target.amount
			_hold(down, delta, MINE_TIME, func() -> void: game.act(&"mine", [target.net_id]))
		&"foundry":
			prompt = "Foundry: %d ore in, %d alloy made, %s\n[Hold E] Pick up" % [target.ore_in, target.alloy_out, "smelting" if target.stalled == "" else target.stalled]
			_hold(down, delta, PICK_UP_TIME * 2.0, func() -> void: game.act(&"pick_up", [target.net_id]))
		&"turret":
			var state: String = "ready" if target.stalled == "" else target.stalled
			prompt = "Turret: %d / %d shots, %s\n%s[Hold E] Pick up" % [target.ammo, Fixture.MAGAZINE, state, "[E] Load ore    " if game.carried > 0 else ""]
			# A tap loads it; holding on picks it up.
			if released and _use_held < 0.3 and game.carried > 0:
				game.act(&"load", [target.net_id])
			_hold(down, delta, PICK_UP_TIME * 2.0, func() -> void: game.act(&"pick_up", [target.net_id]))
			if progress < 0.3 / (PICK_UP_TIME * 2.0):
				progress = 0.0
		&"armory":
			var mine := game.racked.filter(func(entry: Array) -> bool: return entry[1] == Net.local_id()).map(func(entry: Array) -> String: return String(Game.UPGRADES[entry[0]].name).capitalize())
			var busy := "idle" if target.researching == &"" else "making a %s for %s" % [String(Game.UPGRADES[target.researching].name).capitalize(), game.name_of(target.made_for)]
			prompt = "Armory: %s\n%s[Hold E] Pick up" % [busy, ("[E] Gear up: %s    " % ", ".join(mine)) if !mine.is_empty() else ""]
			# A tap gears you up; holding on picks it up.
			if released and _use_held < 0.3 and !mine.is_empty():
				game.act(&"gear_up", [target.net_id])
			_hold(down, delta, PICK_UP_TIME * 2.0, func() -> void: game.act(&"pick_up", [target.net_id]))
			if progress < 0.3 / (PICK_UP_TIME * 2.0):
				progress = 0.0
		&"lamp", &"panel", &"battery", &"lab", &"pylon", &"barricade":
			prompt = "[Hold E] Pick up %s" % target.kind
			_hold(down, delta, PICK_UP_TIME, func() -> void: game.act(&"pick_up", [target.net_id]))


## The fallen soldier you're stood over and facing, if any.
func _fallen_ahead() -> int:
	var look := -camera.global_basis.z
	look -= up_direction * look.dot(up_direction)
	for peer: int in game.bodies:
		var body: Node3D = game.bodies[peer]
		if !(body is Avatar) or !(body as Avatar).down:
			continue
		var to := body.global_position - global_position
		to -= up_direction * to.dot(up_direction)
		if to.length() < Game.REVIVE_REACH and (to.length() < 0.6 or look.normalized().dot(to.normalized()) > 0.5):
			return peer
	return 0


## Right mouse, with the hammer out: paying a cable out, tying it on, or
## putting a pylon down for it; and turning cables round or cutting them.
## True while a cable's being paid out, which is all the prompt's about
## then.
func _lay_cable(delta: float) -> bool:
	var down := weapon == &"hammer" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var pressed := down and !_r_was_down
	var released := !down and _r_was_down
	_r_was_down = down
	if !is_instance_valid(reel) or weapon != &"hammer":
		reel = null
	if is_instance_valid(_lit):
		_lit.highlight = false
	_lit = null
	if weapon != &"hammer":
		_cut_held = 0.0
		return false
	var hit := _aim(CABLE_REACH)
	var target: Fixture = hit.collider if !hit.is_empty() and hit.collider is Fixture else null
	if target and target.kind == &"deposit" and target.rig:
		target = target.rig
	if reel:
		var start := "pod" if reel == game.pod else Fixture.NAMES[reel.kind] as String
		if reel.cable_point().distance_to(global_position) > Link.RANGE + 4.0:
			reel = null
			_say("Too far: the cable slipped off the %s" % start)
			return false
		if target and target != reel and Fixture.CABLE_HEIGHT.has(target.kind):
			var to_name := "pod" if target == game.pod else Fixture.NAMES[target.kind] as String
			var why := game.can_link(reel, target)
			prompt = "Cable from the %s\n%s" % [start, ("[RMB] Tie it to the %s" % to_name) if why == "" else why]
			if pressed and why == "":
				Sfx.play(&"latch")
				game.act(&"link", [reel.net_id, target.net_id])
				reel = null
		elif target == reel:
			prompt = "Cable from the %s\n[RMB] Let it go" % start
			if pressed:
				reel = null
		elif !hit.is_empty() and !target:
			var why := game.can_link_pylon(reel, hit.position, hit.normal)
			prompt = "Cable from the %s\n%s" % [start, "[RMB] A new pylon here" if why == "" else why]
			if pressed and why == "":
				Sfx.play(&"place")
				game.act(&"link_pylon", [reel.net_id, hit.position, hit.normal])
				reel = null
		else:
			prompt = "Cable from the %s\n[RMB] on a pylon, rig, foundry, turret or the pod ties it on;\non open ground, a new pylon" % start
		return true
	var cable := _aim_cable(REACH + 2.0)
	if cable.is_empty():
		cable = _aim_cable(REACH + 2.0, true)
	if !cable.is_empty() and (!target or cable[2] < camera.global_position.distance_to(hit.position)):
		var link: Link = cable[0]
		_lit = link
		link.highlight = true
		_cable_hint = "[RMB] Turn it round    [Hold RMB] Cut it"
		if released and _cut_held > 0.0 and _cut_held < 0.3:
			var why := game.can_flip(link)
			if why != "":
				_say(why)
			else:
				Sfx.play(&"press")
				game.act(&"flip", [link.net_id])
				_say("Cable turned round")
		_cut_held = _cut_held + delta if down else 0.0
		if down:
			progress = maxf(_cut_held, 0.0) / CUT_TIME
		if _cut_held >= CUT_TIME:
			# Held on past the cut: letting go mustn't flip what's next.
			_cut_held = -100.0
			Sfx.play(&"cancel")
			game.act(&"unlink", [link.net_id])
			_say("Cable cut")
		return false
	_cut_held = 0.0
	if target and Fixture.CABLE_HEIGHT.has(target.kind):
		_cable_hint = "[RMB] Run a cable from it"
		if pressed:
			reel = target
			Sfx.play(&"latch")
	return false


## Whether the crosshair's on a screen within reach; if so it's _screen.
func _aim_screen() -> bool:
	if is_instance_valid(_screen):
		_screen.hover = &""
	_screen = null
	var from := camera.global_position
	var dir := -camera.global_basis.z
	var nearest := REACH
	var rock := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * REACH, Terrain.ROCK_LAYER))
	if !rock.is_empty():
		nearest = from.distance_to(rock.position)
	for screen in game.screens():
		var distance := screen.aim(from, dir)
		if distance < nearest:
			if _screen:
				_screen.hover = &""
			nearest = distance
			_screen = screen
		else:
			screen.hover = &""
	return _screen != null


func _hold(down: bool, delta: float, needed: float, done: Callable) -> void:
	_use_held = _use_held + delta if down else 0.0
	progress = _use_held / needed
	if _use_held >= needed:
		_use_held = 0.0
		_use_target = null
		done.call()


## Why you've not got a piece of gear.
func _unequipped(item: StringName) -> String:
	var gear_name := String(Game.UPGRADES[item].name).capitalize()
	if !game.has(item):
		return "No %s: it needs researching, then making at an armory" % gear_name.to_lower()
	return "No %s: the commander can have an armory make you one" % gear_name.to_lower()


## Takes up the gun or the hammer; the gun only once you've been given one.
func _switch(to: StringName, say := true) -> void:
	if to == &"gun" and !game.equipped(&"gun"):
		if say:
			_say(_unequipped(&"gun"))
		return
	weapon = to
	_gun.visible = weapon == &"gun"
	_hammer.visible = weapon == &"hammer"


## Everything in a short arc in front takes a big hit and goes flying;
## ore or a deposit under the head gives up a piece.
func _smash() -> void:
	_cooldown = HAMMER_EVERY
	_swing = 1.0
	Sfx.play(&"swing")
	var from := camera.global_position
	var ahead := -camera.global_basis.z
	for spider: Spider in game.spiders.duplicate():
		var to := spider.global_position + Terrain.up_at(spider.global_position) * 0.4 - from
		if to.length() < HAMMER_REACH and to.normalized().dot(ahead) > 0.55:
			Sfx.play(&"smash")
			game.act(&"hit", [spider.net_id, HAMMER_DAMAGE])
			game.act(&"fling", [spider.net_id, to.normalized() * HAMMER_KNOCK + up_direction * 2.5, HAMMER_STUN])
	var hit := _aim(HAMMER_REACH)
	var plan := _aim_cable(HAMMER_REACH + 1.0, true)
	if !plan.is_empty() and (hit.is_empty() or plan[2] < from.distance_to(hit.position)):
		var link: Link = plan[0]
		if link.from.blueprint or link.to.blueprint:
			_say("Build both ends first")
		else:
			game.act(&"string", [link.net_id])
			_say("Cable strung")
		return
	if hit.is_empty() or !(hit.collider is Fixture):
		return
	var fixture: Fixture = hit.collider
	if fixture.blueprint:
		if !game.can_pay(fixture):
			_say("Not enough in the pod")
			return
		game.act(&"construct", [fixture.net_id])
		_say("%s %d / %d" % [Fixture.NAMES[fixture.kind], mini(fixture.hits + 1, fixture.hits_needed()), fixture.hits_needed()])
	elif fixture.kind == &"deposit" or fixture.kind == &"ore":
		game.act(&"mine", [fixture.net_id])
		_say("+ore")
	elif fixture.health < fixture.max_health:
		game.act(&"repair", [fixture.net_id])
		_say("%s %d / %d" % ["Pod hull" if fixture.kind == &"pod" else Fixture.NAMES[fixture.kind], minf(fixture.max_health, fixture.health + Game.REPAIR), fixture.max_health])


func _throw_flare() -> void:
	if _flare_cooldown > 0.0:
		return
	if game.flares_left <= 0:
		_say("Out of flares: one comes back every %ds" % Game.FLARE_RECHARGE)
		return
	_flare_cooldown = FLARE_EVERY
	var ahead := -camera.global_basis.z
	game.act(&"flare", [camera.global_position + ahead * 0.6, (ahead + up_direction * 0.3).normalized()])


func _ping() -> void:
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * PING_RANGE, Terrain.ROCK_LAYER | Fixture.LAYER, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if !hit.is_empty():
		game.act(&"ping", [hit.position])


## Hooks what's under the crosshair. A spider gets yanked to you; anything
## else pulls you to it while the middle button's held.
func _throw_hook() -> void:
	if hooked or _hook_cooldown > 0.0:
		return
	if !game.equipped(&"grapple"):
		_say(_unequipped(&"grapple"))
		return
	var from := camera.global_position
	var to := from - camera.global_basis.z * GRAPPLE_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to, Terrain.ROCK_LAYER | Fixture.LAYER | Spider.LAYER, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	if hit.collider is Spider:
		_hook_cooldown = GRAPPLE_COOLDOWN
		var spider: Spider = hit.collider
		var home := (from - spider.global_position)
		game.act(&"fling", [spider.net_id, home.normalized() * minf(9.0, home.length()) + up_direction * 2.0, 0.6])
		_yank_from = spider.global_position
		_rope_flash = 0.2
		Sfx.play(&"grapple")
		return
	hooked = true
	Sfx.play(&"grapple")
	_hook_point = hit.position


func _reel(_delta: float, playing: bool) -> void:
	if !playing or !Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or global_position.distance_to(_hook_point) < 2.0:
		hooked = false
		_hook_cooldown = GRAPPLE_COOLDOWN


func _draw_rope(delta: float) -> void:
	_rope_flash = maxf(0.0, _rope_flash - delta)
	var end := _hook_point if hooked else _yank_from
	_rope.visible = hooked or _rope_flash > 0.0
	if !_rope.visible:
		return
	_stretch(_rope, camera.global_transform * Vector3(-0.25, -0.2, -0.4), end)


## A thin line to stretch between two points: the grapple's rope, or the
## cable you're paying out.
func _line(color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.015
	mesh.bottom_radius = 0.015
	mesh.height = 1.0
	mesh.radial_segments = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.material_override = material
	line.top_level = true
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.visible = false
	add_child(line)
	return line


func _stretch(line: MeshInstance3D, from: Vector3, end: Vector3) -> void:
	var length := from.distance_to(end)
	if length < 0.05:
		return
	var along := (end - from) / length
	var side := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
	line.global_transform = Transform3D(Basis(side, along * length, side.cross(along)), (from + end) * 0.5)


func _build_hammer() -> void:
	_hammer = Node3D.new()
	_hammer.position = Vector3(0.3, -0.42, -0.5)
	_hammer.scale = Vector3.ONE * 0.7
	_hammer.visible = false
	camera.add_child(_hammer)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.35, 0.36, 0.4)
	metal.metallic = 0.8
	metal.roughness = 0.35
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color(1.0, 0.45, 0.1)
	grip.roughness = 0.6
	var handle := CylinderMesh.new()
	handle.top_radius = 0.025
	handle.bottom_radius = 0.03
	handle.height = 0.6
	var shaft := MeshInstance3D.new()
	shaft.mesh = handle
	shaft.material_override = grip
	shaft.position = Vector3(0, 0.15, 0)
	shaft.rotation.x = -0.35
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hammer.add_child(shaft)
	var block := BoxMesh.new()
	block.size = Vector3(0.14, 0.14, 0.32)
	var head := MeshInstance3D.new()
	head.mesh = block
	head.material_override = metal
	head.position = Vector3(0, 0.43, -0.1)
	head.rotation.x = -0.35
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hammer.add_child(head)


func _say(text: String) -> void:
	notice = text
	notice_time = 2.5


## Hitscan: whatever the crosshair's on, out to range. Spiders take damage;
## anything else just stops the shot. The flash lights up the dark.
func _fire() -> void:
	_cooldown = FIRE_EVERY
	_recoil = 1.0
	Sfx.play(&"shot")
	var from := camera.global_position
	var angle := deg_to_rad(spread) * sqrt(randf())
	var around := randf() * TAU
	var dir := (camera.global_basis * Vector3(tan(angle) * cos(around), tan(angle) * sin(around), -1.0)).normalized()
	var to := from + dir * GUN_RANGE
	spread = minf(MAX_SPREAD, spread + lerpf(HIP_KICK, ADS_KICK, _ads) * (0.5 if game.has(&"stabiliser") else 1.0))
	var query := PhysicsRayQueryParameters3D.create(from, to, Terrain.ROCK_LAYER | Fixture.LAYER | Spider.LAYER, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if !hit.is_empty():
		to = hit.position
		if hit.collider is Spider:
			game.act(&"hit", [(hit.collider as Spider).net_id, DAMAGE * (2.0 if game.has(&"rounds") else 1.0)])
	_tracer(_muzzle.global_position, to)
	if Net.networked():
		game.act(&"shot", [_muzzle.global_position, to])


func _tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var along := (to - from) / length
	var side := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.7, 1.0, 1.0, 0.9)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.012
	mesh.bottom_radius = 0.012
	mesh.height = 1.0
	mesh.radial_segments = 4
	var tracer := MeshInstance3D.new()
	tracer.mesh = mesh
	tracer.material_override = material
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.add_child(tracer)
	tracer.global_transform = Transform3D(Basis(side, along * length, side.cross(along)), (from + to) * 0.5)
	var fade := tracer.create_tween()
	fade.tween_property(material, "albedo_color:a", 0.0, 0.08)
	fade.tween_callback(tracer.queue_free)


func _build_gun() -> void:
	_gun = Node3D.new()
	_gun.position = HIP_GUN
	_gun.scale = Vector3.ONE * 0.55
	camera.add_child(_gun)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.32, 0.33, 0.36)
	metal.metallic = 0.7
	metal.roughness = 0.35
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.5, 1.0, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.4, 1.0, 1.0)
	glow.emission_energy_multiplier = 3.0
	var body := BoxMesh.new()
	body.size = Vector3(0.08, 0.1, 0.42)
	_gun_part(body, metal, Vector3.ZERO, Vector3.ZERO)
	var grip := BoxMesh.new()
	grip.size = Vector3(0.06, 0.14, 0.07)
	_gun_part(grip, metal, Vector3(0, -0.1, 0.12), Vector3(-0.3, 0, 0))
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.022
	barrel.bottom_radius = 0.03
	barrel.height = 0.26
	_gun_part(barrel, metal, Vector3(0, 0.01, -0.33), Vector3(PI * 0.5, 0, 0))
	var strip := BoxMesh.new()
	strip.size = Vector3(0.02, 0.015, 0.3)
	_gun_part(strip, glow, Vector3(0, 0.055, -0.02), Vector3.ZERO)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.01, -0.47)
	_gun.add_child(_muzzle)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(0.6, 0.95, 1.0)
	_muzzle_light.omni_range = 9.0
	_muzzle_light.light_energy = 0.0
	_muzzle.add_child(_muzzle_light)


func _gun_part(mesh: Mesh, material: Material, pos: Vector3, rotation_angles: Vector3) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	part.rotation = rotation_angles
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gun.add_child(part)
