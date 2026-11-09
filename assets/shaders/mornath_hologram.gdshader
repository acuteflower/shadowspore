shader_type canvas_item;
render_mode unshaded;
// The glitched hologram of Mornath in the middle of the boss arena (MornathHologram): a SubViewport with the real SkyCleaverRig is shown through this.
// Everything happens in whole texels of the viewport: rows slip sideways in bands, the colours split into a magenta and a teal ghost, scanlines crawl,
// the picture is written bottom-up when it appears (`appear`) and tears when it is touched or about to go (`glitch`). Unshaded: it is light, not stone.

uniform float clock = 0.0;     // own animation clock (seconds)
uniform float appear : hint_range(0.0, 1.0) = 1.0; // 0 = nothing, 1 = fully there (the picture is written from the feet up)
uniform float glitch : hint_range(0.0, 1.0) = 0.0; // 0 = the quiet idle tears, 1 = falling apart
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint_a : source_color = vec4(0.42, 0.92, 1.0, 1.0);   // cold teal
uniform vec4 tint_b : source_color = vec4(0.95, 0.35, 0.95, 1.0);  // magenta ghost

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 size = vec2(textureSize(TEXTURE, 0));
	vec2 px = UV * size;
	float row = floor(px.y);
	float tick = floor(clock * 9.0);

	// bands of rows slip sideways, a few at rest, many when it is touched
	float band_h = 3.0 + floor(hash11(tick * 3.7) * 6.0);
	float band = floor(row / band_h);
	float slip_roll = hash21(vec2(band, tick));
	float slip_gate = 0.93 - 0.55 * glitch;
	float slip = 0.0;
	if (slip_roll > slip_gate) {
		slip = (hash21(vec2(band + 9.0, tick)) - 0.5) * (6.0 + 22.0 * glitch);
	}
	// a slow wobble the whole picture has
	slip += floor(sin(row * 0.21 + clock * 2.3) * 1.2 + 0.5) * (0.6 + glitch);
	slip = floor(slip + 0.5);

	// chroma split: the magenta ghost leans one way, the teal the other
	float split = 1.0 + floor(glitch * 4.0 + 0.5) + step(0.96, hash11(tick * 1.9)) * 3.0;
	vec2 uv_c = vec2((px.x + slip) / size.x, UV.y);
	float c_teal = texture(TEXTURE, uv_c + vec2(split / size.x, 0.0)).a;
	float c_mag = texture(TEXTURE, uv_c - vec2(split / size.x, 0.0)).a;
	vec4 here = texture(TEXTURE, uv_c);

	float lum = dot(here.rgb, vec3(0.3, 0.5, 0.2));
	// the rig is dark flesh and bright veins: lift it into light, brightest where the rig is bright
	float body = clamp(0.4 + lum * 1.0, 0.0, 1.0);
	vec3 col = vec3(0.0);
	col += tint_a.rgb * c_teal * body * 0.8;
	col += tint_b.rgb * c_mag * body * 0.2;
	col = mix(col, vec3(0.85, 1.0, 1.0), clamp((lum - 0.7) * 2.5, 0.0, 1.0) * here.a * 0.5); // hot spots (eyes, core) go white
	float alpha = clamp(max(here.a, max(c_teal, c_mag) * 0.6), 0.0, 1.0);

	// scanlines: every second row dimmer, a bright bar travelling down
	float line = mod(row, 2.0) < 1.0 ? 1.0 : 0.62;
	float bar_pos = fract(clock * 0.23) * (size.y + 24.0) - 12.0;
	float bar = smoothstep(7.0, 0.0, abs(px.y - bar_pos));
	col *= line;
	col += tint_a.rgb * bar * 0.28 * here.a;
	alpha *= mix(0.62, 0.86, 0.5 + 0.5 * sin(clock * 1.7)) + bar * 0.2;

	// flicker: short drop-outs, the whole picture
	float flick = step(0.93, hash11(floor(clock * 17.0) + 5.0));
	alpha *= 1.0 - flick * (0.45 + 0.4 * glitch);
	// pixel dust: single texels in the picture blink out
	float dust = step(0.985 - 0.2 * glitch, hash21(floor(px) + vec2(tick, 3.0)));
	alpha *= 1.0 - dust;

	// written from the feet up (the viewport's bottom is the picture's feet): a bright front, ragged by rows
	float written = size.y - px.y; // 0 at the bottom
	float ragged = hash21(vec2(row, 4.0)) * 4.0;
	if (appear < 0.999) {
		float gone = step(0.0, written + ragged - (appear * (size.y + 10.0)));
		alpha *= 1.0 - gone;
		float lead = smoothstep(5.0, 0.0, abs(written + ragged - (appear * (size.y + 10.0))));
		col += tint_a.rgb * lead * 0.9;
		alpha = max(alpha, lead * 0.55 * step(0.0, appear) * step(appear, 0.999));
	}
	COLOR = vec4(col * (1.0 + 0.25 * night), alpha);
}
