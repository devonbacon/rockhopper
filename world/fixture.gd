class_name Fixture
extends StaticBody3D
## Anything standing on the rock: the drop pod, ore, deposits, and what you
## build. Rigs stand along their deposit's slope; buildings stand upright,
## on a plinth sunk into the rock where it slopes.
##
## Ore is a small cluster, gone once mined. A deposit is a big outcrop
## holding a few dozen: you can chip at it by hand, or build a drill rig
## over it. A rig drills while it's lit, by the sun or a lamp, into a
## hopper that cables carry away, or you can empty by hand.
##
## A vent breathes steam, warm and glowing, day and night. A geothermal
## tap built over one makes power, while it's cabled back to the pod.
##
## Everything built carries a small light that comes on in the dark,
## while there's power: it keeps you warm close by.
##
## What the commander places starts as a blueprint: a hologram that does
## nothing till soldiers hammer it up, each blow paying its share of the
## cost from the bank.
##
## A foundry smelts ore into alloy while it has power. Pylons, rigs,
## foundries and the pod can be strung together with cables (Link) that
## carry ore and alloy along. Rigs, foundries, labs and lamps can be
## switched off; working rigs, foundries and labs make noise that draws
## spiders.
##
## A turret shoots the nearest spider it can see in the light, using ore
## fed to it by cable (or loaded by hand) as ammunition, and power for
## each shot; it's loud while it fires. A barricade is a wall spiders
## can't get past, only chew through.

const LAYER := 2
## Barricades are on this too, which spiders collide with.
const BARRIER_LAYER := 32
const COST := {&"lamp": 1, &"panel": 2, &"battery": 2, &"drill": 3, &"lab": 4, &"pylon": 1, &"foundry": 5, &"turret": 4, &"barricade": 1, &"armory": 4, &"tap": 5}
const ALLOY := {&"battery": 1, &"turret": 2}
const HEALTH := 30.0
const DRILL_EVERY := 6.0
const HOPPER := 12
const LAMP_RANGE := 13.0
## A building's own light: how far it shows, and how near it keeps you
## warm.
const GLOW_RANGE := 10.0
const GLOW_WARM := 7.0
const VENT_WARM := 6.0
## Foundries: SMELT_ORE ore makes one alloy every SMELT_EVERY seconds,
## with room for BIN of each.
const SMELT_EVERY := 6.0
const SMELT_ORE := 2
const BIN := 10
const PYLON_HOLDS := 4
## Turrets: shots a piece of ore makes, and the most it holds.
const ROUNDS_PER_ORE := 10
const MAGAZINE := 40
const TURRET_RANGE := 22.0
const TURRET_EVERY := 0.9
const TURRET_DAMAGE := 10.0
## Battery spent per shot.
const TURRET_SHOT := 0.3
## How long a turret stays loud after it last fired.
const LOUD_FOR := 2.0
## Hammer blows to put up a blueprint.
const BUILD_HITS := {&"lamp": 2, &"panel": 3, &"battery": 3, &"drill": 5, &"lab": 6, &"pylon": 2, &"foundry": 6, &"turret": 6, &"barricade": 5, &"armory": 6, &"tap": 6}
const NAMES := {&"lamp": "Lamp", &"panel": "Solar panel", &"battery": "Battery", &"drill": "Drill rig", &"lab": "Research lab", &"pylon": "Pylon", &"foundry": "Foundry", &"turret": "Turret", &"barricade": "Barricade", &"armory": "Armory", &"tap": "Geothermal tap"}
## How high a placement ghost sits over the ground.
const GHOST_LIFT := {&"lamp": 0.8, &"panel": 0.3, &"battery": 0.35, &"drill": 1.9, &"lab": 0.85, &"pylon": 2.2, &"foundry": 1.1, &"turret": 1.6, &"barricade": 1.0, &"armory": 0.9, &"tap": 1.3}
## Steepest ground each can go on, in degrees; the bigger ones sit level
## on a plinth.
const MAX_SLOPE := {&"lamp": 35.0, &"pylon": 35.0}
const SLOPE := 20.0
## How much further than they'd see that spiders hear it working.
const NOISE := {&"pod": 5.0, &"drill": 20.0, &"foundry": 30.0, &"lab": 8.0, &"turret": 25.0, &"armory": 12.0, &"tap": 14.0}
## Off, a building's idle and dark.
const SWITCHED: Array[StringName] = [&"lamp", &"panel", &"battery", &"drill", &"lab", &"pylon", &"foundry", &"turret", &"barricade", &"armory", &"tap"]
## Where cables tie on, above the base.
const CABLE_HEIGHT := {&"pod": 3.7, &"drill": 3.8, &"foundry": 3.4, &"pylon": 4.4, &"tap": 3.0}
## What only sends along a cable, never takes.
const SENDERS: Array[StringName] = [&"drill", &"tap"]

var kind: StringName
var net_id := 0
var normal := Vector3.UP
## Kept up to date by the game: whether the sun reaches it, and for lamps,
## whether they're lit.
var sunlit := false
var on := false
## Ore: how much it gives; a deposit: how much it has left; a vent: the
## power a tap on it makes.
var amount := 3
var full_amount := 0
var power := 0.0
## Lamps, panels and rigs: spiders wear this down.
var health := HEALTH
var max_health := HEALTH
## A deposit's rig, and a rig's deposit; or a vent's tap, and a tap's
## vent.
var rig: Fixture
var deposit: Fixture
## Rigs: ore in the hopper, progress towards the next, and why it isn't
## drilling: "" if it is, "dark" or "full".
var stored := 0
var drilled := 0.0
var stalled := ""
var charge := 0.0
var researching: StringName = &""
var research_time := 0.0
## Armories: who what's being made is for.
var made_for := 0
var unpowered := false
var blueprint := false
var hits := 0
## Switched on by the commander.
var enabled := true
## Foundries: ore waiting, alloy made, progress towards the next; pylons:
## what's passing through.
var ore_in := 0
var alloy_out := 0
var smelted := 0.0
var holding: Array[StringName] = []
## Turrets: shots left, which way the gun's turned, and the time since it
## last fired and till it can again.
var ammo := 0
var aim := 0.0
var since_shot := 99.0
var cooldown := 0.0
var _gun: Node3D

