shader_type canvas_item;
render_mode unshaded;
// The self-lit pixels of the title logo: void veins and magenta cores beat like the shadow creatures' (a double pulse that runs along the
// veins), life roots and glow caps breathe, berries flicker, the crack at the ground ripples, the spore flower swells.
// glow_map: R = phase (0..1 by x), G = kind * 32. The pixels of plants sway with them (same sway map as the plant layer).
#include "res://assets/shaders/title_sway.gdshaderinc"

uniform sampler2D glow_map : filter_nearest;
uniform float time = 0.0;
uniform float intensity = 1.0;
uniform float beat_rate = 0.8; // heartbeats per second of the void
// build-up: the crack at the ground splits open from the middle outwards, then the light runs from left to right through the veins
uniform float center_x = 220.0;
uniform float crack_reach = 9999.0;  // px from the middle
uniform float front = 9999.0;        // x of the light front (veins, cores, roots to the left of it are lit)

float beat(float t) {
	// lub-dub: two quick bumps, then rest
	float x = fract(t);
	float a = exp(-pow((x - 0.08) / 0.05, 2.0));
	float b = exp(-pow((x - 0.24) / 0.06, 2.0)) * 0.75;
	return clamp(a + b, 0.0, 1.0);
}

void fragment() {
	ivec2 size = textureSize(TEXTURE, 0);
	ivec2 p = ivec2(floor(UV * vec2(size)));
	vec4 c = vec4(0.0);
	ivec2 src = p;
	for (int o = -MAX_SHIFT; o <= MAX_SHIFT; o++) {
		ivec2 s = ivec2(p.x - o, p.y);
		if (s.x < 0 || s.x >= size.x) {
			continue;
		}
		if (o != 0 && sway_weight(s) <= 0.0) {
			continue;
		}
		if (sway_offset(s) != o) {
			continue;
		}
		if (texelFetch(TEXTURE, s, 0).a > 0.0) {
			src = s;
			c = texelFetch(TEXTURE, s, 0);
		}
	}
	if (c.a <= 0.0) {
		discard;
	}
	vec4 m = texelFetch(glow_map, src, 0);
	float phase = m.r;
	int kind = int(floor(m.g * 255.0 / 32.0 + 0.5));
	float hot = 0.0;
	if (sway_weight(src) > 0.0) {
		if (plant_cut(src) > grow) {
			discard;
		}
	} else if (kind == 5) {
		float d = abs(float(src.x) - center_x);
		if (d > crack_reach) {
			discard;
		}
		hot = exp(-pow((crack_reach - d) / 8.0, 2.0));
	} else {
		if (float(src.x) > front) {
			discard;
		}
		hot = exp(-pow((front - float(src.x)) / 10.0, 2.0));
	}
	float k;
	if (kind == 0) { // void vein: the beat runs outward along the vein
		k = 0.5 + 0.6 * beat(time * beat_rate - phase * 0.6);
	} else if (kind == 1) { // magenta core: the heart of the beat
		k = 0.55 + 0.65 * beat(time * beat_rate - phase * 0.3);
	} else if (kind == 2) { // life: a slow breath
		k = 0.78 + 0.28 * sin(time * 1.5 + phase * 6.2832);
	} else if (kind == 3) { // berry: a warm flicker
		k = 0.8 + 0.2 * sin(time * 3.1 + phase * 9.0) * sin(time * 1.7 + phase * 5.0);
	} else if (kind == 4) { // shroom: a breath out of step with the others
		k = 0.72 + 0.34 * sin(time * 1.1 + phase * 6.2832 + 1.7);
	} else if (kind == 5) { // the crack at the ground: a ripple runs along it
		k = 0.6 + 0.5 * pow(max(0.0, sin(time * 1.3 - phase * 6.2832 * 1.5)), 2.0);
	} else { // bloom: the spore flower swells and rests
		k = 0.82 + 0.3 * sin(time * 1.2) * sin(time * 1.2) + 0.12 * sin(time * 4.3 + phase * 3.0);
	}
	COLOR = vec4(clamp(c.rgb * k * intensity * (1.0 + 1.4 * hot) + vec3(0.5, 0.55, 0.7) * hot * 0.6, 0.0, 1.0), 1.0);
}
