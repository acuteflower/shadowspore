shader_type canvas_item;
render_mode unshaded;
// The glowing parts of the clumps (dew, blossom hearts, void-violet tips): dim by day, bright at night. Moves exactly like clover_clumps.gdshader.
global uniform vec2 g_wind_dir;
global uniform float g_wind_gust;
global uniform float g_wind_clock;
global uniform float g_night;
uniform float count = 21.0;
uniform vec4 actors[4];
uniform vec2 band_origin = vec2(0.0); // the band's place in the world; the clump's own offset rides in INSTANCE_CUSTOM.a (nothing depends on the camera)
varying vec4 detail;

void vertex() {
	detail = INSTANCE_CUSTOM;
	vec2 foot = (MODEL_MATRIX * vec4(0.0, 9.0, 0.0, 1.0)).xy;
	float clock = floor(g_wind_clock * 12.0) / 12.0;
	float pulse = 0.5 + 0.5 * sin(dot(foot, g_wind_dir) * 0.03 - clock * 1.6 + sin(foot.y * 0.05) * 1.2);
	float breeze = 0.12 + (g_wind_gust <= 1.1 ? g_wind_gust : 1.1 + 0.9 * tanh((g_wind_gust - 1.1) * 0.35)) * (0.35 + 0.65 * pulse);
	float flutter = sin(clock * 2.3 + detail.g * 6.283) * breeze * 0.35;
	vec2 wind = g_wind_dir * breeze * detail.b * 2.0 + vec2(flutter, flutter * 0.25);
	vec2 contact = vec2(0.0);
	float press = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 d = foot - actors[i].xy;
		float f = (1.0 - smoothstep(2.0, 20.0, length(d))) * actors[i].z;
		contact += normalize(d + vec2(0.001)) * f * vec2(7.0, 3.5);
		press += f;
	}
	float rooted = pow(UV.y, 1.4);
	VERTEX += round((wind + contact) * rooted) + vec2(0.0, round(min(press, 1.0) * 2.5 * rooted));
}

void fragment() {
	float kind = floor(detail.r * count + 0.5);
	COLOR = texture(TEXTURE, vec2((UV.x + kind) / count, 1.0 - UV.y));
	COLOR.a *= 0.15 + 0.6 * g_night;
}