var light: OmniLight3D
## The pod's screen.
var screen: Screen
var _bulb: StandardMaterial3D
var _beacon: OmniLight3D
var _beacon_bulb: StandardMaterial3D
var _shaft: Node3D
var _status: StandardMaterial3D
var _fill: MeshInstance3D
var _holo: StandardMaterial3D
var _shards: Array[Node3D] = []


static func make(fixture_kind: StringName, pos: Vector3, surface_normal: Vector3) -> Fixture:
	var fixture := Fixture.new()
	fixture.kind = fixture_kind
	fixture.normal = surface_normal
	fixture.transform = Transform3D(upright(surface_normal), pos)
	return fixture


## A rough shape of kind, for placement ghosts.
static func ghost_mesh(ghost_kind: StringName) -> Mesh:
	match ghost_kind:
		&"lamp":
			var post := CylinderMesh.new()
			post.top_radius = 0.12
			post.bottom_radius = 0.2
			post.height = 1.6
			return post
		&"panel":
			var panel := BoxMesh.new()
			panel.size = Vector3(1.6, 0.6, 1.0)
			return panel
		&"battery":
			var cell := BoxMesh.new()
			cell.size = Vector3(1.0, 0.7, 0.7)
			return cell
		&"drill":
			var rig := CylinderMesh.new()
			rig.top_radius = 0.6
			rig.bottom_radius = 2.4
			rig.height = 3.8
			return rig
		&"pylon":
			var mast := CylinderMesh.new()
			mast.top_radius = 0.15
			mast.bottom_radius = 0.3
			mast.height = 4.4
			return mast
		&"foundry":
			var hall := BoxMesh.new()
			hall.size = Vector3(2.6, 2.2, 2.2)
			return hall
		&"turret":
			var mount := CylinderMesh.new()
			mount.top_radius = 0.4
			mount.bottom_radius = 0.6
			mount.height = 3.2
			return mount
		&"armory":
			var shed := BoxMesh.new()
			shed.size = Vector3(2.4, 1.8, 1.6)
			return shed
		&"barricade":
			var wall := BoxMesh.new()
			wall.size = Vector3(3.0, 2.0, 0.5)
			return wall
	var lab := BoxMesh.new()
	lab.size = Vector3(2.2, 1.7, 1.6)
	return lab


## A basis whose y is up, turned about it arbitrarily.
static func upright(up: Vector3) -> Basis:
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	return Basis(x, up, x.cross(up))


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	match kind:
		&"pod": _build_pod()
		&"lamp": _build_lamp()
		&"panel": _build_panel()
		&"ore": _build_ore()
		&"deposit": _build_deposit()
		&"drill": _build_drill()
		&"battery": _build_battery()
		&"lab": _build_lab()
		&"armory": _build_armory()
		&"pylon": _build_pylon()
		&"foundry": _build_foundry()
		&"turret": _build_turret()
		&"barricade": _build_barricade()
		&"vent": _build_vent()
		&"tap": _build_tap()
	if !blueprint and COST.has(kind) and kind != &"lamp":
		_add_glow()
	if kind == &"pod":
		_add_glow()
	if kind == &"barricade" and !blueprint:
		collision_layer |= BARRIER_LAYER
	if blueprint:
		_hologram()
	max_health = health


## How much further than they'd see that spiders hear it, while it works.
func noise() -> float:
	match kind:
		&"pod": return NOISE.pod
		&"drill", &"foundry": return NOISE[kind] if enabled and stalled == "" else 0.0
		&"lab", &"armory": return NOISE[kind] if enabled and researching != &"" and !unpowered else 0.0
		&"turret": return NOISE.turret if since_shot < LOUD_FOR else 0.0
		&"tap": return NOISE.tap if enabled and stalled == "" else 0.0
	return 0.0


## Turrets: where shots come from.
func muzzle() -> Vector3:
	return global_position + normal * 1.75


func cable_point() -> Vector3:
	return global_position + normal * CABLE_HEIGHT.get(kind, 2.0)


## What it'd send down a cable next, or &"" for nothing.
func output() -> StringName:
	match kind:
		&"drill": return &"ore" if stored > 0 else &""
		&"foundry": return &"alloy" if alloy_out > 0 else &""
		&"pylon": return holding[0] if !holding.is_empty() else &""
	return &""


func take_output() -> void:
	match kind:
		&"drill": stored -= 1
		&"foundry": alloy_out -= 1
		&"pylon": holding.pop_front()


## Whether it'll take this off a cable.
func accepts(item: StringName) -> bool:
	match kind:
		&"foundry": return item == &"ore" and ore_in < BIN
		&"pylon": return holding.size() < PYLON_HOLDS
		&"pod": return true
	return false


## Foundries: smelts for delta seconds, given whether there's power. A
## batch of ore goes in at the start.
func smelt(delta: float, powered: bool) -> void:
	unpowered = !powered
	if !enabled:
		stalled = "off"
	elif smelted == 0.0 and ore_in < SMELT_ORE:
		stalled = "no ore"
	elif alloy_out >= BIN:
		stalled = "full"
	elif !powered:
		stalled = "no power"
	else:
		stalled = ""
	if stalled != "":
		return
	if smelted == 0.0:
		ore_in -= SMELT_ORE
	smelted += delta
	if smelted >= SMELT_EVERY:
		smelted = 0.0
		alloy_out += 1


