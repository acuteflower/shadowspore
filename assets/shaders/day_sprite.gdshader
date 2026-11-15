shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
uniform float highlight = 1.0;
uniform float sun_side = 1.0; // 0 = no sun-side shading (flat things)
varying vec2 day_position;
void vertex() { day_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }
void fragment() {
	float flip = dFdx(UV.x) < 0.0 ? -1.0 : 1.0;
	COLOR.rgb = day_grade(COLOR.rgb, day_position, highlight);
	if (sun_side > 0.0 && COLOR.a > 0.5 && g_sun_side.y > 0.002) {
		vec2 step_x = vec2(TEXTURE_PIXEL_SIZE.x * flip, 0.0);
		float dl;
		float dr;
		SUN_EDGE(dl, UV, -step_x, 0.0, 1.0)
		SUN_EDGE(dr, UV, step_x, 0.0, 1.0)
		COLOR.rgb = mix(COLOR.rgb, day_sun_side(COLOR.rgb, dl, dr, day_position), sun_side);
	}
}
