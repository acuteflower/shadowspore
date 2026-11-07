shader_type canvas_item;
render_mode unshaded;
// The shadow face come alive (src/ui/void_title.gd composes the letters from assets/ui/void_face_*.png, tools/art_void_face.py makes them).
// The atlas carries R = the letter, G = signed distance to its edge (128 = edge), B = the spine of the thick strokes. Drawn here, on the art pixel grid:
//  - flesh: black void flesh, a little lighter towards the spine; a cold violet rim light on the edges that face the top left, a dim one on the others
//  - veins: the spine glows magenta-white and beats (the shadow creatures' double pulse, running outwards along the word)
//  - glimmer: small stars flare up and die on the letters, an aura of violet dust breathes round them
//  - morph: the whole shape is displaced by slow noise in whole pixels (more at the bottom, where it melts), and tendrils drip down from every lower edge
//  - reveal: the letters condense out of smoke from left to right (first a ghost of dither, then flesh); dissolve: they rise and crumble upwards
//  - glitch: rows slip sideways and the colours split, like the shadow creatures
// Strength knobs: power (0..1: how alive), drip (tendrils), reveal (0..1.4), dissolve (0..1), glitch (0..1).

uniform sampler2D face : filter_nearest, repeat_disable;
uniform vec2 tex_size = vec2(256.0, 128.0);
uniform float time = 0.0;
uniform float night = 1.0;
uniform float sdf_range = 12.0;
uniform float margin = 26.0;
uniform float reveal = 1.4;
uniform float dissolve = 0.0;
uniform float glitch = 0.0;
uniform float power = 1.0;
uniform float drip = 1.0;
uniform float seed = 0.0;
uniform float detail = 1.0; // how big the morphing is: 1 for the big face, about 0.3 for the small ones (their strokes are thin)
uniform float ink = 0.0; // 0..1: blacker: a black outline round the letters, a dimmer rim (for words that sit on a bright or busy picture, e.g. the boss bar)
uniform float goo = 1.0; // 1 for the big face, less for the small ones: thickness of the melting tendrils

#include "res://assets/shaders/map_veil.gdshaderinc"

const vec3 HOT = vec3(1.0, 0.84, 0.96);

vec4 tap(vec2 q) {
	if (q.x < 0.0 || q.y < 0.0 || q.x >= tex_size.x || q.y >= tex_size.y) return vec4(0.0, 0.0, 0.0, 1.0);
	return texture(face, (floor(q) + 0.5) / tex_size);
}

// the letter is its signed distance field cut at a level that breathes: the goo swells and shrinks, edges wobble
float shape_at(vec2 q, float w) {
	return (tap(q).g - 0.5) * 2.0 * sdf_range + w;
}

#define inside(q) step(0.0, shape_at((q), wob))

// the double pulse of the shadow creatures (lub-dub), 0..1
float heart(float t) {
	float c = fract(t * 0.8);
	float a = (c - 0.06) / 0.06;
	float b = (c - 0.27) / 0.07;
	return clamp(exp(-a * a) + 0.7 * exp(-b * b), 0.0, 1.0);
}

