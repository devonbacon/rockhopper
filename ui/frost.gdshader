shader_type canvas_item;
// A tint creeping in from the edges: frost as the suit cools, red when
// you're hurt.

uniform float amount = 0.0;
uniform vec4 tint : source_color = vec4(0.78, 0.9, 1.0, 1.0);

void fragment() {
	float r = distance(UV, vec2(0.5)) * 1.4;
	COLOR = vec4(tint.rgb, smoothstep(1.0 - amount, 1.2 - amount * 0.5, r) * amount * 0.8);
}
