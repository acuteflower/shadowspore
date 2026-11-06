shader_type canvas_item;
// Rows of a picture slide sideways in the wind, in whole art pixels, so a sprite sways without losing its pixel look: the farther a row is from the
// pivot row, the more it moves. `dir` 1 = the rows below the pivot move (rags hung from a line), -1 = the rows above it (plants rooted at the pivot).
// A little restless ripple is always there, in clumps of `cell_w` columns that are out of step with each other (each rag, each tuft on its own).
// `wind` is WorldWind's x component, `time` the game's own clock (it stops when the game is paused). Used by HutYard.

uniform float pivot_row = 0.0;
uniform float dir = 1.0;
uniform float amount = 4.0; // art pixels per 16 rows of distance at a wind of 1
uniform float flutter = 0.5; // the ripple that is always there, same unit
uniform float speed = 2.4;
uniform float cell_w = 12.0;
uniform float wind = 0.0;
uniform float time = 0.0;

void fragment() {
	vec2 size = vec2(textureSize(TEXTURE, 0));
	vec2 px = UV * size;
	float row = floor(px.y);
	float cell = floor(px.x / cell_w);
	float d = dir > 0.0 ? max(row - pivot_row, 0.0) : max(pivot_row - row, 0.0);
	float ripple = sin(time * speed + row * 0.11 + cell * 1.9) * flutter + sin(time * speed * 2.3 + cell * 3.1) * flutter * 0.45;
	float shift = floor((wind * amount * (0.75 + 0.25 * sin(cell * 2.7 + time * 0.6)) + ripple) * d / 16.0 + 0.5);
	COLOR = texture(TEXTURE, UV - vec2(shift / size.x, 0.0));
}