func set_on(value: bool) -> void:
	on = value
	light.visible = on
	if _bulb:
		_bulb.emission_energy_multiplier = 6.0 if on else 0.0


## Deposits: shows what's left, a shard gone for each part dug out.
func show_left() -> void:
	var showing := ceili(_shards.size() * amount / float(maxi(1, full_amount)))
	for i in _shards.size():
		_shards[i].visible = i < showing


## A small light up top, for the dark.
func _add_glow() -> void:
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.65)
	light.omni_range = GLOW_RANGE
	light.light_energy = 1.8
	light.position = Vector3.UP * (4.6 if kind == &"pod" else (CABLE_HEIGHT.get(kind, 2.0) + 0.4))
	add_child(light)
	_bulb = _material(Color(1.0, 0.85, 0.6), 0.0, 0.3)
	_bulb.emission_enabled = true
	_bulb.emission = Color(1.0, 0.75, 0.45)
	var bulb := SphereMesh.new()
	bulb.radius = 0.09
	bulb.height = 0.18
	_add_mesh(bulb, _bulb, light.position - Vector3.UP * 0.15).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_on(false)


## Rigs: drills for delta seconds if it's lit and has room, given whether
## it's lit.
func drill(delta: float, lit: bool, every: float = DRILL_EVERY) -> void:
	stalled = "off" if !enabled else ("spent" if deposit and deposit.amount <= 0 else ("full" if stored >= HOPPER else ("dark" if !lit else "")))
	if stalled != "":
		return
	drilled += delta
	if drilled >= every:
		drilled -= every
		stored += 1
		if deposit:
			deposit.amount -= 1
			deposit.show_left()


## Rigs: empties up to amount from the hopper, returning what it gave.
func take(amount: int) -> int:
	var given := mini(amount, stored)
	stored -= given
	return given


func hits_needed() -> int:
	return BUILD_HITS[kind]


## Ore (or alloy) paid into a blueprint after this many blows, rounded up
## so the first blows pay first.
func paid_after(blows: int, alloy := false) -> int:
	return ceili((ALLOY.get(kind, 0) if alloy else COST[kind]) * blows / float(hits_needed()))


func paid(alloy := false) -> int:
	return paid_after(hits, alloy)


func blow_cost(alloy := false) -> int:
	return paid_after(hits + 1, alloy) - paid(alloy)


## Every part see-through and glowing, nothing lit or working.
func _hologram() -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.35, 0.75, 1.0, 0.28)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	_holo = material
	_hologram_under(self)
	if light:
		light.visible = false
	if screen:
		screen.visible = false
	_shaft = null
	_fill = null


func _hologram_under(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = _holo
			(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif child is Light3D:
			(child as Light3D).visible = false
		if !(child is Screen):
			_hologram_under(child)


func _process(delta: float) -> void:
	if blueprint:
		var done := hits / float(hits_needed())
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 300.0)
		_holo.albedo_color = Color(0.35, 0.75, 1.0, 0.18 + 0.3 * done + 0.08 * pulse)
		return
	if kind == &"battery":
		_fill.scale.y = maxf(0.02, charge)
		_fill.position.y = 0.12 + 0.24 * _fill.scale.y
	if _gun:
		var turn := Basis(Vector3.UP, aim)
		_gun.basis = _gun.basis.slerp(turn, minf(1.0, delta * 12.0))
		_fill.scale.y = maxf(0.02, ammo / float(MAGAZINE))
		_fill.position.y = 0.3 + 0.3 * _fill.scale.y
		return
	if kind == &"foundry":
		var working := stalled == ""
		_status.emission = Color(1.0, 0.45, 0.1) if working else Color(0.2, 0.2, 0.25)
		_status.emission_energy_multiplier = 3.0 + sin(Time.get_ticks_msec() / 120.0) if working else 0.3
		_fill.scale.y = maxf(0.02, alloy_out / float(BIN))
		_fill.position.y = 0.45 + 0.4 * _fill.scale.y
		return
	if _shaft:
		if stalled == "":
			_shaft.rotate_object_local(Vector3.UP, delta * 9.0)
		var color := Color(0.3, 1.0, 0.4) if stalled == "" else (Color(0.4, 0.7, 1.0) if stalled == "dark" else (Color(0.3, 0.3, 0.3) if stalled == "off" else Color(1.0, 0.7, 0.2)))
		_status.albedo_color = color
		_status.emission = color
		_fill.scale.y = maxf(0.02, stored / float(HOPPER))
		_fill.position.y = 3.05 + 0.28 * _fill.scale.y
	if _beacon:
		var blink := fmod(Time.get_ticks_msec() / 1000.0, 1.6) < 0.25
		_beacon.visible = blink
		_beacon_bulb.emission_energy_multiplier = 8.0 if blink else 0.3


func _build_pod() -> void:
	health = 500.0
	var hull := _material(Color(0.78, 0.76, 0.72), 0.45, 0.5)
	_add_mesh(_cylinder(1.25, 1.65, 3.0), hull, Vector3(0, 1.3, 0))
	_add_mesh(_cylinder(0.35, 1.25, 1.2), hull, Vector3(0, 3.4, 0))
	var stripe := _material(Color(1.0, 0.55, 0.15), 0.2, 0.4)
	stripe.emission_enabled = true
	stripe.emission = Color(1.0, 0.5, 0.1)
	stripe.emission_energy_multiplier = 1.5
	var torus := TorusMesh.new()
	torus.inner_radius = 1.5
	torus.outer_radius = 1.62
	_add_mesh(torus, stripe, Vector3(0, 1.0, 0))
	var cells := _material(Color(0.08, 0.12, 0.3), 0.6, 0.2)
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 1.6, 1.0)
	_add_mesh(box, cells, Vector3(-1.55, 2.0, 0)).rotation.z = -0.12
	# The screen faces out of the +x side, leaning back with the hull.
	var lean := atan2(0.4, 3.0)
	var out := Vector3(cos(lean), sin(lean), 0.0)
	var up := Vector3(-sin(lean), cos(lean), 0.0)
	var screen_basis := Basis(up.cross(out), up, out)
	var frame := BoxMesh.new()
	screen = Screen.new()
	screen.title = "PROSPECTOR POD  //  FAB-2"
	screen.buttons = [&"hand_in", &"command"]
	frame.size = Vector3(screen.size_m.x + 0.12, screen.size_m.y + 0.12, 0.06)
	_add_mesh(frame, _material(Color(0.2, 0.21, 0.24), 0.6, 0.4), Vector3(1.34, 2.1, 0)).basis = screen_basis
	screen.transform = Transform3D(screen_basis, Vector3(1.34, 2.1, 0) + out * 0.035)
	add_child(screen)
	for i in 3:
		var leg := BoxMesh.new()
		leg.size = Vector3(0.15, 1.6, 0.15)
		var angle := TAU * i / 3.0
		var foot := _add_mesh(leg, hull, Vector3(cos(angle) * 1.7, 0.3, sin(angle) * 1.7))
		foot.rotation = Vector3(sin(angle) * 0.5, 0, -cos(angle) * 0.5)
	_beacon_bulb = _material(Color(1.0, 0.2, 0.15), 0.3, 0.3)
	_beacon_bulb.emission_enabled = true
	_beacon_bulb.emission = Color(1.0, 0.15, 0.1)
	var bulb := SphereMesh.new()
	bulb.radius = 0.16
	bulb.height = 0.32
	_add_mesh(bulb, _beacon_bulb, Vector3(0, 4.1, 0))
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color(1.0, 0.2, 0.1)
	_beacon.omni_range = 9.0
	_beacon.light_energy = 1.5
	_beacon.position = Vector3(0, 4.3, 0)
	add_child(_beacon)
	var shape := CylinderShape3D.new()
	shape.radius = 1.6
	shape.height = 4.0
	_add_collider(shape, Vector3(0, 1.9, 0))


