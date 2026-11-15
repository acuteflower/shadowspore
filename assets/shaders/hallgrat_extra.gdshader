shader_type canvas_item;
// Hallgrat's townsfolk (HallgratExtra): the sheets from tools/art_hallgrat_extras.py draw the clothes and the hair in three KEY ramps of four
// colours that appear nowhere else; this swaps them for the townsperson's own palette (data/hallgrat_people.json extras.palettes).
// Stays world-lit like every ordinary figure (no unshaded).

uniform vec4 key_a[4];
uniform vec4 key_b[4];
uniform vec4 key_h[4];
uniform vec4 new_a[4];
uniform vec4 new_b[4];
uniform vec4 new_h[4];

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 o = c.rgb;
	for (int i = 0; i < 4; i++) {
		if (distance(c.rgb, key_a[i].rgb) < 0.006) { o = new_a[i].rgb; }
		if (distance(c.rgb, key_b[i].rgb) < 0.006) { o = new_b[i].rgb; }
		if (distance(c.rgb, key_h[i].rgb) < 0.006) { o = new_h[i].rgb; }
	}
	COLOR = vec4(o, c.a) * tint;
}
