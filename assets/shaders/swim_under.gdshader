shader_type canvas_item;
// The part of the body below the waterline (sheet player_swim_under.png): pulled towards the water's colour, darker, rows sliding sideways in
// whole pixels with a slow wave, every fifth row a glint, and fading out (dithered) the deeper it is. Frames are 64x72, the water line is row 46.
global uniform float g_water_time;
uniform float frame_height = 72.0;
uniform float water_row = 46.0;
uniform vec3 fill : source_color = vec3(0.263, 0.529, 0.502);
uniform float depth_px = 24.0;
uniform float energy = 0.5; // 0..1, bigger waves while she swims hard

void fragment() {
	vec2 size = vec2(textureSize(TEXTURE, 0));
	float row = mod(floor(UV.y * size.y), frame_height);
	float depth = max(row - water_row, 0.0);
	float wave = sin(row * 0.55 + g_water_time * 2.6) + 0.6 * sin(row * 1.3 - g_water_time * 1.7);
	float shift = floor(wave * (0.55 + 0.8 * energy) + 0.5);
	vec4 c = texture(TEXTURE, UV + vec2(shift / size.x, 0.0));
	vec3 rgb = mix(c.rgb, fill, 0.55) * 0.78;
	if (mod(row, 5.0) < 1.0) { rgb += vec3(0.07, 0.10, 0.09); }
	vec2 px = floor(UV * size);
	float bayer = fract(sin(dot(mod(px, vec2(4.0)), vec2(12.9, 78.2))) * 437.5);
	float keep = clamp(1.0 - depth / depth_px, 0.0, 1.0);
	float a = c.a * 0.72;
	if (keep < bayer * 0.9 + 0.1 && depth > 3.0) { a = 0.0; }
	COLOR = vec4(rgb, a);
}