func _build_lamp() -> void:
	var metal := _material(Color(0.5, 0.5, 0.52), 0.7, 0.4)
	var base := BoxMesh.new()
	base.size = Vector3(0.45, 0.12, 0.45)
	_add_mesh(base, metal, Vector3(0, 0.06, 0))
	# The post and bulb sit right under the light: they'd shadow everything
	# round the lamp.
	_add_mesh(_cylinder(0.04, 0.05, 1.4), metal, Vector3(0, 0.75, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bulb = _material(Color(1.0, 0.85, 0.6), 0.0, 0.3)
	_bulb.emission_enabled = true
	_bulb.emission = Color(1.0, 0.75, 0.45)
	var bulb := SphereMesh.new()
	bulb.radius = 0.14
	bulb.height = 0.28
	_add_mesh(bulb, _bulb, Vector3(0, 1.5, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.78, 0.5)
	light.omni_range = LAMP_RANGE
	light.light_energy = 2.2
	light.shadow_enabled = true
	light.position = Vector3(0, 1.75, 0)
	add_child(light)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.45, 1.6, 0.45)
	_add_collider(shape, Vector3(0, 0.8, 0))
	set_on(false)


func _build_panel() -> void:
	_plinth(Vector2(0.5, 0.5))
	var metal := _material(Color(0.5, 0.5, 0.52), 0.7, 0.4)
	_add_mesh(_cylinder(0.04, 0.05, 0.6), metal, Vector3(0, 0.3, 0))
	var cells := _material(Color(0.06, 0.1, 0.32), 0.6, 0.18)
	var face := BoxMesh.new()
	face.size = Vector3(1.6, 0.05, 1.0)
	_add_mesh(face, cells, Vector3(0, 0.65, 0))
	var frame := BoxMesh.new()
	frame.size = Vector3(1.7, 0.03, 1.1)
	_add_mesh(frame, metal, Vector3(0, 0.62, 0))
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.7, 0.75, 1.1)
	_add_collider(shape, Vector3(0, 0.38, 0))


func _build_ore() -> void:
	var crystal := _material(Color(0.3, 0.85, 0.92), 0.25, 0.12)
	crystal.emission_enabled = true
	crystal.emission = Color(0.2, 0.75, 0.9)
	crystal.emission_energy_multiplier = 0.12
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(position)
	for i in 5:
		var height := rng.randf_range(0.6, 1.4)
		var mesh := _cylinder(0.0, rng.randf_range(0.14, 0.28), height)
		mesh.radial_segments = 5
		var offset := Vector3(rng.randf_range(-0.35, 0.35), height * 0.4, rng.randf_range(-0.35, 0.35))
		var shard := _add_mesh(mesh, crystal, offset)
		shard.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0, TAU), rng.randf_range(-0.5, 0.5))
	var shape := SphereShape3D.new()
	shape.radius = 0.75
	_add_collider(shape, Vector3(0, 0.45, 0))


