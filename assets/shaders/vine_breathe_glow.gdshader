shader_type canvas_item;
render_mode unshaded;
// The glowing buds of the Hexenulme's ropes: the same breath as vine_breathe.gdshader, read from the glow row (two rows below the
// art), its mask one row up.
#include "res://assets/shaders/vine_breathe.gdshaderinc"

void vertex() {
	modulate_in = COLOR;
	phase = MODEL_MATRIX[3].x * 0.021 + MODEL_MATRIX[3].y * 0.013;
}

void fragment() {
	vec2 size = vec2(textureSize(TEXTURE, 0));
	vec4 best = vec4(0.0);
	for (int s = -3; s <= 3; s++) {
		vec2 src = UV - vec2(float(s) / size.x, 0.0);
		vec4 m = texture(TEXTURE, src + vec2(0.0, mask_rows));
		if (m.a > 0.5 && vine_shift(m.r, phase) == s) {
			vec4 c = texture(TEXTURE, src);
			if (c.a > best.a) { best = c; }
		}
	}
	COLOR = best * modulate_in;
}
