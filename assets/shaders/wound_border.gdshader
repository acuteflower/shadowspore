shader_type canvas_item;
// The permanent red border of the wounded state: dark red veins creep in from every edge of the screen in pixel-sized, dithered cells,
// crawl slowly and swell with every heartbeat (`beat` 0..1). `grow` 0..1 is how far in (it unrolls when she is hurt, withdraws when she heals),
// `flash` is the jolt at the moment she becomes wounded.

uniform float grow : hint_range(0.0, 1.0) = 0.0;
uniform float beat = 0.0;
uniform float time = 0.0;
uniform float flash = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(float x, float y) {
	vec2 p = vec2(x, y);
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 q = (UV - 0.5) * 2.0;
	float d = pow(pow(abs(q.x), 3.0) + pow(abs(q.y), 3.0), 1.0 / 3.0); // 0 in the middle, 1 at the edge, boxy
	float ang = atan(q.y, q.x * aspect * 0.55);
	float tendrils = vnoise(ang * 4.0 + time * 0.12, time * 0.2) * 0.55 + vnoise(ang * 11.0 - time * 0.08, 3.0) * 0.45;
	float reach = (0.03 + pow(tendrils, 1.6) * 0.2 + beat * 0.035) * grow;
	float inner = d - (1.0 - reach); // > 0 where it has crept in
	vec2 cell = floor(FRAGCOORD.xy / (2.0 / (SCREEN_PIXEL_SIZE.y * 360.0)));
	float band = clamp(inner / 0.1, 0.0, 1.0);
	float on = step(hash(cell), band);
	float rim = step(0.0, inner) * (1.0 - step(0.03, inner));
	vec3 col = mix(vec3(0.34, 0.02, 0.07), vec3(0.74, 0.07, 0.16), clamp(inner * 6.0 + beat * 0.5, 0.0, 1.0));
	col = mix(col, vec3(1.0, 0.38, 0.42), rim * (0.35 + 0.5 * beat));
	float shade = smoothstep(0.6, 1.1, d) * 0.3 * grow; // a faint dark vignette under the veins
	float alpha = max(on * (0.35 + 0.4 * clamp(inner * 5.0, 0.0, 1.0)), shade);
	COLOR = vec4(mix(vec3(0.1, 0.0, 0.03), col, on), alpha * min(1.0, grow * 4.0));
	COLOR.a = clamp(COLOR.a + flash * 0.55 * smoothstep(0.3, 1.0, d), 0.0, 1.0);
	COLOR.rgb = mix(COLOR.rgb, vec3(0.9, 0.12, 0.2), flash * smoothstep(0.3, 1.0, d) * 0.6);
}