void fragment() {
	vec2 p = floor(UV * tex_size);
	vec2 P = p + 0.5;
	float span_x = max(tex_size.x - 2.0 * margin, 1.0);
	float span_y = max(tex_size.y - 2.0 * margin, 1.0);
	float xn = clamp((P.x - margin) / span_x, 0.0, 1.0);
	float yn = clamp((P.y - margin) / span_y, 0.0, 1.0);

	// --- morph: displace the sampling in whole pixels, more towards the bottom
	float melt = power * detail * (0.5 + 1.5 * yn);
	vec2 nw = vec2(fbm(P * 0.05 + vec2(time * 0.45, seed)), fbm(P * 0.05 + vec2(seed + 5.0, -time * 0.4))) - 0.5;
	vec2 sp = p + floor(nw * melt * 2.8 + 0.5);
	float row = floor(P.y / 2.0);
	float tk = floor(time * 18.0);
	float g = glitch * step(0.78, hash21(vec2(row, tk + seed)));
	sp.x += floor(g * (hash21(vec2(row, tk + 9.0)) - 0.5) * 34.0);
	float lift = floor(dissolve * dissolve * 34.0 * (0.4 + hash21(vec2(floor(P.x / 2.0), 3.0 + seed))));
	sp.y += lift; // sampling from below makes everything rise

	vec4 m = tap(sp);
	float wob = 0.55 * detail + power * detail * ((vnoise(P * 0.09 + vec2(time * 0.55, seed * 2.0)) - 0.5) * 3.4 + (vnoise(P * 0.21 + vec2(-time * 0.9, seed)) - 0.5) * 1.3);
	float d = shape_at(sp, wob); // + inside, - outside
	float ins = step(0.0, d);

	// --- reveal and dissolve: smoke in, smoke out
	float nr = fbm(P * 0.07 + vec2(seed * 3.1, 1.7));
	float th = reveal * 1.25 - xn * 0.45;
	float shown = step(nr, th);
	float ghost = step(nr, th + 0.2) - shown;
	float nd = fbm(P * 0.06 + vec2(4.0, seed));
	shown *= 1.0 - step(nd, dissolve * 1.3 - yn * 0.25 * dissolve);

	float beat = heart(time - P.x * 0.007);
	vec4 col = vec4(0.0);

	if (ins > 0.5) {
		if (shown > 0.5) {
			float up = inside(sp + vec2(0.0, -1.0));
			float left = inside(sp + vec2(-1.0, 0.0));
			float down = inside(sp + vec2(0.0, 1.0));
			float right = inside(sp + vec2(1.0, 0.0));
			vec3 c = VOID0;
			float depth = smoothstep(0.5, 3.5, d);
			if (depth * 0.75 > bayer(p) + 0.1) c = VOID1; // black flesh, a little less black towards the middle of a stroke
			// veins: the spine, and a little light seeping into the flesh beside it
			float spine = m.b;
			float near_spine = max(max(tap(sp + vec2(1.0, 0.0)).b, tap(sp + vec2(-1.0, 0.0)).b), max(tap(sp + vec2(0.0, 1.0)).b, tap(sp + vec2(0.0, -1.0)).b));
			if (near_spine > 0.5 && spine < 0.5 && bayer(p + 2.0) < 0.35 + 0.4 * beat) c = mix(c, VIO5, 0.7);
			// rim light
			bool wet = inside(sp + vec2(0.0, -2.0)) < 0.5 || inside(sp + vec2(-2.0, 0.0)) < 0.5 || inside(sp + vec2(-1.0, -2.0)) < 0.5;
			if (up < 0.5 || left < 0.5) c = mix(VIO6, VIO7, beat * 0.6) * (1.0 - 0.35 * ink);
			else if (down < 0.5 || right < 0.5) c = VIO5 * (0.5 + 0.3 * beat) * (1.0 - 0.5 * ink);
			else if (wet && bayer(p + 5.0) < 0.7) c = mix(c, VIO8, 0.55); // the wet shine just inside the rim
			if (spine > 0.5) c = mix(MAGENTA * 0.85, HOT, beat);
			col = vec4(c, 1.0);
		} else if (ghost > 0.5 && bayer(p) < 0.55) {
			col = vec4(mix(VOID3, VIO5, hash21(p + seed)), 0.7);
		}
	} else if (shown > 0.5 || ghost > 0.5) {
		// --- goo melting down from every lower edge: a stem and a drop at its end
		float cell = floor(P.x * 0.25);
		float lx = mod(floor(P.x), 4.0);
		float colh = hash21(vec2(cell, 11.0 + seed));
		float len = 0.0;
		if (colh > 0.6) {
			len = (7.0 + 24.0 * hash21(vec2(cell, 5.0))) * (0.55 + 0.45 * sin(time * (0.7 + colh) + colh * 20.0)) * drip;
		}
		float dj = 0.0;
		if (len > 1.0) {
			for (int j = 1; j <= 36; j++) {
				if (float(j) > len + 2.0) break;
				if (inside(sp - vec2(0.0, float(j))) > 0.5) {
					dj = float(j);
					break;
				}
			}
		}
		float drop = goo > 0.5 ? 3.0 : 2.0;
		bool stem = goo > 0.5 ? (lx > 0.5 && lx < 2.5) : (lx > 0.5 && lx < 1.5);
		bool bulb = dj > len - drop + 0.5 && dj <= len + 1.0 && (goo > 0.5 ? lx < 3.5 : lx > 0.5 && lx < 2.5);
		if (dj > 0.0 && shown > 0.5 && dj <= len + 1.0 && (stem || bulb)) {
			vec3 c = mix(VOID1, VOID3, 0.5);
			if (lx < 1.5 && (bulb || stem)) c = VIO5; // the lit left edge
			if (bulb) c = mix(c, VIO6, 0.55);
			if (dj > len - 0.5 && lx < 2.5) c = mix(VIO7, HOT, 0.35 * beat); // the glimmering bottom of the drop
			col = vec4(c, 1.0);
		} else {
			// --- the aura: violet dust that breathes
			float dout = -d;
			float aura = (1.0 - smoothstep(0.0, 9.0, dout)) * power * (0.5 + 0.3 * beat) * (1.0 - 0.6 * ink);
			aura = aura * aura * 1.6; // dense close to the letters, dust further out: the black letters stand against a violet glow
			if (aura > bayer(p) * 0.9 + 0.08) col = vec4(mix(VIO5, VIO6, clamp(1.0 - dout / 5.0, 0.0, 1.0)), (0.3 + 0.35 * clamp(1.0 - dout / 3.0, 0.0, 1.0)) * shown);
			if (ink > 0.0 && dout < 2.4 && shown > 0.5) col = vec4(VOID0, 0.92 * ink); // the black round the letters
		}
	}

	// --- glimmer: stars that flare up on the letters and die
	vec2 cellg = floor(P / 13.0);
	float hs = hash21(cellg + seed + 40.0);
	float ph = fract(time * (0.35 + hs * 0.5) + hs * 7.0);
	if (hs > 0.42 && ph < 0.12 && shown > 0.5) {
		vec2 c0 = cellg * 13.0 + floor(vec2(hash21(cellg + 3.0), hash21(cellg + 6.0)) * 13.0);
		if (tap(c0).g > 118.0 / 255.0) {
			vec2 dd = p - c0;
			float env = sin(ph / 0.12 * 3.14159265);
			if (dd == vec2(0.0)) col = vec4(HOT, 1.0);
			else if ((dd.x == 0.0 || dd.y == 0.0) && max(abs(dd.x), abs(dd.y)) <= (env > 0.6 ? 3.0 : 1.0)) col = vec4(mix(VIO7, HOT, env), env);
		}
	}

	// --- glitch: a ghost of the letters in magenta and teal, a pixel and a half to the sides
	if (g > 0.0 && col.a < 0.5) {
		if (inside(sp + vec2(-4.0, 0.0)) > 0.5) col = vec4(MAGENTA, 0.55);
		else if (inside(sp + vec2(4.0, 0.0)) > 0.5) col = vec4(0.3, 0.88, 0.82, 0.5);
	}
	COLOR = col;
}
