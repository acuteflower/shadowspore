shader_type canvas_item;
render_mode unshaded;
global uniform float g_sun; // 0..1 sun height (DayNight)
// The glowing pixels of luminous plants (blooms, mushrooms, glyphs), drawn above the ground without
// the night tint, so they shine against the dark. At night they brighten and breathe, each plant
// out of step. By day they simply repeat the pixels underneath.

uniform float night = 0.0; // 0 day .. 1 night (set by DayNight)

varying vec2 world_px;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float pulse = 0.5 + 0.5 * sin(TIME * 1.4 + hash(floor(world_px / 16.0)) * 6.2831);
	c.rgb *= 1.0 + night * (0.08 + 0.2 * pulse);
	if (c.a > 0.0 && g_sun > 0.0) { // by day the sleeping buds wink with a pale glint
		vec2 px = floor(world_px);
		float tw = step(0.8, hash(px + 5.0)) * step(0.6, fract(TIME * 0.3 + hash(px)));
		c.rgb = mix(c.rgb, vec3(1.0, 0.97, 0.85), 0.7 * g_sun * tw);
	}
	COLOR = c;
}
