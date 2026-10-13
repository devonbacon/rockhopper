class_name Sun
extends DirectionalLight3D
## The star, crossing the sky as the rock turns: up in the east, over at
## 65 degrees, down in the west, then a night as long as the day. Low in
## the sky the hills' shadows run long, so the hollows go dark first and
## the high ground holds the light longest.

const DAY := 300.0
const TILT := deg_to_rad(25.0)
## How far the sun's climbed at the start.
const START := deg_to_rad(24.0)

var time := 0.0


func _ready() -> void:
	shadow_enabled = true
	directional_shadow_max_distance = 220.0
	light_energy = 1.6
	light_color = Color(1.0, 0.96, 0.9)
	sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	set_time(time)


## Unit vector towards the sun at time t.
static func dir_at(t: float) -> Vector3:
	var angle := START + TAU * t / DAY
	return Vector3(cos(angle), sin(angle) * cos(TILT), sin(angle) * sin(TILT))


func set_time(t: float) -> void:
	time = t
	var dir := dir_at(t)
	basis = Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	visible = dir.y > -0.1


## Whether the sun's up and nothing but space lies between p and it, now
## or at time t.
func lights(p: Vector3, space: PhysicsDirectSpaceState3D, t: float = NAN) -> bool:
	var dir := dir_at(time if is_nan(t) else t)
	if dir.y <= 0.0:
		return false
	var query := PhysicsRayQueryParameters3D.create(p, p + dir * 250.0, Terrain.ROCK_LAYER)
	return space.intersect_ray(query).is_empty()


## Whether the sun reaches p at each of `steps` moments spread over the
## next turn, starting now.
func forecast(p: Vector3, space: PhysicsDirectSpaceState3D, steps: int) -> Array[bool]:
	var lit: Array[bool] = []
	for i in steps:
		lit.push_back(lights(p, space, time + DAY * i / float(steps)))
	return lit
