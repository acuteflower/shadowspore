shader_type canvas_item;
// The HUD grows in: every vine of it unrolls from where it is rooted (a screen edge, the hotbar's ends) as a ragged, dithered wave, and the
// newest growth glows teal for a moment. Set per widget by Hud.open(); `reveal` runs 0 .. 1, `origin` is in viewport 0 .. 1.

uniform vec2 origin = vec2(0.5, 1.0);
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform float reach = 0.9; // how far the wave travels, in screen heights

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = FRAGCOORD.xy * SCREEN_PIXEL_SIZE;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 q = (uv - origin) * vec2(aspect, 1.0);
	vec2 cell = floor(uv * vec2(aspect, 1.0) * 180.0); // 2 px cells of the 360 px high canvas: crisp, pixel-sized ragged edge
	float d = length(q) + (hash(cell) - 0.5) * 0.06;
	float k = reveal * (reach + 0.12) - d; // > 0 where it has grown
	if (k < hash(cell + 7.0) * 0.03) {
		discard;
	}
	float glow = smoothstep(0.07, 0.0, k) * (1.0 - step(1.0, reveal));
	COLOR.rgb = mix(COLOR.rgb, vec3(0.62, 0.96, 0.9), glow * 0.75);
}
