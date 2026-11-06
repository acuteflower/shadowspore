shader_type canvas_item;
// Red-violet glow at the screen edges after the player is hit. `amount` fades 0..1.

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.85, 0.1, 0.3, 1.0);

void fragment() {
	float edge = smoothstep(0.45, 1.1, length((UV - 0.5) * 1.4));
	COLOR = vec4(tint.rgb, edge * amount * 0.5);
}
