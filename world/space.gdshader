shader_type sky;
// Black, with stars and the sun's disc.

uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col = vec3(0.0);
	vec3 grid = d * 260.0;
	vec3 cell = floor(grid);
	float h = hash(cell);
	if (h > 0.985) {
		vec3 centre = cell + 0.5 + (vec3(hash(cell + 1.7), hash(cell + 3.1), hash(cell + 5.3)) - 0.5) * 0.6;
		float star = smoothstep(0.35, 0.0, distance(grid, centre));
		float tint = hash(cell + 9.0);
		col += star * (h - 0.985) * 120.0 * mix(vec3(1.0, 0.8, 0.65), vec3(0.7, 0.8, 1.0), tint);
	}
	if (LIGHT0_ENABLED) {
		float facing = dot(d, LIGHT0_DIRECTION);
		col += sun_color * smoothstep(0.9993, 0.9996, facing) * 40.0;
		col += sun_color * pow(max(facing, 0.0), 600.0) * 2.0;
	}
	COLOR = col;
}
