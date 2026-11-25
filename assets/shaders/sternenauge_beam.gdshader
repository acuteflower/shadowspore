shader_type canvas_item;
render_mode unshaded, blend_add;
// The beam of the Sternenauge: a cone of starlight leaving the lens along +x of a ColorRect.
// UV.x = 0 at the lens, 1 at the far end; UV.y across. Never a smooth gradient: a 4x4 Bayer
// pattern decides every pixel, like the waystone pillar. `strength` 0..1 fades it in.
uniform float strength = 0.0;
uniform float time = 0.0;
uniform vec2 rect_size = vec2(420.0, 90.0);
uniform vec3 tone_near : source_color = vec3(0.88, 1.0, 0.98);
uniform vec3 tone_far : source_color = vec3(0.47, 0.96, 0.9);

float bayer(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	vec2 px = floor(UV * rect_size);
	float along = UV.x;
	float half_width = mix(0.07, 0.5, pow(along, 0.85));
	float across = abs(UV.y - 0.5) / half_width;
	float body = 1.0 - smoothstep(0.35, 1.0, across);
	float core = 1.0 - smoothstep(0.0, 0.3, across);
	float motes = 0.75 + 0.25 * sin(px.x * 0.21 - time * 2.3 + sin(px.y * 0.5 + time) * 1.5);
	float fade = pow(1.0 - along, 1.15) * smoothstep(0.0, 0.04, along);
	float level = (body * 0.55 + core * 0.45) * fade * motes * strength;
	float lit = step(bayer(px), level * 0.9);
	COLOR = vec4(mix(tone_near, tone_far, along) * lit * 0.7, lit);
}
