shader_type canvas_item;
render_mode unshaded;
// The loading screen's backdrop: the shared abyss (abyss.gdshaderinc) surrounding a narrow floating
// ridge of luminous land (`horizon`). Beneath the dashed crystal-violet lip hangs a frayed stone and
// root cliff silhouette that drifts past with `travel`. When the waystone sanctuary awakens, a soft
// dithered teal-violet halo blooms around `sanctuary_x`. Opens and closes via `veil_opening`.

uniform vec2 view_size = vec2(640.0, 360.0);
uniform float time = 0.0;
uniform float night = 1.0;
uniform float opening = 1.0;
uniform float travel = 0.0;
uniform float horizon = 208.0;
uniform float sanctuary_x = 434.0;
uniform float sanctuary_glow = 0.0;

const vec3 TEAL_GLOW = vec3(0.471, 0.957, 0.902); // #78f4e6

#include "res://assets/shaders/map_veil.gdshaderinc"
#include "res://assets/shaders/abyss.gdshaderinc"

void fragment() {
	vec2 P = floor(UV * view_size) + 0.5;
	vec2 wp = P - 0.5;
	vec2 L = floor(P - (view_size - vec2(640.0, 360.0)) * 0.5);
	float glow = 1.0 + 0.28 * abyss_beat(time);

	float gx = L.x + floor(travel);
	float edge_jitter = (vnoise(vec2(gx * 0.07, 3.0)) - 0.5) * 26.0;
	float side = smoothstep(152.0, 236.0, abs(L.x - 320.0) + edge_jitter);
	float h = max(L.y - horizon, 0.0) * 1.45 + max(horizon - L.y, 0.0) * 0.92 + side * 125.0;
	vec3 col = abyss(wp + vec2(floor(travel * 0.45), 0.0), h, glow);

	// Soft dithered sanctuary aura around the awakening waystone
	if (sanctuary_glow > 0.001) {
		vec2 d_sanc = (L - vec2(sanctuary_x, horizon - 26.0)) / vec2(68.0, 62.0);
		float halo = exp(-dot(d_sanc, d_sanc) * 1.65) * sanctuary_glow;
		float band = floor(halo * 4.0 + bayer(wp)) / 4.0;
		if (band > 0.0) {
			vec3 aura = mix(VIO6, mix(VIO8, TEAL_GLOW, 0.55), clamp(halo * 1.2, 0.0, 1.0));
			col = mix(col, aura * glow, clamp(band * 0.55, 0.0, 0.65));
		}
	}

	// Floating ridge lip & frayed stone/root cliff underside
	float lip_y = L.y - horizon;
	float span = 1.0 - side;
	if (span > 0.06) {
		float arch = pow(clamp(span, 0.0, 1.0), 0.65);
		float rough = vnoise(vec2(gx * 0.065, 7.1)) * 7.5 + vnoise(vec2(gx * 0.21, 2.3)) * 3.5;
		float root_hang = pow(vnoise(vec2(gx * 0.34, 11.7)), 3.0) * 6.0;
		float cliff_depth = (3.5 + rough + root_hang) * arch;

		if (lip_y >= -1.0 && lip_y < 0.0) {
			// Sparse 1px moss/crystal sparkles just on top of the ridge
			if (span > 0.3 && hash21(vec2(gx, 19.0)) > 0.86) {
				col = mix(VIO6, VIO8, hash21(vec2(gx, 31.0))) * glow;
			}
		} else if (lip_y >= 0.0 && lip_y < 1.0) {
			// Luminous dashed ridge lip (brightens with teal leyline glints near sanctuary)
			float dash = vnoise(vec2(gx * 0.38, time * 0.18));
			if (dash > 0.24 && bayer(wp) < span * 1.15) {
				float near_sanc = exp(-abs(L.x - sanctuary_x) * 0.028) * sanctuary_glow;
				vec3 lip_col = mix(VIO6, VIO8, vnoise(vec2(gx * 0.85, 1.0)));
				lip_col = mix(lip_col, mix(TEAL_GLOW, vec3(1.0), 0.35), clamp(near_sanc * 0.85, 0.0, 1.0));
				col = lip_col * glow;
			}
		} else if (lip_y >= 1.0 && lip_y < cliff_depth + 2.0) {
			float fade_bottom = clamp((cliff_depth - lip_y + 1.5) / 3.0, 0.0, 1.0);
			if (bayer(wp) < fade_bottom * clamp(span * 1.3, 0.0, 1.0)) {
				float rock = vnoise(vec2(gx * 0.16, lip_y * 0.32));
				col = lip_y < 2.5 ? VOID2 : (rock > 0.58 ? VOID1 : VOID0);
				// Occasional glowing violet crystal seam inside the rock face
				float seam = abs(vnoise(vec2(gx * 0.09, lip_y * 0.18)) - 0.5);
				if (seam < 0.026 && lip_y > 1.5 && lip_y < cliff_depth - 1.5 && span > 0.45) {
					float pulse = 0.65 + 0.35 * sin(time * 2.1 + gx * 0.05);
					col = mix(VIO5, TEAL_GLOW, sanctuary_glow * 0.45) * pulse;
				}
			}
		}
	}

	COLOR = veil_opening(col, P, view_size, view_size * 0.5 + vec2(0.0, -10.0), opening);
}
