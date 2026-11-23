shader_type canvas_item;
render_mode unshaded;
#include "res://assets/shaders/canopy_cluster.gdshaderinc"

varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

void fragment() {
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	float gust_f;
	float c_dist;
	vec2 wuv = canopy_wind_uv(UV, tex_size, gust_f, c_dist);
	vec4 tex = texture(TEXTURE, wuv);
	if (tex.a < 0.01) {
		discard;
	}
	COLOR = tex * v_modulate;
}
