shader_type canvas_item;
render_mode unshaded;
// SunShadows silhouette twin for LivingTree 2.0 canopy clusters:
// Mirrors the exact whole-pixel 3-frequency wind displacement of canopy_cluster.gdshader!
#include "res://assets/shaders/canopy_cluster.gdshaderinc"

varying float local_y;
varying float feet_y;

void vertex() {
	local_y = VERTEX.y;
	feet_y = (COLOR.r - 0.5) * 1000.0;
}

void fragment() {
	float gust_f;
	float c_dist;
	vec2 wuv = canopy_wind_uv(UV, vec2(textureSize(TEXTURE, 0)), gust_f, c_dist);
	COLOR = vec4(1.0, 1.0, 1.0, step(local_y, feet_y + 0.5) * step(0.55, texture(TEXTURE, wuv).a));
}
