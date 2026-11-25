shader_type canvas_item;
render_mode unshaded;

// Pixel-locked, 3/4-perspective sword slash sheet renderer (Shadowspore 2.0).
// Draws on an unrotated integer-snapped quad so every fragment aligns strictly to
// the 640x360 game pixel grid (zero rotated mixels!) while projecting the handcrafted
// pixel-art animation frames cleanly into any 360-degree aim & 3/4 perspective plane.

uniform sampler2D sheet_tex : filter_nearest, repeat_disable;
uniform vec2 canvas_px = vec2(128.0, 128.0);
uniform vec2 frame_size = vec2(96.0, 96.0);
uniform vec2 sheet_size = vec2(960.0, 96.0);
uniform vec2 frame_pivot = vec2(48.0, 48.0);
uniform float frame_index = 0.0;
uniform vec2 inv_x = vec2(1.0, 0.0);
uniform vec2 inv_y = vec2(0.0, 1.0);
uniform vec2 pivot_shift = vec2(0.0, 0.0);
uniform int depth_pass = 0; // 0 = full, -1 = back half (rel.y < 0) behind player, 1 = front half (rel.y >= 0)
uniform float hit_flash = 0.0;
uniform float opacity = 1.0;

uniform bool use_custom_palette = false;
uniform vec4 col_dark : source_color = vec4(0.141, 0.173, 0.329, 0.941);
uniform vec4 col_shadow : source_color = vec4(0.337, 0.447, 0.682, 0.980);
uniform vec4 col_mid : source_color = vec4(0.620, 0.753, 0.933, 1.0);
uniform vec4 col_core : source_color = vec4(0.886, 0.949, 1.0, 1.0);
uniform vec4 col_edge : source_color = vec4(1.0, 1.0, 1.0, 1.0);

vec4 sample_frame_px(vec2 local_px, float frame_x) {
	if (local_px.x < 0.0 || local_px.y < 0.0 || local_px.x >= frame_size.x || local_px.y >= frame_size.y) {
		return vec4(0.0);
	}
	vec2 tex_px = floor(local_px) + vec2(frame_x + 0.5, 0.5);
	return texture(sheet_tex, tex_px / sheet_size);
}

void fragment() {
	// Lock sampling strictly to the 1x1 art-pixel grid of the canvas (zero mixels).
	vec2 px = floor(UV * canvas_px) + 0.5 - canvas_px * 0.5;
	vec2 rel = px - pivot_shift;
	if (depth_pass < 0 && rel.y >= 0.0) {
		discard;
	}
	if (depth_pass > 0 && rel.y < 0.0) {
		discard;
	}
	vec2 local = vec2(dot(inv_x, rel), dot(inv_y, rel)) + frame_pivot;
	float frame_x = floor(frame_index + 0.001) * frame_size.x;

	vec4 c = sample_frame_px(local, frame_x);

	// Preserve delicate 1px curved wind-threads & star glints when compressed by 3/4 squash:
	// only probe sub-pixel neighbors along the compressed screen Y axis if the center tap missed.
	if (c.a < 0.05) {
		vec2 dy_step = vec2(inv_x.y, inv_y.y);
		if (dot(dy_step, dy_step) > 1.12) {
			vec4 ca = sample_frame_px(local + dy_step * 0.28, frame_x);
			vec4 cb = sample_frame_px(local - dy_step * 0.28, frame_x);
			c = (ca.a >= cb.a) ? ca : cb;
		}
	}

	if (c.a < 0.05) {
		discard;
	}

	vec4 out_col = c;
	if (use_custom_palette) {
		float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		vec4 mapped = col_edge;
		if (lum < 0.31) {
			mapped = col_dark;
		} else if (lum < 0.58) {
			mapped = col_shadow;
		} else if (lum < 0.83) {
			mapped = col_mid;
		} else if (lum < 0.97) {
			mapped = col_core;
		}
		out_col = vec4(mapped.rgb, c.a * mapped.a);
	}

	if (hit_flash > 0.01) {
		out_col.rgb = mix(out_col.rgb, col_edge.rgb, clamp(hit_flash * 0.58, 0.0, 0.85));
	}

	out_col.a *= opacity;
	COLOR = out_col;
}
