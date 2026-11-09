shader_type canvas_item;
render_mode unshaded, blend_add;
// The glowing layer of the arena's burning light (docs/boss_sky_cleaver.md): laid over the arena's own picture, it shows only the turquoise pixels of it, as
// bright pink-violet fire that flares white-hot in patches a few pixels wide, each on its own beat. Additive and unshaded, so it burns through the night tint.

uniform float fury : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;
uniform float patch_px = 7.0;
uniform float strength = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 px = UV / TEXTURE_PIXEL_SIZE;
	float teal = smoothstep(0.03, 0.16, min(tex.g, tex.b) - tex.r) * tex.a;
	float lum = clamp(dot(tex.rgb, vec3(0.299, 0.587, 0.114)) * 1.7, 0.0, 1.0);
	vec3 mid = vec3(1.0, 0.33, 0.86);
	vec3 hot = vec3(1.0, 0.85, 0.97);
	vec3 pink = mix(vec3(0.62, 0.18, 0.95), mid, lum);
	vec2 cell = floor(px / patch_px);
	float slow = hash(cell * 1.7 + floor(time * 0.6));
	float quick = hash(cell + floor(time * 7.0) * 0.37);
	float burn = step(0.7, slow) * (0.5 + 0.5 * quick);
	pink = mix(pink, hot, burn * 0.7);
	float flick = 0.8 + 0.2 * sin(time * 5.0 + px.x * 0.07 + px.y * 0.05);
	COLOR = vec4(pink * flick, teal * fury * strength * (0.55 + 0.6 * burn) * COLOR.a);
}