func _build_deposit() -> void:
	var crystal := _material(Color(0.3, 0.85, 0.92), 0.25, 0.12)
	crystal.emission_enabled = true
	crystal.emission = Color(0.2, 0.75, 0.9)
	crystal.emission_energy_multiplier = 0.15
	var rock := _material(Color(0.32, 0.3, 0.28), 0.0, 0.95)
	var base := SphereMesh.new()
	base.radius = 1.7
	base.height = 1.6
	_add_mesh(base, rock, Vector3(0, 0.1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(position)
	for i in 9:
		var height := rng.randf_range(1.4, 3.2)
		var mesh := _cylinder(0.0, rng.randf_range(0.3, 0.6), height)
		mesh.radial_segments = 6
		var angle := TAU * i / 9.0 + rng.randf_range(-0.3, 0.3)
		var out := rng.randf_range(0.2, 1.1)
		var shard := _add_mesh(mesh, crystal, Vector3(cos(angle) * out, height * 0.4 + 0.3, sin(angle) * out))
		shard.rotation = Vector3(sin(angle) * out * 0.5, rng.randf_range(0, TAU), -cos(angle) * out * 0.5)
		_shards.append(shard)
	var shape := SphereShape3D.new()
	shape.radius = 1.6
	_add_collider(shape, Vector3(0, 0.9, 0))


## A tripod over the deposit, a spinning drill down its middle, and a
## hopper up top with a gauge, in white, gold foil and orange.
func _build_drill() -> void:
	health = 40.0
	var white := _material(Color(0.88, 0.88, 0.86), 0.3, 0.45)
	var gold := _material(Color(0.85, 0.62, 0.22), 0.9, 0.3)
	var orange := _material(Color(1.0, 0.45, 0.1), 0.1, 0.5)
	for i in 3:
		var angle := TAU * i / 3.0
		var foot := Vector3(cos(angle) * 2.4, 0.0, sin(angle) * 2.4)
		var top := Vector3(0, 3.2, 0)
		var leg := BoxMesh.new()
		leg.size = Vector3(0.14, foot.distance_to(top), 0.14)
		var along := (top - foot).normalized()
		var side := along.cross(Vector3.FORWARD if absf(along.z) < 0.9 else Vector3.RIGHT).normalized()
		var instance := _add_mesh(leg, white, (foot + top) * 0.5)
		instance.basis = Basis(side, along, side.cross(along))
		var pad := BoxMesh.new()
		pad.size = Vector3(0.45, 0.1, 0.45)
		_add_mesh(pad, orange, foot + Vector3(0, 0.05, 0))
	_shaft = Node3D.new()
	_shaft.position = Vector3(0, 1.6, 0)
	add_child(_shaft)
	var bit := _cylinder(0.12, 0.12, 2.6)
	var shaft_mesh := MeshInstance3D.new()
	shaft_mesh.mesh = bit
	shaft_mesh.material_override = _material(Color(0.4, 0.4, 0.42), 0.8, 0.3)
	_shaft.add_child(shaft_mesh)
	var flight := BoxMesh.new()
	flight.size = Vector3(0.5, 0.06, 0.08)
	for i in 4:
		var blade := MeshInstance3D.new()
		blade.mesh = flight
		blade.material_override = orange
		blade.position = Vector3(0, -0.9 + i * 0.5, 0)
		blade.rotation.y = i * 0.8
		_shaft.add_child(blade)
	var hopper := BoxMesh.new()
	hopper.size = Vector3(1.3, 0.75, 1.3)
	_add_mesh(hopper, gold, Vector3(0, 3.4, 0))
	var gauge := BoxMesh.new()
	gauge.size = Vector3(0.18, 0.56, 0.05)
	var gauge_back := _material(Color(0.05, 0.05, 0.06), 0.0, 0.8)
	_add_mesh(gauge, gauge_back, Vector3(0, 3.33, 0.67))
	var fill_material := _material(Color(0.3, 0.85, 0.92), 0.0, 0.3)
	fill_material.emission_enabled = true
	fill_material.emission = Color(0.2, 0.75, 0.9)
	fill_material.emission_energy_multiplier = 2.0
	var fill := BoxMesh.new()
	fill.size = Vector3(0.12, 0.56, 0.06)
	_fill = _add_mesh(fill, fill_material, Vector3(0, 3.05, 0.68))
	_status = _material(Color(0.3, 1.0, 0.4), 0.0, 0.3)
	_status.emission_enabled = true
	_status.emission_energy_multiplier = 4.0
	var bulb := SphereMesh.new()
	bulb.radius = 0.1
	bulb.height = 0.2
	_add_mesh(bulb, _status, Vector3(0, 3.9, 0))
	var shape := CylinderShape3D.new()
	shape.radius = 1.0
	shape.height = 4.0
	_add_collider(shape, Vector3(0, 2.0, 0))


func _build_lab() -> void:
	health = 50.0
	_plinth(Vector2(2.2, 1.6))
	var white := _material(Color(0.88, 0.88, 0.86), 0.3, 0.45)
	var gold := _material(Color(0.85, 0.62, 0.22), 0.9, 0.3)
	var orange := _material(Color(1.0, 0.45, 0.1), 0.1, 0.5)
	var dark := _material(Color(0.2, 0.21, 0.24), 0.6, 0.4)
	var body := BoxMesh.new()
	body.size = Vector3(2.2, 1.7, 1.6)
	_add_mesh(body, white, Vector3(0, 0.85, 0))
	var roof := BoxMesh.new()
	roof.size = Vector3(2.3, 0.12, 1.7)
	_add_mesh(roof, gold, Vector3(0, 1.76, 0))
	var stripe := BoxMesh.new()
	stripe.size = Vector3(2.22, 0.1, 1.62)
	_add_mesh(stripe, orange, Vector3(0, 0.3, 0))
	_add_mesh(_cylinder(0.04, 0.04, 0.8), white, Vector3(0.7, 2.2, -0.4))
	var dish := _cylinder(0.45, 0.08, 0.18)
	_add_mesh(dish, white, Vector3(0.7, 2.65, -0.4)).rotation = Vector3(0.5, 0, 0.3)
	var window := BoxMesh.new()
	window.size = Vector3(1.6, 0.6, 0.04)
	_add_mesh(window, dark, Vector3(0, 1.1, 0.81))
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.2, 1.8, 1.6)
	_add_collider(shape, Vector3(0, 0.9, 0))


func _build_armory() -> void:
	health = 50.0
	_plinth(Vector2(2.4, 1.6))
	var grey := _material(Color(0.42, 0.44, 0.46), 0.6, 0.45)
	var orange := _material(Color(1.0, 0.45, 0.1), 0.1, 0.5)
	var dark := _material(Color(0.16, 0.17, 0.19), 0.6, 0.4)
	var white := _material(Color(0.88, 0.88, 0.86), 0.3, 0.45)
	var body := BoxMesh.new()
	body.size = Vector3(2.4, 1.8, 1.6)
	_add_mesh(body, grey, Vector3(0, 0.9, 0))
	var roof := BoxMesh.new()
	roof.size = Vector3(2.5, 0.14, 1.7)
	_add_mesh(roof, orange, Vector3(0, 1.85, 0))
	# An open rack on the front, with suits hung in it.
	var bay := BoxMesh.new()
	bay.size = Vector3(1.9, 1.3, 0.05)
	_add_mesh(bay, dark, Vector3(0, 0.95, 0.81))
	for i in 3:
		var suit := BoxMesh.new()
		suit.size = Vector3(0.38, 0.9, 0.2)
		_add_mesh(suit, white, Vector3(-0.6 + i * 0.6, 0.95, 0.86))
		var visor := BoxMesh.new()
		visor.size = Vector3(0.24, 0.1, 0.04)
		_add_mesh(visor, orange, Vector3(-0.6 + i * 0.6, 1.25, 0.97))
	var stripe := BoxMesh.new()
	stripe.size = Vector3(2.42, 0.1, 1.62)
	_add_mesh(stripe, orange, Vector3(0, 0.25, 0))
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 1.9, 1.6)
	_add_collider(shape, Vector3(0, 0.95, 0))
	# Ammo boxes stacked on the left side.
	var olive := _material(Color(0.32, 0.36, 0.2), 0.3, 0.6)
	for i in 3:
		var crate := BoxMesh.new()
		crate.size = Vector3(0.45, 0.32, 0.6)
		_add_mesh(crate, olive, Vector3(-1.45, 0.16 + i * 0.33, -0.3 + (i % 2) * 0.4))
	if blueprint:
		return
	# Soldiers order their own gear, and grab ammo, at the screen on the
	# right side.
	var out := Vector3.RIGHT
	var screen_basis := Basis(Vector3.UP.cross(out), Vector3.UP, out)
	screen = Screen.new()
	screen.title = "ARMORY  //  FAB-7"
	screen.size_m = Vector2(1.3, 1.1)
	screen.pixels = Vector2i(640, 540)
	screen.button_height = 34.0
	screen.button_font = 20
	screen.buttons.assign(Game.GEAR.keys() + [&"ammo", &"flares"])
	var frame := BoxMesh.new()
	frame.size = Vector3(screen.size_m.x + 0.1, screen.size_m.y + 0.1, 0.05)
	_add_mesh(frame, dark, Vector3(1.22, 1.0, 0)).basis = screen_basis
	screen.transform = Transform3D(screen_basis, Vector3(1.22, 1.0, 0) + out * 0.03)
	add_child(screen)


