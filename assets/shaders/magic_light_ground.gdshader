// Bannlicht (docs/magie_konzept.md): the floor of the standing light round Ellie. Drawn in whole art pixels of the zone's own frame
// (the node sits on a whole pixel): a dithered pool of lantern teal that is brighter towards the rim and in a small core, slow ripples
// running outwards, faint spokes turning, a bright rim with a ring of turning runes just inside it, a halo outside, the shock ring of
// the opening, the SONNENKERN pulse, the NACHBRAND flash and a crumbling dissolve at the end. Additive and unshaded: it is light.
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float radius = 40.0;
uniform float squash = 0.6;
uniform float age = 0.0; // seconds since it opened
uniform float grow = 1.0; // 0..1 the opening (already eased)
uniform float fade = 0.0; // 0..1 the end
uniform float pulse = 0.0; // 0..1 a SONNENKERN ring on its way out, 0 = none
uniform float flare = 0.0; // 0..1 the NACHBRAND flash
uniform float burn = 0.0; // 0..1 something burns inside: the light flickers hotter
uniform float seed = 0.0;
uniform vec4 core : source_color = vec4(0.5, 0.94, 0.86, 1.0);
uniform vec4 deep : source_color = vec4(0.1, 0.5, 0.5, 1.0);
uniform vec4 white : source_color = vec4(0.92, 1.0, 0.95, 1.0);

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
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.17) * 43758.5453);
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
	float th = bayer(p);
	float alive = 1.0 - fade;
	float big_r = radius * grow * (1.0 - 0.35 * fade * fade);
	float d = r / max(big_r, 1.0);
	float light = 0.0;
	float hot = 0.0; // 0 = deep teal .. 1 = white
	if (r < big_r) {
		float rim_ramp = smoothstep(0.3, 1.0, d);
		float core_glow = 1.0 - smoothstep(0.0, 0.3, d);
		float ripple = 0.5 + 0.5 * sin(d * 16.0 - age * 4.2);
		float spokes = pow(0.5 + 0.5 * cos(ang * 7.0 + age * 0.5 + seed), 10.0) * (1.0 - d) * 0.22;
		float flicker = burn * (noise(p * 0.18 + vec2(age * 3.0, -age * 2.0)) - 0.4) * 0.18;
		light = 0.16 + 0.24 * rim_ramp + 0.3 * core_glow + 0.08 * ripple + spokes + flicker;
		hot = 0.25 * rim_ramp + 0.6 * core_glow + spokes * 2.0;
		// the runes: fourteen slots turning slowly just inside the rim, each a little 3x3 mark
		float slots = 14.0;
		float turn = ang + age * 0.22;
		float slot = floor(turn / (6.2831853 / slots));
		float within = fract(turn / (6.2831853 / slots));
		float band = (big_r - r);
		if (band > 2.5 && band < 6.5 && within > 0.3 && within < 0.7) {
			vec2 cell = floor(vec2((within - 0.3) / 0.4 * 3.0, (band - 2.5) / 4.0 * 3.0));
			float bit = step(0.45, hash(vec2(slot, cell.x * 3.0 + cell.y)));
			float lit = 0.55 + 0.25 * sin(age * 2.0 + slot);
			light = max(light, bit * lit);
			hot = max(hot, bit * 0.5);
		}
		// the inner thread two pixels inside the rim
		if (abs(r - (big_r - 8.5)) < 0.5 && hash(vec2(floor(ang * 20.0), 3.0)) > 0.25) {
			light = max(light, 0.32);
		}
	}
	// the rim: a bright line, a softer one under it
	float rim = abs(r - big_r);
	if (rim < 0.9) {
		light = max(light, 0.85);
		hot = max(hot, 0.7);
	} else if (rim < 1.9 && r < big_r) {
		light = max(light, 0.5);
		hot = max(hot, 0.35);
	}
	// a halo outside the rim
	if (r >= big_r && r < big_r + 8.0) {
		float h = 1.0 - (r - big_r) / 8.0;
		light = max(light, 0.3 * h * h);
	}
	// the shock ring of the opening: runs out past the rim and is gone after half a second
	float shock_t = clamp(age / 0.5, 0.0, 1.0);
	float shock_r = radius * (0.2 + 1.15 * sqrt(shock_t));
	if (shock_t < 1.0 && abs(r - shock_r) < 1.5 - shock_t) {
		light = max(light, 1.0 - shock_t * 0.7);
		hot = 1.0;
	}
	// SONNENKERN: a ring of white breaks out of the core
	if (pulse > 0.0) {
		float pr = radius * pulse * 1.05;
		if (abs(r - pr) < 1.4) {
			light = max(light, 0.9 * (1.0 - pulse * 0.5));
			hot = 1.0;
		}
	}
	// NACHBRAND: the whole floor flashes and a ring leaves it
	if (flare > 0.0) {
		light = max(light, flare * (0.55 - 0.3 * d) * step(r, radius));
		float fr = radius * (1.0 + (1.0 - flare) * 0.6);
		if (abs(r - fr) < 1.5) {
			light = max(light, flare);
			hot = 1.0;
		}
	}
	light *= alive;
	// the end: the light crumbles in blocks of two pixels
	if (fade > 0.0 && hash(floor(p / 2.0) + 7.0) < fade * 1.15) {
		light *= 0.25;
	}
	// dithered steps: the light comes in four flat tones
	float stepped = floor(clamp(light, 0.0, 1.0) * 4.0 + th) / 4.0;
	if (stepped <= 0.0) {
		discard;
	}
	vec3 tone = mix(deep.rgb, core.rgb, clamp(stepped * 1.3, 0.0, 1.0));
	tone = mix(tone, white.rgb, clamp(hot * stepped * 1.2, 0.0, 1.0));
	COLOR = vec4(tone, stepped);
}
