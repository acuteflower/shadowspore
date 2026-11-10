shader_type canvas_item;
render_mode unshaded;
#include "res://assets/shaders/daylight.gdshaderinc"
#include "res://assets/shaders/night_noise.gdshaderinc"
// The clouds themselves (docs/wetter_konzept.md section 5.3): masses of pixel cloud drifting over the land, drawn from the SAME field that casts
// the cloud shadows (cloud_thick in daylight.gdshaderinc). A cloud is drawn up and to the left of its shadow (`height`: the sun is low in the
// evening, so the offset grows), which gives the 3/4 view its altitude and shows which cloud throws which shadow. Four flat tones lit from the upper
// left (an edge is bright where the cloud gets thinner towards the light), a Bayer dither at the thin rim, one thin high veil of streaks along the wind.
// Every pixel is a whole art pixel (like the night fog), nothing is smoothed.

uniform vec2 world_origin = vec2(0.0);
uniform vec2 view_px = vec2(640.0, 360.0);
uniform vec2 height = vec2(54.0, 62.0); // px between the cloud and its shadow
uniform float alpha_max : hint_range(0.0, 1.0) = 0.56;
uniform float golden : hint_range(0.0, 1.0) = 0.0;
uniform float storm : hint_range(0.0, 1.0) = 0.0;
uniform float cover : hint_range(0.0, 1.0) = 0.0;
uniform float visibility : hint_range(0.0, 1.0) = 1.0;
uniform float clock = 0.0;
uniform vec3 ambient : source_color = vec3(1.0); // the daylight tint (dark at night)
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform vec2 light_dir = vec2(-0.7, -0.7); // towards the light

const vec3 SHADE = vec3(0.48, 0.54, 0.70);
const vec3 BODY = vec3(0.67, 0.72, 0.85);
const vec3 SOFT = vec3(0.86, 0.89, 0.96);
const vec3 LIT = vec3(1.0, 0.99, 0.97);

vec3 tone_color(int i) {
	if (i <= 0) { return SHADE; }
	if (i == 1) { return BODY; }
	if (i == 2) { return SOFT; }
	return LIT;
}

void fragment() {
	vec2 w = floor(world_origin + UV * view_px + 0.001); // the art pixel of the world under this fragment
	vec2 q = w + height + 0.5; // where in the cloud field this cloud stands
	float th = cloud_thick(q);
	float b = n_bayer(w);
	vec4 out_color = vec4(0.0);
	if (th > 0.0) {
		float edge = smoothstep(0.0, 0.22, th);
		if (edge >= b * 0.85 + 0.06) {
			vec2 toward = normalize(light_dir);
			float d0 = cloud_density(q);
			float d_l = cloud_density(q + toward * 5.0);
			float d_f = cloud_density(q + toward * 12.0);
			float rim = clamp((d0 - d_l) * 16.0 + (d0 - d_f) * 5.0, -1.0, 1.0); // > 0: the cloud is lower towards the light: a lit edge
			float det = texture(g_cloud_tex, q / 512.0 + vec2(0.37, 0.61)).g; // puffs inside the mass
			float tone = 0.60 + 0.42 * rim + (det - 0.5) * 0.7 - 0.30 * smoothstep(0.5, 1.0, th) * (0.7 + 0.3 * storm);
			int step_i = int(clamp(floor(clamp(tone, 0.0, 0.999) * 4.0), 0.0, 3.0));
			vec3 col = tone_color(step_i);
			// golden hour: warm tops, rosy undersides
			col = mix(col, step_i >= 2 ? vec3(1.0, 0.80, 0.52) : vec3(0.76, 0.56, 0.70), golden * (step_i >= 2 ? 0.7 : 0.45));
			// overcast is grey, a storm cloud is dark with a violet belly
			col = mix(col, vec3(0.58, 0.60, 0.66) * (0.7 + 0.12 * float(step_i)), smoothstep(0.6, 1.0, cover) * 0.5);
			col = mix(col, col * vec3(0.40, 0.42, 0.58), clamp(storm * 0.95, 0.0, 1.0));
			float a = alpha_max * (0.62 + 0.38 * smoothstep(0.1, 0.8, th)) * (1.0 + 0.3 * storm);
			out_color = vec4(col * ambient, a * visibility);
		}
	}
	if (out_color.a <= 0.0 && cover < 0.62) {
		// the high veil: long thin streaks along the wind, only in a fairly open sky
		vec2 qc = w + height * 1.9 + g_cloud_drift * 1.35;
		vec2 wd = normalize(wind_dir);
		float along = dot(qc, wd);
		float perp = dot(qc, vec2(-wd.y, wd.x));
		float n = n_fbm(vec2(along / 360.0, perp / 34.0) + 7.0);
		float streak = smoothstep(0.60, 0.76, n) * (1.0 - smoothstep(0.30, 0.62, cover));
		if (streak > b * 0.9 + 0.1) {
			out_color = vec4(mix(vec3(0.96, 0.97, 1.0), vec3(1.0, 0.86, 0.68), golden * 0.6) * ambient, 0.20 * visibility);
		}
	}
	COLOR = out_color;
}
