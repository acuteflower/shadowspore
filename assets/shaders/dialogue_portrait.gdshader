shader_type canvas_item;
render_mode unshaded;
uniform vec4 frame_region = vec4(0.0, 0.0, 443.0, 660.0);
uniform vec2 sheet_size = vec2(887.0, 1774.0);
uniform vec2 logical_size = vec2(103.0, 153.0);
uniform float blink_offset = 418.0;
uniform float clock = 0.0;
uniform bool speaking = false;
uniform int viseme = 0; // 0 closed, 1 consonant, 2 wide (e, i), 3 open (a), 4 round (o, u)
uniform bool blinking = false;
uniform bool reflective = false;
uniform bool injured = false;
uniform float fade = 1.0;

const vec3 PALETTE[30] = vec3[30](
	vec3(0.07059, 0.04706, 0.10980),
	vec3(0.03529, 0.02353, 0.05882),
	vec3(0.08235, 0.05882, 0.13333),
	vec3(0.17255, 0.13725, 0.27843),
	vec3(0.29020, 0.23922, 0.47059),
	vec3(0.41569, 0.35294, 0.65098),
	vec3(0.31765, 0.25490, 0.37255),
	vec3(0.44314, 0.37647, 0.47059),
	vec3(0.36863, 0.32941, 0.58824),
	vec3(0.56078, 0.51765, 0.76078),
	vec3(0.74118, 0.70196, 0.89412),
	vec3(0.91373, 0.89020, 0.96863),
	vec3(1.00000, 0.98039, 0.94118),
	vec3(0.72157, 0.47059, 0.40784),
	vec3(0.84314, 0.60392, 0.53333),
	vec3(0.93725, 0.75294, 0.65882),
	vec3(0.97647, 0.86275, 0.77647),
	vec3(1.00000, 0.94510, 0.89412),
	vec3(0.43529, 0.31373, 0.12549),
	vec3(0.70588, 0.54118, 0.21961),
	vec3(0.90196, 0.76863, 0.40784),
	vec3(1.00000, 0.94118, 0.69020),
	vec3(0.20392, 0.09412, 0.36863),
	vec3(0.40000, 0.21176, 0.67843),
	vec3(0.58039, 0.40784, 0.93333),
	vec3(0.79608, 0.66667, 1.00000),
	vec3(0.18039, 0.01569, 0.04706),
	vec3(0.35294, 0.03137, 0.09412),
	vec3(0.54118, 0.07059, 0.14902),
	vec3(0.72157, 0.15686, 0.22745)
);

void fragment() {
	// Animate on the game's pixel grid rather than filtering the illustration.
	vec2 p = floor(UV * logical_size) + vec2(0.5);
	vec2 q = p / logical_size;
	q.x = 1.0 - q.x; // turn Ellie towards the conversation
	float hair = step(0.17, q.y) * (1.0 - step(0.23, q.x) + step(0.78, q.x));
	q.x += floor(sin(clock * 1.35 + q.y * 5.0) * 1.1) * hair / logical_size.x;
	float breath = floor(sin(clock * 1.7) * 0.8 + 0.5);
	q.y += breath * smoothstep(0.35, 0.68, q.y) / logical_size.y;
	vec4 ink = texture(TEXTURE, (frame_region.xy + clamp(q, vec2(0.0), vec2(1.0)) * frame_region.zw) / sheet_size);
	if (blinking || (reflective && sin(clock * 0.85) > 0.3)) {
		// Swap only the eyelids. Hair, pose, and the cheek wound stay registered.
		float eye_y = 0.31;
		vec2 a = (q - vec2(0.32, eye_y)) / vec2(0.088, 0.04);
		vec2 b = (q - vec2(0.49, eye_y - 0.008)) / vec2(0.088, 0.04);
		if (min(dot(a, a), dot(b, b)) < 1.0) {
			ink = texture(TEXTURE, (frame_region.xy + vec2(blink_offset, 0.0) + clamp(q, vec2(0.0), vec2(1.0)) * frame_region.zw) / sheet_size);
		}
	}
	if (speaking) {
		// Lip sync from the painted resting mouth: its upper lip stays, the lower lip and everything under it slide down by `open` art pixels
		// and the gap is filled with the mouth's inside (dark, teeth, tongue). u, v are art pixels from the mouth's centre (texture space,
		// v down); the lower lip starts at v = 0. The corners follow with a delay so the opening is round.
		float u = floor(q.x * logical_size.x - 43.5 + 0.5);
		float v = floor(q.y * logical_size.y - 63.5 + 0.5);
		float au = abs(u);
		if (au <= 7.0 && v >= 0.0 && v <= 8.0) {
			float gap = viseme == 0 ? 0.0 : (viseme == 1 ? 1.0 : (viseme == 2 ? 2.0 : (viseme == 3 ? 3.0 : 2.0)));
			float corner = viseme == 4 ? max(au - 2.0, 0.0) * 2.0 : max(au - 3.0, 0.0);
			float n = max(gap - corner, 0.0);
			if (n > 0.0) {
				vec2 top_q = vec2(q.x, q.y - (v + 1.0) / logical_size.y); // the row of the upper lip (v = -1)
				vec4 top = texture(TEXTURE, (frame_region.xy + clamp(top_q, vec2(0.0), vec2(1.0)) * frame_region.zw) / sheet_size);
				vec4 skin = texture(TEXTURE, (frame_region.xy + vec2(0.4235, 0.385) * frame_region.zw) / sheet_size);
				if (v < n) {
					bool lip = distance(top.rgb, skin.rgb) > 0.2;
					if (lip) {
						ink = vec4(PALETTE[26], 1.0);
						if (v == 0.0 && n >= 2.0 && au <= 3.0) ink = vec4(PALETTE[17], 1.0);
						if (v == n - 1.0 && n >= 3.0 && au <= 2.0) ink = vec4(PALETTE[13], 1.0);
					} else {
						ink = top;
					}
				} else {
					vec2 sq = vec2(q.x, q.y - n / logical_size.y);
					ink = texture(TEXTURE, (frame_region.xy + clamp(sq, vec2(0.0), vec2(1.0)) * frame_region.zw) / sheet_size);
				}
			}
		}
	}
	// Reject stray chroma-key pixels at the generated cutout's outer edge.
	if (ink.r > 0.88 && ink.b > 0.78 && ink.g < 0.16) ink.a = 0.0;
	vec3 pigment = PALETTE[0];
	float best = 10.0;
	for (int i = 0; i < 30; i++) {
		vec3 delta = ink.rgb - PALETTE[i];
		float distance = dot(delta, delta);
		if (distance < best) { best = distance; pigment = PALETTE[i]; }
	}
	COLOR = vec4(pigment, step(0.5, ink.a) * fade);
}
