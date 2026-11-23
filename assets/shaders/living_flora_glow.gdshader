shader_type canvas_item;
render_mode unshaded;
#include "res://assets/shaders/living_flora.gdshaderinc"

void vertex() {
	v_world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	v_flip_sign = (MODEL_MATRIX[0][0] < 0.0) ? -1.0 : 1.0;
	modulate_in = COLOR;
}

void fragment() {
	vec2 size = vec2(textureSize(TEXTURE, 0));
	vec4 tex = texture(TEXTURE, living_flora_uv(UV, size)) * modulate_in;
	if (tex.a < 0.02) {
		discard;
	}
	COLOR = tex;
}