func _build_battery() -> void:
	_plinth(Vector2(1.0, 0.7))
	var white := _material(Color(0.88, 0.88, 0.86), 0.3, 0.45)
	var gold := _material(Color(0.85, 0.62, 0.22), 0.9, 0.3)
	var dark := _material(Color(0.12, 0.12, 0.14), 0.4, 0.6)
	var body := BoxMesh.new()
	body.size = Vector3(1.0, 0.6, 0.7)
	_add_mesh(body, white, Vector3(0, 0.3, 0))
	var band := BoxMesh.new()
	band.size = Vector3(1.02, 0.14, 0.72)
	_add_mesh(band, gold, Vector3(0, 0.42, 0))
	for x in [-0.28, 0.28]:
		_add_mesh(_cylinder(0.06, 0.08, 0.12), dark, Vector3(x, 0.66, 0))
	var gauge := BoxMesh.new()
	gauge.size = Vector3(0.6, 0.5, 0.02)
	_add_mesh(gauge, dark, Vector3(0, 0.36, 0.36))
	var fill_material := _material(Color(0.5, 1.0, 0.45), 0.0, 0.3)
	fill_material.emission_enabled = true
	fill_material.emission = Color(0.4, 1.0, 0.35)
	fill_material.emission_energy_multiplier = 2.0
	var fill := BoxMesh.new()
	fill.size = Vector3(0.5, 0.48, 0.02)
	_fill = _add_mesh(fill, fill_material, Vector3(0, 0.36, 0.37))
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 0.7, 0.7)
	_add_collider(shape, Vector3(0, 0.35, 0))


