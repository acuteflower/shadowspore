shader_type canvas_item;
render_mode unshaded, blend_add;
#include "res://assets/shaders/night_noise.gdshaderinc"
// Lightning (docs/wetter_konzept.md section 7.2): one additive pass. The whole picture flares in a few flat steps (Bayer dithered, brightest in the
// sky half), and a jagged one-pixel bolt tears down from the top to the strike point with a short side branch and a flare where it lands. A far flash is
// only sheet lightning: a pale blob behind the clouds, no bolt. The colour is the flash's own (cold white, green in the Hexenwald, magenta at the void).

uniform vec2 view_px = vec2(640.0, 360.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 color : source_color = vec3(0.80, 0.84, 1.0);
uniform vec2 strike = vec2(0.5, 0.7); // screen fractions
uniform float bolt = 0.0; // 1: draw the bolt
uniform float bolt_seed = 0.0;
uniform float far = 0.0;

float node_x(float i, float top_x, float end_x, float end_y) {
	float t = clamp(i * 9.0 / max(end_y, 1.0), 0.0, 1.0);
	return mix(top_x, end_x, t) + (n_hash(vec2(i, bolt_seed)) - 0.5) * 30.0 * (1.0 - 0.55 * t);
}

void fragment() {
	vec2 s = floor(UV * view_px + 0.001);
	float b = n_bayer(s);
	float sky = mix(1.0, 0.55, smoothstep(0.1, 1.0, UV.y));
	float f = flash * (0.07 + 0.09 * sky);
	float q = floor(f * 7.0 + b) / 7.0; // a few flat steps, dithered
	vec3 add = color * q;
	vec2 target = strike * view_px;
	// sheet lightning: a pale blob where the cloud lights up
	vec2 blob = (s - vec2(target.x, target.y * 0.45)) / vec2(180.0, 90.0);
	add += color * flash * 0.09 * exp(-dot(blob, blob) * 1.4) * (far * 0.7 + 0.3) * step(b * 0.5, 0.7);
	if (bolt > 0.5 && flash > 0.18 && s.y <= target.y) {
		float top_x = target.x + (n_hash(vec2(bolt_seed, 3.0)) - 0.5) * 120.0;
		float seg = floor(s.y / 9.0);
		float fr = (s.y - seg * 9.0) / 9.0;
		float x0 = node_x(seg, top_x, target.x, target.y);
		float x1 = node_x(seg + 1.0, top_x, target.x, target.y);
		float xp = mix(x0, x1, fr);
		float d = abs(s.x + 0.5 - xp);
		if (d < 0.95) { add = vec3(1.0, 1.0, 1.0); }
		else if (d < 2.6 && b < 0.4) { add += color * 0.55 * flash; } // a dithered halo
		// a branch leaves the main stroke two thirds down
		float yb = target.y * 0.52;
		if (s.y > yb && s.y < yb + 62.0) {
			float sb = floor(yb / 9.0);
			float xb = mix(node_x(sb, top_x, target.x, target.y), node_x(sb + 1.0, top_x, target.x, target.y), 0.5);
			float side = n_hash(vec2(bolt_seed, 9.0)) > 0.5 ? 1.0 : -1.0;
			float xr = xb + side * (s.y - yb) * 0.55 + (n_hash(vec2(floor((s.y - yb) / 6.0), bolt_seed + 5.0)) - 0.5) * 9.0;
			if (abs(s.x + 0.5 - xr) < 0.8) { add = vec3(0.9, 0.93, 1.0) * 0.85; }
		}
	}
	vec2 r = s - target;
	float flare = exp(-dot(r, r) / 340.0) * flash * step(0.5, bolt);
	add += color * flare * 0.55;
	COLOR = vec4(add, 1.0);
}
