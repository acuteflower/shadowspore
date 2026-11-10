shader_type canvas_item;
render_mode unshaded;
// The colour mood of the whole picture (MoodGrade, data/mood.json): the last pass over the world, under the HUD.
// 1. split toning: the dark parts lean one way and the bright parts the other (violet shade and amber light at golden hour, indigo shade and teal
//    light at night): two opposed hues are what reads as "coloured light" instead of a tinted picture.
// 2. vibrance: dull colours gain saturation, already vivid ones hardly (so nothing burns out).
// 3. a gentle S curve for depth.
// 4. bloom: bright, coloured things (fire, windows, glowing plants, crystals, moon pools) bleed a soft glow into their surroundings. It is read from
//    the screen texture's mip chain (two blur sizes, four taps each as a tent, so the glow does not shimmer when the camera glides).
// The glow sizes are in ART pixels (`px_scale` = screen pixels per art pixel), so the look is the same in any window.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec3 shadow_tint = vec3(1.0);
uniform vec3 light_tint = vec3(1.0);
uniform float split : hint_range(0.0, 1.0) = 0.0;
uniform float vibrance : hint_range(0.0, 1.0) = 0.0;
uniform float contrast : hint_range(0.0, 0.5) = 0.0;
uniform float bloom : hint_range(0.0, 2.0) = 0.0;
uniform float threshold : hint_range(0.0, 1.0) = 0.6;
uniform float vignette : hint_range(0.0, 1.0) = 0.0; // the picture's rim sinks into the mood's shadow colour (strong at night: the dark closes in)
uniform float px_scale = 2.0;

vec3 blurred(vec2 uv, float lod, vec2 texel) {
	vec2 o = texel * exp2(lod) * 0.5;
	return (textureLod(screen_texture, uv + vec2(o.x, o.y), lod).rgb + textureLod(screen_texture, uv + vec2(-o.x, o.y), lod).rgb
		+ textureLod(screen_texture, uv + vec2(o.x, -o.y), lod).rgb + textureLod(screen_texture, uv + vec2(-o.x, -o.y), lod).rgb) * 0.25;
}

vec3 glow_of(vec3 b) {
	float peak = max(b.r, max(b.g, b.b));
	float sat = peak - min(b.r, min(b.g, b.b));
	return b * smoothstep(threshold, threshold + 0.38, peak + 0.35 * sat); // coloured light glows sooner than grey brightness
}

void fragment() {
	vec3 c = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	float base_lod = log2(max(px_scale, 1.0));
	vec3 near = glow_of(blurred(SCREEN_UV, base_lod + 1.6, SCREEN_PIXEL_SIZE));
	vec3 far = glow_of(blurred(SCREEN_UV, base_lod + 3.4, SCREEN_PIXEL_SIZE));
	vec3 glow = (near * 0.55 + far * 0.75) * bloom;
	// bloom first (it is light), as a screen blend so bright places saturate softly instead of clipping
	c = 1.0 - (1.0 - c) * (1.0 - clamp(glow * 0.55, 0.0, 1.0));
	float lum = dot(c, vec3(0.30, 0.59, 0.11));
	// vibrance
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	c = mix(vec3(lum), c, 1.0 + vibrance * (1.0 - sat));
	// split toning
	vec3 tone = mix(shadow_tint, light_tint, smoothstep(0.10, 0.62, lum));
	c = mix(c, c * tone + (shadow_tint - 1.0) * 0.035 * (1.0 - smoothstep(0.0, 0.30, lum)), split);
	// S curve around the mid tones
	vec3 s = c * c * (3.0 - 2.0 * c);
	c = mix(c, s, contrast * 2.0);
	// vignette: an oval, so the sides close in more than top and bottom; the dark leans towards the shadow tint, not grey
	vec2 q = (SCREEN_UV - 0.5) * vec2(1.0, 1.25);
	float rim = smoothstep(0.30, 0.78, length(q));
	c = mix(c, c * shadow_tint * 0.55, vignette * rim);
	float noise = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	COLOR = vec4(clamp(c, 0.0, 1.0) + vec3(noise / 255.0), 1.0);
}
