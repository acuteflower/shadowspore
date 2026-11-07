shader_type canvas_item;
render_mode unshaded, blend_add;
// An additive, already dithered halo of the title logo (void eye, life, lamp). `strength` breathes with the light it belongs to.

uniform float strength = 0.8;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.rgb * strength, c.a);
}
