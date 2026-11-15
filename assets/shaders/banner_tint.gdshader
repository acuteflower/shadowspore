shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
varying vec2 daylight_position;
// Sways rows in the wind (like sway_rows.gdshader) and tints teal banner cloth (`#2f8f86` range) to `banner_color`, leaving gold trim, poles, and outlines intact.

uniform float pivot_row = 0.0;
uniform float dir = 1.0;
uniform float amount = 4.0;
uniform float flutter = 0.5;
uniform float speed = 2.4;
uniform float cell_w = 12.0;
uniform float wind = 0.0;
uniform float time = 0.0;
uniform vec4 banner_color : source_color = vec4(0.184, 0.561, 0.525, 1.0);

void vertex() {
	daylight_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 size = vec2(textureSize(TEXTURE, 0));
	vec2 px = UV * size;
	float row = floor(px.y);
	float cell = floor(px.x / cell_w);
	float d = dir > 0.0 ? max(row - pivot_row, 0.0) : max(pivot_row - row, 0.0);
	float ripple = sin(time * speed + row * 0.11 + cell * 1.9) * flutter + sin(time * speed * 2.3 + cell * 3.1) * flutter * 0.45;
	float shift = (amount > 0.0 || flutter > 0.0) ? floor((wind * amount * (0.75 + 0.25 * sin(cell * 2.7 + time * 0.6)) + ripple) * d / 16.0 + 0.5) : 0.0;
	vec4 c = texture(TEXTURE, UV - vec2(shift / size.x, 0.0));
	if (c.a > 0.5 && c.g > c.r * 1.15 && c.b > c.r * 1.15 && c.b > 0.14) {
		float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		c.rgb = clamp(banner_color.rgb * clamp(lum / 0.435, 0.35, 1.45), vec3(0.0), vec3(1.0));
	}
	COLOR = vec4(day_grade(c.rgb, daylight_position, 0.7), c.a);
}
