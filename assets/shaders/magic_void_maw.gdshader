// Leerenschlund (docs/magie_konzept.md, school LEERE): a tear in the ground that opens into the void. A black hole with a ragged lip of
// bruise-dark void flesh, lit only from the upper left, magenta sparks along the lip; round it the ground darkens and spiral arms of violet
// light are wound inwards, faster the closer they get; stars drift in the black. `snap` closes it (the hole shrinks to a seam, a white-violet
// ring breaks out), `feed` flares it when it swallows something. Whole art pixels, Bayer-dithered steps, unshaded (it glows at night).
shader_type canvas_item;
render_mode unshaded;

uniform float radius = 50.0;
uniform float squash = 0.6;
uniform float age = 0.0;
uniform float grow = 0.0;
uniform float snap = 0.0;
uniform float feed = 0.0;
uniform float fade = 0.0;
uniform float seed = 0.0;
uniform vec4 rim : source_color = vec4(0.82, 0.48, 1.0, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.31, 0.85, 1.0);
uniform vec4 abyss : source_color = vec4(0.016, 0.008, 0.035, 1.0);
uniform vec4 flesh : source_color = vec4(0.15, 0.07, 0.29, 1.0);
uniform vec4 white : source_color = vec4(0.96, 0.9, 1.0, 1.0);

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
	float d = r / max(radius, 1.0);
	float alive = 1.0 - fade;
	float open = grow * (1.0 - smoothstep(0.0, 0.55, snap));
	// the hole: ragged, breathing, a little bigger when it feeds
	float hole = radius * (0.34 + 0.06 * feed) * open * (0.82 + 0.3 * noise(vec2(ang * 2.2 + seed, age * 1.8)) + 0.1 * noise(vec2(ang * 8.0, age * 3.0)));
	float seam = abs(e.y) < 1.2 && abs(e.x) < radius * 0.5 * (1.0 - smoothstep(0.5, 1.0, snap)) && snap > 0.3 ? 1.0 : 0.0;
	vec4 col = vec4(0.0);
	if (r < hole) {
		// the black of the void, stars drifting slowly towards the middle
		col = vec4(abyss.rgb, 1.0);
		vec2 star = floor(vec2(ang * 9.0 + age * 0.6, log(r + 1.0) * 6.0 + age * 1.4));
		if (hash(star) > 0.93 && fract(age * 0.7 + hash(star + 3.0)) > 0.4) {
			col.rgb = mix(rim.rgb, white.rgb, hash(star + 7.0));
		}
		if (r > hole - 3.0) {
			// the lip: void flesh, lit only on its upper left side, a cold rim at the very edge
			float lit = clamp(-(e.x + e.y) / max(r, 1.0), 0.0, 1.0);
			col.rgb = mix(flesh.rgb, rim.rgb * 0.8, lit * step(hole - 1.5, r));
			if (hash(p + floor(age * 10.0)) > 0.86) {
				col.rgb = hot.rgb; // magenta sparks run along the lip
			}
		}
	} else if (d < 1.0 + 0.08 * feed) {
		// the pull field: the ground darkens towards the hole, spiral arms of light are wound inwards
		float depth = 1.0 - smoothstep(hole / radius, 1.0, d);
		float dark = depth * 0.62 * open;
		float spiral = fract(ang / 6.2831853 * 3.0 + log(d + 0.04) * 1.6 + age * (0.9 + 1.4 * depth) + seed);
		float arm = 1.0 - smoothstep(0.0, 0.1 + 0.08 * depth, abs(spiral - 0.5));
		float light = arm * (0.25 + 0.75 * depth) * open * (0.75 + 0.5 * feed);
		float stepped = floor(clamp(light, 0.0, 1.0) * 4.0 + bayer(p)) / 4.0;
		float shade = floor(clamp(dark, 0.0, 1.0) * 4.0 + bayer(p + 2.0)) / 4.0;
		if (stepped > 0.0) {
			col = vec4(mix(rim.rgb * 0.6, mix(rim.rgb, white.rgb, depth * 0.5), stepped), clamp(stepped * 1.3, 0.0, 1.0));
			if (hash(p) > 0.97) {
				col.rgb = hot.rgb;
			}
		} else if (shade > 0.0) {
			col = vec4(abyss.rgb, shade * 0.85);
		}
		// the torn edge of the field: a thin broken ring
		if (abs(d - 0.97) < 0.025 && noise(vec2(ang * 7.0, age)) > 0.45) {
			col = vec4(mix(flesh.rgb, rim.rgb, 0.5), 0.7 * open);
		}
	}
	if (seam > 0.5) {
		col = vec4(white.rgb, 1.0); // closing: a white seam
	}
	// the snap: a ring breaks out of the closing hole
	if (snap > 0.3) {
		float ring = (snap - 0.3) / 0.7 * 1.25;
		if (abs(d - ring) < 0.035 + 0.02 * (1.0 - snap)) {
			col = vec4(mix(white.rgb, hot.rgb, smoothstep(0.3, 1.0, snap)), 1.0 - smoothstep(0.6, 1.0, snap));
		}
	}
	col.a *= alive;
	if (col.a <= 0.01) {
		discard;
	}
	COLOR = col;
}
