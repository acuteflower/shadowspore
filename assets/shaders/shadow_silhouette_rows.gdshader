shader_type canvas_item;
render_mode unshaded;
// SunShadows (docs/sonnenschatten.md): the silhouette of a picture that sways through sway_rows.gdshader (rags, garden plants,
// the crow tree). The same row slide; SunShadows copies the uniforms (wind and time change every frame) from the caster's material.
uniform float pivot_row = 0.0;
uniform float dir = 1.0;
uniform float amount = 4.0;
uniform float flutter = 0.5;
uniform float speed = 2.4;
uniform float cell_w = 12.0;
uniform float wind = 0.0;
uniform float time = 0.0;

// The caster's feet in the sprite's own space come in the draw colour (r = feet_y / 1000 + 0.5): pixels below the feet
// (root flares, the lower rim of rocks and bushes) would be thrown forwards, in front of the caster, so they cast nothing.
varying float local_y;
varying float feet_y;
void vertex() {
	local_y = VERTEX.y;
	feet_y = (COLOR.r - 0.5) * 1000.0;
}
void fragment() {
	vec2 size = vec2(textureSize(TEXTURE, 0));
	vec2 px = UV * size;
	float row = floor(px.y);
	float cell = floor(px.x / cell_w);
	float d = dir > 0.0 ? max(row - pivot_row, 0.0) : max(pivot_row - row, 0.0);
	float ripple = sin(time * speed + row * 0.11 + cell * 1.9) * flutter + sin(time * speed * 2.3 + cell * 3.1) * flutter * 0.45;
	float shift = floor((wind * amount * (0.75 + 0.25 * sin(cell * 2.7 + time * 0.6)) + ripple) * d / 16.0 + 0.5);
	COLOR = vec4(1.0, 1.0, 1.0, step(local_y, feet_y + 0.5) * step(0.55, texture(TEXTURE, UV - vec2(shift / size.x, 0.0)).a));
}
