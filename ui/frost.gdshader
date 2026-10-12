shader_type canvas_item;
// Frost creeping in from the edges as the suit cools.

uniform float amount = 0.0;

void fragment() {
	float r = distance(UV, vec2(0.5)) * 1.4;
	COLOR = vec4(0.78, 0.9, 1.0, smoothstep(1.0 - amount, 1.2 - amount * 0.5, r) * amount * 0.8);
}
