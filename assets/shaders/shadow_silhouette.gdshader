shader_type canvas_item;
render_mode unshaded;
// SunShadows (docs/sonnenschatten.md): one sheared copy of a sprite in the shadow buffer. Only solid pixels cast a
// shadow (baked contact shadows and soft glow halos are half transparent and cast none). Hard-edged, like pixel art.
// The caster's feet in the sprite's own space come in the draw colour (r = feet_y / 1000 + 0.5): pixels below the feet
// (root flares, the lower rim of rocks and bushes) would be thrown forwards, in front of the caster, so they cast nothing.
varying float local_y;
varying float feet_y;
void vertex() {
	local_y = VERTEX.y;
	feet_y = (COLOR.r - 0.5) * 1000.0;
}
void fragment() {
	COLOR = vec4(1.0, 1.0, 1.0, step(local_y, feet_y + 0.5) * step(0.55, texture(TEXTURE, UV).a));
}
