shader_type spatial;
render_mode unshaded, cull_back;
// A screen in the world: what its viewport shows, with scanlines and a
// slight flicker, bright enough to glow in the dark.

uniform sampler2D screen : source_color, filter_linear;

void fragment() {
	vec3 colour = texture(screen, UV).rgb;
	float lines = 0.82 + 0.18 * sin(UV.y * 900.0);
	float flicker = 0.97 + 0.03 * sin(TIME * 47.0);
	ALBEDO = colour * lines * flicker * 1.4;
}
