shader_type canvas_item;
render_mode unshaded;
// Only the palette-derived emission mask is drawn here. World tint still affects the body.
// Inherited COLOR alpha keeps emissions attached to their owner's death fade.
uniform float pulse : hint_range(0.0, 1.0) = 0.5;
uniform float warning : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float lit = step(0.01, COLOR.a);
	COLOR.rgb = COLOR.rgb * (1.0 + pulse * 0.32 + warning * 0.3) + vec3(0.04, 0.02, 0.09) * pulse * lit;
}