## A white mast with a gold cross-arm, where cables tie on.
func _build_pylon() -> void:
	var white := _material(Color(0.88, 0.88, 0.86), 0.3, 0.45)
	var gold := _material(Color(0.85, 0.62, 0.22), 0.9, 0.3)
	var orange := _material(Color(1.0, 0.45, 0.1), 0.1, 0.5)
	var foot := BoxMesh.new()
	foot.size = Vector3(0.7, 0.2, 0.7)
	_add_mesh(foot, orange, Vector3(0, 0.1, 0))
	_add_mesh(_cylinder(0.08, 0.13, 4.3), white, Vector3(0, 2.25, 0))
	var arm := BoxMesh.new()
	arm.size = Vector3(1.1, 0.12, 0.12)
	_add_mesh(arm, gold, Vector3(0, 4.3, 0))
	_add_mesh(_cylinder(0.14, 0.14, 0.1), orange, Vector3(0, 4.45, 0)).rotation.x = PI * 0.5
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 4.4, 0.4)
	_add_collider(shape, Vector3(0, 2.2, 0))


## A squat furnace hall with a stack, a glowing mouth, an alloy gauge, and
## a mast on top for cables.
func _build_foundry() -> void:
	health = 60.0
	_plinth(Vector2(2.6, 2.2))
	var white := _material(Color(0.88, 0.88, 0.86), 0.3, 0.45)
	var gold := _material(Color(0.85, 0.62, 0.22), 0.9, 0.3)
	var dark := _material(Color(0.2, 0.21, 0.24), 0.6, 0.4)
	var body := BoxMesh.new()
	body.size = Vector3(2.6, 1.8, 2.2)
	_add_mesh(body, white, Vector3(0, 0.9, 0))
	var roof := BoxMesh.new()
	roof.size = Vector3(2.7, 0.14, 2.3)
	_add_mesh(roof, gold, Vector3(0, 1.85, 0))
	_add_mesh(_cylinder(0.25, 0.32, 1.6), dark, Vector3(-0.8, 2.6, -0.5))
	_add_mesh(_cylinder(0.06, 0.08, 1.6), white, Vector3(0, 2.6, 0))
	_status = _material(Color(0.3, 0.1, 0.05), 0.0, 0.5)
	_status.emission_enabled = true
	var mouth := BoxMesh.new()
	mouth.size = Vector3(0.9, 0.6, 0.05)
	_add_mesh(mouth, _status, Vector3(0, 0.6, 1.11))
	var gauge := BoxMesh.new()
	gauge.size = Vector3(0.2, 0.84, 0.05)
	_add_mesh(gauge, _material(Color(0.05, 0.05, 0.06), 0.0, 0.8), Vector3(0.95, 0.87, 1.11))
	var fill_material := _material(Color(1.0, 0.6, 0.2), 0.0, 0.3)
	fill_material.emission_enabled = true
	fill_material.emission = Color(1.0, 0.55, 0.15)
	fill_material.emission_energy_multiplier = 2.0
	var fill := BoxMesh.new()
	fill.size = Vector3(0.14, 0.8, 0.06)
	_fill = _add_mesh(fill, fill_material, Vector3(0.95, 0.45, 1.12))
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.6, 1.9, 2.2)
	_add_collider(shape, Vector3(0, 0.95, 0))


## An ammo box on a plinth, a gun on a swivel above it, and a mast behind
## for the cable.
func _build_turret() -> void:
	health = 60.0
	_plinth(Vector2(1.2, 1.2))
	var white := _material(Color(0.88, 0.88, 0.86), 0.3, 0.45)
	var gold := _material(Color(0.85, 0.62, 0.22), 0.9, 0.3)
	var dark := _material(Color(0.2, 0.21, 0.24), 0.6, 0.4)
	var orange := _material(Color(1.0, 0.45, 0.1), 0.1, 0.5)
	var box := BoxMesh.new()
	box.size = Vector3(1.1, 0.9, 1.1)
	_add_mesh(box, white, Vector3(0, 0.45, 0))
	var band := BoxMesh.new()
	band.size = Vector3(1.12, 0.12, 1.12)
	_add_mesh(band, orange, Vector3(0, 0.75, 0))
	_add_mesh(_cylinder(0.12, 0.16, 0.6), dark, Vector3(0, 1.2, 0))
	_add_mesh(_cylinder(0.05, 0.07, 2.6), white, Vector3(-0.45, 2.1, -0.45))
	_gun = Node3D.new()
	_gun.position = Vector3(0, 1.6, 0)
	add_child(_gun)
	var housing := BoxMesh.new()
	housing.size = Vector3(0.6, 0.4, 0.8)
	var body := MeshInstance3D.new()
	body.mesh = housing
	body.material_override = gold
	_gun.add_child(body)
	var barrel := MeshInstance3D.new()
	barrel.mesh = _cylinder(0.06, 0.08, 1.0)
	barrel.material_override = dark
	barrel.rotation.x = PI * 0.5
	barrel.position = Vector3(0, 0.05, -0.8)
	_gun.add_child(barrel)
	var gauge := BoxMesh.new()
	gauge.size = Vector3(0.2, 0.62, 0.05)
	_add_mesh(gauge, _material(Color(0.05, 0.05, 0.06), 0.0, 0.8), Vector3(0, 0.45, 0.56))
	var fill_material := _material(Color(0.3, 0.85, 0.92), 0.0, 0.3)
	fill_material.emission_enabled = true
	fill_material.emission = Color(0.2, 0.75, 0.9)
	fill_material.emission_energy_multiplier = 2.0
	var fill := BoxMesh.new()
	fill.size = Vector3(0.14, 0.6, 0.06)
	_fill = _add_mesh(fill, fill_material, Vector3(0, 0.3, 0.57))
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.1, 1.9, 1.1)
	_add_collider(shape, Vector3(0, 0.95, 0))


