shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
varying vec2 daylight_position;

// Signed pixel displacement at the tips; root remains at the sprite's foot.
// The caller supplies current- and actor-driven bend on plant rows only.
uniform float bend = 0.0;
uniform vec2 current_push = vec2(0.0);

void vertex() {
	daylight_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
				float root_factor = clamp(-VERTEX.y / 28.0, 0.0, 1.0);
				VERTEX += round((vec2(clamp(bend, -2.0, 2.0), 0.0) + current_push) * root_factor);
}

void fragment() { COLOR.rgb = day_grade(COLOR.rgb, daylight_position, 0.7); }
