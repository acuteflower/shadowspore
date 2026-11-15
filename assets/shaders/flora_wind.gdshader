shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
varying vec2 daylight_position;
#include "res://assets/shaders/flora_wind.gdshaderinc"
void vertex() {
	daylight_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	modulate_in = COLOR;
}
void fragment() {
	float flip = dFdx(UV.x) < 0.0 ? -1.0 : 1.0;
	vec2 size = vec2(textureSize(TEXTURE, 0));
	vec2 uv = wind_uv(UV, size);
	COLOR = texture(TEXTURE, uv) * modulate_in;
	COLOR.rgb = day_grade(COLOR.rgb, daylight_position, 0.7);
	if (COLOR.a > 0.5 && g_sun_side.y > 0.002) { // the sun side, kept inside this plant's frame
		float col = floor(uv.x * size.x / frame_size.x);
		float lo = col * frame_size.x / size.x;
		float hi = (col + 1.0) * frame_size.x / size.x - 0.5 / size.x;
		vec2 step_x = vec2(flip / size.x, 0.0);
		float dl;
		float dr;
		SUN_EDGE(dl, uv, -step_x, lo, hi)
		SUN_EDGE(dr, uv, step_x, lo, hi)
		COLOR.rgb = day_sun_side(COLOR.rgb, dl, dr, daylight_position);
	}
}
