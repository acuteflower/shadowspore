shader_type canvas_item;
// The lit picture of the boss arena (floor and pillars) in the last phase: every turquoise pixel (the sigil, the rings, the ley lines, the veins in the pillars) is
// recoloured into dark pink-violet; it stays lit by the world like the stone round it. The glow itself is `fury_teal_glow.gdshader` on top (additive, unshaded).

uniform float fury : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float teal = smoothstep(0.03, 0.16, min(tex.g, tex.b) - tex.r);
	float lum = clamp(dot(tex.rgb, vec3(0.299, 0.587, 0.114)) * 1.7, 0.0, 1.0);
	vec3 deep = vec3(0.30, 0.09, 0.50);
	vec3 mid = vec3(0.80, 0.24, 0.68);
	vec3 pink = mix(deep, mid, lum);
	COLOR = vec4(mix(tex.rgb, pink, teal * fury) * COLOR.rgb, tex.a * COLOR.a);
}
