// Wurzelgrund (docs/magie_konzept.md): the torn-open ground under the roots. World-lit (it darkens at night like any soil): churned dark earth
// in clumps with a ragged edge and a lighter torn lip of turf, cracks that run out from the middle at the burst, moss and tiny sprouts that
// spread from the middle while it lives, the green turning brown and the earth sinking back into the meadow when it ends. Whole pixels.
shader_type canvas_item;

uniform float radius = 34.0;
uniform float squash = 0.6;
uniform float age = 0.0;
uniform float grow = 1.0; // 0..1 the earth tearing open
uniform float moss = 0.0; // 0..1 green spreading from the middle
uniform float wither = 0.0; // 0..1 the end
uniform float seed = 0.0;
uniform vec4 soil_dark : source_color = vec4(0.13, 0.08, 0.12, 1.0);
uniform vec4 soil_mid : source_color = vec4(0.23, 0.15, 0.17, 1.0);
uniform vec4 soil_light : source_color = vec4(0.36, 0.25, 0.22, 1.0);
uniform vec4 turf : source_color = vec4(0.42, 0.5, 0.25, 1.0);
uniform vec4 moss_dark : source_color = vec4(0.22, 0.42, 0.17, 1.0);
uniform vec4 moss_light : source_color = vec4(0.46, 0.7, 0.26, 1.0);
uniform vec4 bloom : source_color = vec4(0.93, 0.85, 0.98, 1.0);
uniform vec4 dry : source_color = vec4(0.4, 0.33, 0.22, 1.0);

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
	float th = bayer(p);
	if (d > 1.0) {
		discard;
	}
	// the end: the earth closes from the rim inwards, in a dither
	if (wither > 0.0 && th < smoothstep(1.0 - wither * 1.2, 1.05 - wither * 1.2, d) + wither * wither * 0.8) {
		discard;
	}
	// churned earth: three tones in clumps, lighter where clods stick up
	float clump = noise(p * 0.28) * 0.6 + noise(p * 0.7 + 11.0) * 0.4;
	vec3 tone = clump < 0.38 ? soil_dark.rgb : (clump < 0.62 ? soil_mid.rgb : soil_light.rgb);
	if (clump > 0.74 && hash(p + 3.0) > 0.5) {
		tone = soil_light.rgb * 1.12; // a clod catching the light
	}
	// cracks running out from the middle at the burst, and staying as dark seams
	float spoke = abs(fract((ang + noise(vec2(r * 0.09, seed)) * 0.5) * 7.0 / 6.2831853 + seed) - 0.5);
	if (spoke < 0.035 + 0.03 * (1.0 - d) && d > 0.12) {
		tone = soil_dark.rgb * 0.65;
	}
	// the torn lip: a lighter ring of turf, the shaded inside under it
	if (d > 0.86) {
		tone = (p.y < 0.0) ? mix(tone, turf.rgb, 0.75) : mix(tone, turf.rgb * 0.8, 0.6);
		if (d > 0.95 && th > 0.5) {
			tone = turf.rgb * 1.08;
		}
	} else if (d > 0.78 && p.y < 0.0) {
		tone *= 0.7; // the far bank throws a little shade into the hole
	}
	// moss and sprouts spread from the middle
	float reach = moss * 1.05 - d * 0.7;
	float patch_n = noise(p * 0.22 + vec2(seed * 3.0, 0.0));
	if (reach > 0.0 && patch_n < reach * 1.3 && d < 0.86) {
		tone = (noise(p * 0.6 + 5.0) > 0.5) ? moss_light.rgb : moss_dark.rgb;
		if (hash(floor(p)) > 0.985 && moss > 0.6) {
			tone = bloom.rgb; // a tiny flower here and there
		}
	}
	// withering: the green turns to dry brown
	tone = mix(tone, mix(dry.rgb, tone, 0.35), wither * step(0.5, (tone.g - tone.r) * 4.0 + 0.5));
	COLOR = vec4(tone, 1.0);
}
