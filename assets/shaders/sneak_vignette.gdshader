shader_type canvas_item;
// Sneak look: slightly cool gray picture with darkened edges. `amount` fades 0..1.

uniform sampler2D screen : hint_screen_texture, filter_nearest, repeat_disable;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float desaturation = 0.25;
uniform float darkness = 0.3;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float gray = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(gray) * vec3(0.93, 0.98, 1.08), desaturation * amount);
	float edge = smoothstep(0.3, 0.95, length((UV - 0.5) * 1.35));
	c *= 1.0 - edge * darkness * amount;
	COLOR = vec4(c, 1.0);
}
