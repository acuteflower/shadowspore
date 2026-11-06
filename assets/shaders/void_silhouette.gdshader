shader_type canvas_item;
// Flat void-violet silhouette with a brighter rim, used for blink afterimages.

uniform vec4 tint : source_color = vec4(0.17, 0.07, 0.31, 1.0);
uniform vec4 rim : source_color = vec4(0.61, 0.36, 1.0, 1.0);

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float edge = 1.0 - min(
		min(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a),
		min(texture(TEXTURE, UV + vec2(0.0, px.y)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a));
	COLOR = vec4(mix(tint.rgb, rim.rgb, edge), COLOR.a);
}
