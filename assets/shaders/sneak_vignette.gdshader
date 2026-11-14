shader_type canvas_item;
// Sneak look: slightly cool gray picture with darkened edges. `amount` fades 0..1.

uniform sampler2D screen : hint_screen_texture, filter_nearest, repeat_disable;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float desaturation = 0.25;
uniform float darkness = 0.3;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float gray = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(gray) * vec3(0.86, 0.94, 1.10), desaturation * amount);
	vec2 q = (UV - 0.5) * vec2(1.05, 1.38);
	float edge = smoothstep(0.28, 0.82, length(q));
	c *= mix(vec3(1.0), vec3(0.62, 0.70, 0.90), edge * darkness * 1.15 * amount);
	COLOR = vec4(c, 1.0);
}
