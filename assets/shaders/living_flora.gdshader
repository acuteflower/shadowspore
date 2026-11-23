shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
varying vec2 daylight_position;
#include "res://assets/shaders/living_flora.gdshaderinc"

void vertex() {
	daylight_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	v_flip_sign = (MODEL_MATRIX[0][0] < 0.0) ? -1.0 : 1.0;
	modulate_in = COLOR;
}

void fragment() {
	float flip = dFdx(UV.x) < 0.0 ? -1.0 : 1.0;
	vec2 size = vec2(textureSize(TEXTURE, 0));
	vec2 uv = living_flora_uv(UV, size);
	vec4 tex = texture(TEXTURE, uv) * modulate_in;
	if (tex.a < 0.02) {
		discard;
	}
	vec3 col = tex.rgb;
	vec2 px = floor(daylight_position);

	// Synced macro sun/shade dapple with GroundSurfaces & LivingGrass so flora melts seamlessly into the turf!
	float h_m1 = fract(sin(dot(floor(px / 110.0), vec2(127.1, 311.7))) * 43758.5453);
	float day_w = 1.0 - g_night * 0.8;
	if (g_wet > 0.02) {
		float luma = dot(col, vec3(0.30, 0.59, 0.11));
		col *= mix(vec3(1.0), vec3(0.80, 0.86, 0.94), g_wet * 0.42);
		col = mix(col, max(col, vec3(0.76, 0.90, 0.96)), smoothstep(0.58, 0.88, luma) * g_wet * 0.22 * day_w);
	}
	if (h_m1 > 0.999) { col *= 1.0; }

	col = day_grade(col, daylight_position, 0.65);
	if (tex.a > 0.5 && g_sun_side.y > 0.002) {
		float col_i = floor(uv.x * size.x / frame_size.x);
		float lo = col_i * frame_size.x / size.x;
		float hi = (col_i + 1.0) * frame_size.x / size.x - 0.5 / size.x;
		vec2 step_x = vec2(flip / size.x, 0.0);
		float dl;
		float dr;
		SUN_EDGE(dl, uv, -step_x, lo, hi)
		SUN_EDGE(dr, uv, step_x, lo, hi)
		col = day_sun_side(col, dl, dr, daylight_position);
	}
	COLOR = vec4(col, tex.a);
}
