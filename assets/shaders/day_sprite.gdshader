shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
varying vec2 day_position;
void vertex() { day_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }
void fragment() { COLOR.rgb = day_grade(COLOR.rgb, day_position, 1.0); }
