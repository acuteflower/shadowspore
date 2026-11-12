shader_type canvas_item;
render_mode unshaded;
// Turns any sprite into a backlit silhouette (loading screen): every solid pixel becomes the void's darkest ink, the outer edges catch a thin violet
// rim of the moon behind. With `keep_glow` the self-lit pixels (a void spider's eyes and veins) keep burning through.

uniform vec4 body : source_color = vec4(0.016, 0.008, 0.031, 1.0); // 040208
uniform vec4 rim : source_color = vec4(0.58, 0.41, 0.93, 1.0); // 9468ee
uniform float rim_strength : hint_range(0.0, 1.0) = 0.85;
uniform bool keep_glow = false;
uniform float cutoff = 0.35;

float solid(sampler2D tex, vec2 uv) {
	return step(cutoff, texture(tex, uv).a);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < cutoff) {
		discard;
	}
	vec2 t = TEXTURE_PIXEL_SIZE;
	// the rim sits on the top and side edges (the light comes from behind and above), never on the soles
	float open_side = (1.0 - solid(TEXTURE, UV + vec2(-t.x, 0.0))) + (1.0 - solid(TEXTURE, UV + vec2(t.x, 0.0))) + (1.0 - solid(TEXTURE, UV + vec2(0.0, -t.y)));
	float edge = clamp(open_side, 0.0, 1.0);
	vec3 col = mix(body.rgb, rim.rgb, edge * rim_strength);
	if (keep_glow) {
		float hot = max(c.r, c.b);
		if (hot > 0.6 && hot - c.g > 0.45) {
			col = c.rgb;
		}
	}
	COLOR = vec4(col, 1.0);
}
