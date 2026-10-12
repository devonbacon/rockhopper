class_name Sun
extends DirectionalLight3D
## The star, circling the asteroid as it turns. It's the light that sweeps
## round, not the rock, so the day-night line crawls over the surface.
## The sun sits 20 degrees off the rock's equator: one pole never sets,
## the other never rises.

const DAY := 240.0
const AXIS := Vector3.UP
const TILT := deg_to_rad(20.0)
const START := Vector3(0.9396926, 0.3420201, 0.0)

var time := 0.0


func _ready() -> void:
	shadow_enabled = true
	directional_shadow_max_distance = 140.0
	light_energy = 1.6
	light_color = Color(1.0, 0.96, 0.9)
	sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	set_time(time)


## Unit vector from the asteroid towards the sun at time t.
static func dir_at(t: float) -> Vector3:
	return START.rotated(AXIS, TAU * t / DAY)


func set_time(t: float) -> void:
	time = t
	basis = Basis.looking_at(-dir_at(t), Vector3.UP)


## Whether nothing but space lies between p and the sun, now or at time
## t. On a rock this small and lumpy, that's often well past where a
## smooth horizon would put sunset.
func lights(p: Vector3, space: PhysicsDirectSpaceState3D, t: float = NAN) -> bool:
	var query := PhysicsRayQueryParameters3D.create(p, p + dir_at(time if is_nan(t) else t) * 250.0, Asteroid.ROCK_LAYER)
	return space.intersect_ray(query).is_empty()


## Whether the sun reaches p at each of `steps` moments spread over the
## next turn, starting now.
func forecast(p: Vector3, space: PhysicsDirectSpaceState3D, steps: int) -> Array[bool]:
	var lit: Array[bool] = []
	for i in steps:
		lit.push_back(lights(p, space, time + DAY * i / float(steps)))
	return lit
