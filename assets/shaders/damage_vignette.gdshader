shader_type canvas_item;
render_mode unshaded;
// Red-violet glow at the screen edges after the player is hit. `amount` fades 0..1.

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.85, 0.1, 0.3, 1.0);

void fragment() {
	vec2 q = (UV - 0.5) * vec2(1.22, 1.55);
	float edge = smoothstep(0.36, 0.92, length(q));
	float pulse = 1.0 + 0.08 * sin(TIME * 12.0) * amount;
	vec3 col = mix(tint.rgb, vec3(1.0, 0.24, 0.42), edge * 0.35 * amount);
	float noise = (fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
	COLOR = vec4(col, clamp(edge * amount * 0.56 * pulse + noise, 0.0, 0.85));
}
