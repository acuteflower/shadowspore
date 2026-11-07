shader_type canvas_item;
// The body of a waystone statue (the dormant sheet is TEXTURE). `wave_tex` holds per pixel the moment the awakening reaches it (R) and the body mask (A);
// where `progress` has passed that moment the pixel comes from the awakened sheet: the cracks mend, the growth is gone, the chips are whole.
// The statue stays world-lit (the night tint applies); the light of the awakening is drawn by waystone_glow.gdshader.
uniform sampler2D clean_tex : filter_nearest;
uniform sampler2D wave_tex : filter_nearest;
uniform float progress = 0.0;

void fragment() {
	vec4 wild = texture(TEXTURE, UV);
	vec4 clean = texture(clean_tex, UV);
	float t = texture(wave_tex, UV).r;
	COLOR = mix(wild, clean, step(t, progress));
}
