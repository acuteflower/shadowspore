shader_type canvas_item;
render_mode unshaded;
// The screen closes in while the dark creeps from the edges (crossroad ambush). amount 0..1.
uniform float amount = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5); }

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= 1.78;
	float d = length(uv) * (1.0 + 0.03 * sin(TIME * 2.4) * amount);
	float edge = smoothstep(0.92 - amount * 0.72, 1.18 - amount * 0.34, d);
	float inner_rim = smoothstep(0.0, 0.55, edge) * (1.0 - edge);
	float noise = (hash(FRAGCOORD.xy) - 0.5) / 255.0;
	vec3 col = mix(vec3(0.025, 0.0, 0.06), vec3(0.14, 0.02, 0.16), inner_rim * 0.85);
	float a = clamp(edge * (0.58 + amount * 0.44) + noise, 0.0, 0.96);
	COLOR = vec4(col, a);
}