## A wall of white panels between two posts, striped orange.
func _build_barricade() -> void:
	health = 120.0
	_plinth(Vector2(3.0, 0.5))
	var white := _material(Color(0.88, 0.88, 0.86), 0.3, 0.45)
	var orange := _material(Color(1.0, 0.45, 0.1), 0.1, 0.5)
	var dark := _material(Color(0.2, 0.21, 0.24), 0.6, 0.4)
	var panel := BoxMesh.new()
	panel.size = Vector3(2.8, 1.8, 0.3)
	_add_mesh(panel, white, Vector3(0, 0.95, 0))
	for y in [0.5, 1.4]:
		var stripe := BoxMesh.new()
		stripe.size = Vector3(2.82, 0.16, 0.32)
		_add_mesh(stripe, orange, Vector3(0, y, 0))
	for x in [-1.45, 1.45]:
		var post := BoxMesh.new()
		post.size = Vector3(0.2, 2.1, 0.45)
		_add_mesh(post, dark, Vector3(x, 1.05, 0))
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.1, 2.1, 0.5)
	_add_collider(shape, Vector3(0, 1.05, 0))


## A block of concrete under it, down into the rock, so it sits level on
## a slope.
## A ring of dark rock round a glowing pit, breathing steam.
func _build_vent() -> void:
	var rock := _material(Color(0.2, 0.18, 0.17), 0.0, 0.95)
	var lip := TorusMesh.new()
	lip.inner_radius = 0.8
	lip.outer_radius = 1.9
	_add_mesh(lip, rock, Vector3(0, 0.05, 0)).scale = Vector3(1, 0.6, 1)
	var magma := _material(Color(1.0, 0.4, 0.1), 0.0, 0.6)
	magma.emission_enabled = true
	magma.emission = Color(1.0, 0.35, 0.08)
	magma.emission_energy_multiplier = 2.5
	var pit := CylinderMesh.new()
	pit.top_radius = 1.0
	pit.bottom_radius = 1.0
	pit.height = 0.05
	_add_mesh(pit, magma, Vector3(0, 0.02, 0))
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.2)
	glow.omni_range = 9.0
	glow.light_energy = 1.6
	glow.position = Vector3(0, 1.2, 0)
	add_child(glow)
	_add_steam(Vector3(0, 0.3, 0), 1.0)
	var shape := CylinderShape3D.new()
	shape.radius = 1.6
	shape.height = 0.5
	_add_collider(shape, Vector3(0, 0.1, 0))


## A squat turbine housing over the vent, a stack venting steam, gold
## pipework and an orange band.
func _build_tap() -> void:
	health = 50.0
	var white := _material(Color(0.88, 0.88, 0.86), 0.3, 0.45)
	var gold := _material(Color(0.85, 0.62, 0.22), 0.9, 0.3)
	var orange := _material(Color(1.0, 0.45, 0.1), 0.1, 0.5)
	var dark := _material(Color(0.16, 0.17, 0.19), 0.6, 0.4)
	_add_mesh(_cylinder(1.3, 1.5, 1.4), white, Vector3(0, 0.7, 0))
	_add_mesh(_cylinder(1.32, 1.32, 0.18), orange, Vector3(0, 1.1, 0))
	_add_mesh(_cylinder(0.35, 0.45, 1.4), dark, Vector3(0, 2.0, 0))
	_add_mesh(_cylinder(0.12, 0.12, 2.6), gold, Vector3(0.75, 1.3, 0.4))
	_add_mesh(_cylinder(0.12, 0.12, 2.6), gold, Vector3(-0.75, 1.3, 0.4))
	_add_mesh(_cylinder(0.1, 0.1, 0.4), white, Vector3(0, CABLE_HEIGHT.tap - 0.2, 0))
	if !blueprint:
		_add_steam(Vector3(0, 2.7, 0), 0.5)
	var shape := CylinderShape3D.new()
	shape.radius = 1.4
	shape.height = 2.6
	_add_collider(shape, Vector3(0, 1.3, 0))


func _add_steam(at: Vector3, size: float) -> void:
	var steam := CPUParticles3D.new()
	steam.amount = 24
	steam.lifetime = 3.0
	var puff := QuadMesh.new()
	puff.size = Vector2(1.2, 1.2) * size
	var material := StandardMaterial3D.new()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.85, 0.8, 0.75, 0.3)
	material.vertex_color_use_as_albedo = true
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	var round_puff := GradientTexture2D.new()
	round_puff.gradient = soft
	round_puff.fill = GradientTexture2D.FILL_RADIAL
	round_puff.fill_from = Vector2(0.5, 0.5)
	round_puff.fill_to = Vector2(0.5, 0.0)
	round_puff.width = 64
	round_puff.height = 64
	material.albedo_texture = round_puff
	puff.material = material
	steam.mesh = puff
	steam.direction = Vector3.UP
	steam.spread = 12.0
	steam.gravity = Vector3.UP * 0.6
	steam.initial_velocity_min = 1.2 * size + 0.4
	steam.initial_velocity_max = 2.2 * size + 0.6
	steam.scale_amount_min = 1.0
	steam.scale_amount_max = 2.5
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 2.5))
	steam.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0))
	steam.color_ramp = fade
	steam.position = at
	steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(steam)


func _plinth(footprint: Vector2) -> void:
	var block := BoxMesh.new()
	block.size = Vector3(footprint.x + 0.3, 1.4, footprint.y + 0.3)
	_add_mesh(block, _material(Color(0.4, 0.39, 0.37), 0.0, 0.9), Vector3(0, -0.66, 0))


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	return mesh


func _add_mesh(mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	add_child(instance)
	return instance


func _add_collider(shape: Shape3D, pos: Vector3) -> void:
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = pos
	add_child(collider)
