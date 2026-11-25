shader_type canvas_item;
// Animated tidal chamber water for Die Gezeitenkammern von Sturmhafen.
// Supports smooth tide_level lowering (1.0 = flooded waist-deep, 0.5 = ankle-deep after West Bell, 0.0 = drained).

uniform float tide_level : hint_range(0.0, 1.0) = 1.0;
uniform float wave_surge : hint_range(0.0, 1.0) = 0.0;
uniform vec4 deep_col : source_color = vec4(0.045, 0.105, 0.175, 0.94);
uniform vec4 mid_col : source_color = vec4(0.09, 0.24, 0.34, 0.88);
uniform vec4 foam_col : source_color = vec4(0.30, 0.94, 0.88, 0.90);
uniform vec2 tex_size = vec2(640.0, 360.0);

void fragment() {
	if (tide_level <= 0.01) {
		discard;
	}
	vec2 px = floor(UV * tex_size * 0.5) * 2.0;
	float t = TIME * (1.4 + wave_surge * 3.5);
	float w1 = sin(px.x * 0.06 + t + sin(px.y * 0.09) * 1.4);
	float w2 = cos(px.y * 0.08 - t * 0.75 + px.x * 0.03);
	float rip = (w1 * 0.55 + w2 * 0.45) * 0.5 + 0.5;

	// Edge foam near basin rim
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float foam_edge = 1.0 - smoothstep(0.015, 0.065, edge);

	vec4 col = mix(deep_col, mid_col, smoothstep(0.25, 0.78, rip));
	float crest = step(0.84 - wave_surge * 0.18, rip) * 0.45 + foam_edge * 0.55;
	col.rgb = mix(col.rgb, foam_col.rgb, clamp(crest, 0.0, 0.85));
	col.a = mix(0.28, col.a, clamp(tide_level, 0.0, 1.0));
	COLOR = col;
}
