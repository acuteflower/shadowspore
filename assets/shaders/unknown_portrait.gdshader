shader_type canvas_item;
render_mode unshaded;
uniform bool unknown = true;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
	vec4 art = texture(TEXTURE,UV);
	if(unknown && art.a > 0.5) {
		float lum = dot(art.rgb,vec3(.3,.59,.11));
		// Preserve the silhouette and only a hint of volume; visor and identifying
		// colors disappear too, so equipment doesn't reveal the stranger.
		art.rgb = lum > .35 ? vec3(.065,.047,.095) : vec3(.035,.024,.055);
	}
	COLOR = tint * art;
}
