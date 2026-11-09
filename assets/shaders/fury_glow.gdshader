shader_type canvas_item;
render_mode unshaded;
// The inlaid light of the boss arena (floor and pillars, sheets that hold only the glowing pixels) turning from turquoise into the pink-violet fire of Mornath's
// last phase. `fury` 0 = the sheet as it is, 1 = burning: every glowing pixel is mapped by its brightness onto a violet -> magenta -> pale pink ramp, and patches of
// the light (a few pixels wide) flare up white-hot now and then, each on its own beat, so the light burns only partly and never evenly.

uniform float fury : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;
uniform float patch_px = 7.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 px = UV / TEXTURE_PIXEL_SIZE;
	float lum = clamp(dot(tex.rgb, vec3(0.299, 0.587, 0.114)) * 1.35, 0.0, 1.0);
	vec3 deep = vec3(0.50, 0.14, 0.86);
	vec3 mid = vec3(1.0, 0.33, 0.86);
	vec3 hot = vec3(1.0, 0.85, 0.97);
	vec3 pink = lum < 0.55 ? mix(deep, mid, lum / 0.55) : mix(mid, hot, (lum - 0.55) / 0.45);
	vec2 cell = floor(px / patch_px);
	float slow = hash(cell * 1.7 + floor(time * 0.6));
	float quick = hash(cell + floor(time * 7.0) * 0.37);
	float burn = step(0.72, slow) * (0.5 + 0.5 * quick);
	pink = mix(pink, hot, burn * 0.65);
	pink *= 0.92 + 0.25 * sin(time * 5.0 + px.x * 0.07 + px.y * 0.05);
	vec3 rgb = mix(tex.rgb, pink, fury);
	COLOR = vec4(rgb * COLOR.rgb, tex.a * COLOR.a);
}
