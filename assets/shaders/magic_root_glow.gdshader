// Wurzelgrund (docs/magie_konzept.md): the living light of the healing ground, drawn over the soil. A breathing witch-green ring along the torn
// edge, faint veins of light from the middle to the roots, the green ring of each healing beat running outwards, a soft bloom of light at
// the middle. Additive and unshaded (it stays green at night), whole pixels with dithered steps.
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float radius = 34.0;
uniform float squash = 0.6;
uniform float age = 0.0;
uniform float grow = 1.0;
uniform float wither = 0.0;
uniform float beat = 0.0; // 0..1 the last healing beat on its way out (0 = none)
uniform float bloom = 0.0; // 0..1 BLÜTENSCHLUSS flash
uniform float seed = 0.0;
uniform vec4 core : source_color = vec4(0.66, 0.94, 0.44, 1.0);
uniform vec4 deep : source_color = vec4(0.18, 0.42, 0.16, 1.0);
uniform vec4 white : source_color = vec4(0.94, 1.0, 0.84, 1.0);

varying vec2 local;

void vertex() {
	local = VERTEX;
}

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float bayer(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	return (BAYER[q.x + q.y * 4] + 0.5) / 16.0;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.3) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = floor(local) + 0.5;
	vec2 e = vec2(p.x, p.y / squash);
	float r = length(e);
	float ang = atan(e.y, e.x);
	float edge = radius * (0.9 + 0.14 * noise(vec2(ang * 2.6 + seed, seed)) + 0.05 * noise(vec2(ang * 9.0, 3.0))) * grow;
	float d = r / max(edge, 1.0);
	float alive = 1.0 - wither;
	float light = 0.0;
	float hot = 0.0;
	// the ring along the torn edge, breathing
	float breath = 0.6 + 0.4 * sin(age * 2.4);
	float ring = abs(d - 0.93);
	if (ring < 0.05) {
		light = 0.6 * breath * (0.7 + 0.3 * noise(vec2(ang * 6.0 + age, 1.0)));
		hot = 0.2;
	} else if (d < 1.12 && d > 0.98) {
		light = 0.12 * breath * (1.12 - d) / 0.14;
	}
	// veins of light from the middle towards the roots
	float vein = abs(fract((ang + noise(vec2(r * 0.12, seed + 4.0)) * 0.7) * 5.0 / 6.2831853 + seed * 0.5) - 0.5);
	if (vein < 0.02 && d < 0.85 && d > 0.1) {
		float run = fract(d * 1.5 - age * 0.8);
		light = max(light, 0.18 + 0.32 * smoothstep(0.7, 1.0, run));
	}
	// the middle
	light = max(light, 0.22 * (1.0 - smoothstep(0.0, 0.3, d)) * breath);
	// a healing beat runs out
	if (beat > 0.0) {
		float br = beat * 1.0;
		if (abs(d - br) < 0.045) {
			light = max(light, 0.7 * (1.0 - beat * 0.6));
			hot = 0.6;
		}
	}
	// BLÜTENSCHLUSS: everything flares once
	if (bloom > 0.0 && d < 1.0) {
		light = max(light, bloom * (0.6 - 0.35 * d));
		hot = max(hot, bloom);
	}
	light *= alive;
	if (d > 1.15) {
		discard;
	}
	float stepped = floor(clamp(light, 0.0, 1.0) * 4.0 + bayer(p)) / 4.0;
	if (stepped <= 0.0) {
		discard;
	}
	vec3 tone = mix(deep.rgb, core.rgb, clamp(stepped * 1.4, 0.0, 1.0));
	tone = mix(tone, white.rgb, clamp(hot * stepped, 0.0, 1.0));
	COLOR = vec4(tone, stepped);
}
