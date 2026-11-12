shader_type canvas_item;
render_mode unshaded;
// The loading screen's backdrop: only the abyss (abyss.gdshaderinc, the same void as the world's edge and the main menu), glowing brightest along a
// thin path of land the cast walks on, its dashed lip drifting past with the walk (`travel`). Opens and closes with the world map's violet wipe
// (`opening` 0..1, map_veil.gdshaderinc).

uniform vec2 view_size = vec2(640.0, 360.0);
uniform float time = 0.0;
uniform float night = 1.0;
uniform float opening = 1.0;
uniform float travel = 0.0;
uniform float horizon = 212.0;

#include "res://assets/shaders/map_veil.gdshaderinc"
#include "res://assets/shaders/abyss.gdshaderinc"

void fragment() {
	vec2 P = floor(UV * view_size) + 0.5;
	vec2 wp = P - 0.5;
	vec2 L = P - (view_size - vec2(640.0, 360.0)) * 0.5; // stage coordinates (centred when the window is wider)
	float glow = 1.0 + 0.3 * abyss_beat(time);
	// the path: a thin strip of land, fading out to the sides
	float side = smoothstep(150.0, 250.0, abs(L.x - 320.0) + (vnoise(vec2(L.x + travel, 3.0) * 0.08) - 0.5) * 30.0);
	float h = max(L.y - horizon, 0.0) * 1.4 + max(horizon - L.y, 0.0) * 0.9 + side * 120.0;
	vec3 col = abyss(wp + vec2(floor(travel * 0.5), 0.0), h, glow);
	float lip_y = L.y - horizon;
	if (lip_y >= 0.0 && lip_y < 1.0 && side < 0.85) {
		vec2 g = vec2(floor(L.x + travel), 0.0);
		if (vnoise(g * 0.4 + time * 0.2) > 0.3 && bayer(wp) > side) {
			col = mix(VIO6, VIO8, vnoise(g * 0.9)) * glow;
		}
	} else if (lip_y >= 1.0 && lip_y < 4.0 && side < 0.6) {
		col = VOID0; // the dark under the lip
	}
	COLOR = veil_opening(col, P, view_size, view_size * 0.5 + vec2(0.0, -10.0), opening);
}
