shader_type canvas_item;
// Morwenna and her glitch clones (docs/enemies/boss_mora.md, src/entities/enemies/witch_boss/witch_body.gd). One frame of a sprite sheet whose
// rows slip sideways in whole art pixels: a band of the picture (`slice`) jumps to one side for a moment, thin scanlines run through a phantom,
// the colours split a pixel apart, and a body that is struck away crumbles into rows of mist (`dissolve`). Everything works in the frame's own
// pixels (`frame_px`, `frame_origin`), so nothing ever reads the neighbouring frame of the sheet.

uniform vec2 sheet_px = vec2(4512.0, 768.0);
uniform vec2 frame_px = vec2(96.0, 96.0);
uniform vec2 frame_origin = vec2(0.0);   // top left of the shown frame in sheet pixels
uniform vec4 slice = vec4(0.0);          // y0, height, shift (px), second band shift
uniform float scan = 0.0;                // 0 = flesh, 1 = a phantom: scanlines, a little see-through
uniform float split = 0.0;               // px the red and blue ghosts stand apart
uniform float jitter = 0.0;              // every row trembles by up to this many px
uniform float dissolve = 0.0;            // 0 whole .. 1 gone
uniform float flash = 0.0;               // struck: white
uniform float clock = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 ghost : source_color = vec4(0.66, 1.0, 0.42, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 1 inside the shown frame, 0 outside (so nothing of the neighbouring frame is read)
float inside(vec2 px) {
	return (px.x < 0.5 || px.y < 0.5 || px.x > frame_px.x - 0.5 || px.y > frame_px.y - 0.5) ? 0.0 : 1.0;
}

// built-in TEXTURE cannot be handed to a function: a macro reads it inside fragment()
#define TEXEL(p) (texture(TEXTURE, (frame_origin + (p)) / sheet_px) * inside(p))

void fragment() {
	vec2 px = floor(UV * sheet_px - frame_origin) + 0.5;
	float row = px.y;
	float shift = 0.0;
	if (row >= slice.x && row < slice.x + slice.y) {
		shift += slice.z;
	}
	if (row >= slice.x + slice.y * 1.8 && row < slice.x + slice.y * 2.3) {
		shift += slice.w;
	}
	float step_t = floor(clock * 14.0);
	if (jitter > 0.0) {
		shift += floor((hash(vec2(row, step_t)) - 0.5) * 2.0 * jitter + 0.5);
	}
	float eaten = 0.0;
	if (dissolve > 0.0) { // rows slide apart and are eaten from random pixels
		shift += floor((hash(vec2(row * 0.37, 3.0)) - 0.5) * 26.0 * dissolve);
		eaten = step(hash(px + vec2(0.0, floor(dissolve * 9.0))), dissolve * 1.15);
		px.y += floor(dissolve * 7.0 * hash(vec2(px.x, 9.0)));
	}
	vec2 at = px - vec2(shift, 0.0);
	vec4 c = TEXEL(at);
	if (split > 0.0) {
		vec4 l = TEXEL(at - vec2(split, 0.0));
		vec4 r = TEXEL(at + vec2(split, 0.0));
		c.rgb = c.rgb * c.a;
		c.rgb += vec3(l.r * 0.6, 0.0, l.b * 0.35) * l.a * (1.0 - c.a);
		c.rgb += vec3(0.0, r.g * 0.5, r.b * 0.6) * r.a * (1.0 - c.a);
		c.a = max(c.a, max(l.a, r.a) * 0.55);
		c.rgb /= max(c.a, 0.001);
	}
	if (scan > 0.0) {
		float line = step(0.5, fract((row + floor(clock * 9.0)) / 3.0)) ;
		c.rgb = mix(c.rgb, c.rgb * 0.72 + ghost.rgb * 0.10, scan * line);
		c.a *= 1.0 - scan * 0.16 * line;
		float band = step(0.93, hash(vec2(floor(row / 2.0), step_t)));
		c.rgb += ghost.rgb * 0.22 * band * scan;
	}
	c.rgb = mix(c.rgb, vec3(1.0), flash);
	c.rgb = mix(c.rgb, ghost.rgb, dissolve * 0.6);
	c.a *= 1.0 - eaten;
	COLOR = c * tint * COLOR;
}
