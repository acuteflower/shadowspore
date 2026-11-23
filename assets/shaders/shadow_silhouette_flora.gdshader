shader_type canvas_item;
render_mode unshaded;
// SunShadows (docs/sonnenschatten.md): the silhouette of a small plant that bends in the wind through flora_wind.gdshader.
// Same row slide (same globals, same uniforms copied from the plant's own material), so the shadow bends with the plant.
#include "res://assets/shaders/flora_wind.gdshaderinc"
// The caster's feet in the sprite's own space come in the draw colour (r = feet_y / 1000 + 0.5): pixels below the feet
// (root flares, the lower rim of rocks and bushes) would be thrown forwards, in front of the caster, so they cast nothing.
varying float local_y;
varying float feet_y;
void vertex() {
	local_y = VERTEX.y;
	feet_y = (COLOR.r - 0.5) * 1000.0;
	v_world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
}
void fragment() {
	COLOR = vec4(1.0, 1.0, 1.0, step(local_y, feet_y + 0.5) * step(0.55, texture(TEXTURE, wind_uv(UV, vec2(textureSize(TEXTURE, 0)))).a));
}
