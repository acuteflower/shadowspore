shader_type canvas_item;
render_mode unshaded;
// The emissive layer of a waystone statue (TEXTURE = the dim glints of the dormant statue, `lit_tex` = crystals, runes, eyes and halos of the awakened one).
// Pixels the wave has reached show the awakened sheet; the front of the wave itself is a dithered line of white-teal light that runs over the body.
uniform sampler2D lit_tex : filter_nearest;
uniform sampler2D wave_tex : filter_nearest;
uniform float progress = 0.0;
uniform float dim_level = 0.35;
uniform float lit_level = 1.0;
uniform float front_width = 0.045;
uniform float flash = 0.0; // 0..1: everything blooms for an instant

void fragment() {
	vec4 dim = texture(TEXTURE, UV);
	vec4 lit = texture(lit_tex, UV);
	vec4 wave = texture(wave_tex, UV);
	float reached = step(wave.r, progress);
	vec4 c = mix(vec4(dim.rgb, dim.a * dim_level), vec4(lit.rgb * lit_level, lit.a * clamp(lit_level, 0.0, 1.0)), reached);
	vec2 px = floor(UV * vec2(textureSize(wave_tex, 0)));
	float checker = mod(px.x + px.y, 2.0);
	float live = step(0.002, progress) * (1.0 - step(1.1, progress));
	float edge = 1.0 - smoothstep(0.0, front_width, abs(progress - wave.r));
	float front = edge * wave.a * live * (checker > 0.5 ? 1.0 : 0.55);
	vec3 front_color = mix(vec3(0.45, 0.95, 0.9), vec3(0.95, 1.0, 1.0), edge);
	float a = max(c.a, front * 0.9);
	vec3 rgb = mix(c.rgb, front_color, front);
	rgb = mix(rgb, vec3(1.0), flash * 0.55 * lit.a);
	COLOR = vec4(rgb, min(a + flash * 0.35 * lit.a, 1.0));
}
