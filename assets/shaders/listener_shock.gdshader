shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec2 field_size = vec2(120.0);
uniform vec2 direction = vec2(1.0, 0.0);
uniform vec2 world_to_uv;
uniform float reach = 46.0;
uniform float half_arc = 1.0;
uniform float phase = 0.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * field_size;
	float r = length(p);
	vec2 radial = p / max(r, 0.01);
	float front = reach * clamp(phase, 0.0, 1.0);
	float band = exp(-pow((r - front) / 3.4, 2.0));
	float angular = smoothstep(cos(half_arc) - 0.03, cos(half_arc) + 0.03, dot(radial, direction));
	float strength = band * angular * (1.0 - smoothstep(0.8, 2.3, phase)) * smoothstep(2.0, 8.0, r);
	vec2 offset = radial * strength * 2.0 * world_to_uv;
	vec2 snapped = (floor((SCREEN_UV - offset) / SCREEN_PIXEL_SIZE) + vec2(0.5)) * SCREEN_PIXEL_SIZE;
	COLOR = vec4(textureLod(screen_texture, snapped, 0.0).rgb, strength * 0.8);
}
