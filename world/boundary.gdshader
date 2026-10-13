shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.25, 0.65, 1.0, 1.0);
uniform float radius = 60.0;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line(float v, float width) {
	return smoothstep(0.5 - width, 0.5, abs(fract(v) - 0.5));
}

void fragment() {
	float along = atan(world.z, world.x) * radius;
	float grid = max(line(along / 2.0, 0.04), line(world.y / 1.5 - TIME * 0.15, 0.05));
	float near = 1.0 - smoothstep(6.0, 35.0, distance(world, CAMERA_POSITION_WORLD));
	// UV.y runs from the top of the wall (0) to the bottom (1): it fades out upwards.
	float fade = UV.y;
	ALBEDO = tint.rgb * (grid * (0.6 + 0.6 * near) + 0.08 + 0.12 * near) * fade;
}
