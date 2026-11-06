shader_type canvas_item;
render_mode unshaded; // keeps its violet glints bright at night
// Creeping shadow on the ground: a ragged black pool that grows, with violet tendrils that
// writhe, glints that pulse, and a slow crumbling dissolve. All per pixel on the 1:1 grid.

uniform vec2 size = vec2(16.0, 12.0); // patch size in pixels
uniform float seed = 0.0;
uniform float age = 0.0;
uniform float life = 6.0; // seconds before it starts to dissolve
uniform float fade = 3.5; // seconds the dissolve takes
uniform int arms = 4; // tendril count (max 10)

const float FLATTEN = 0.62; // ground pools are flat in the 3/4 view
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed * 91.7) * 43758.5453);
}

float bayer(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	return BAYER[i.y * 4 + i.x] / 16.0;
}

void fragment() {
	vec2 px = floor(UV * size);
	vec2 p = px + 0.5 - size * 0.5;
	p.y /= FLATTEN;
	float r = length(p);
	float ang = atan(p.y, p.x);

	float grow = 1.0 - exp(-age * 3.5);
	float dissolve = smoothstep(life, life + fade, age);
	float base = min(size.x * 0.5, size.y * 0.5 / FLATTEN) * 0.74;
	float radius = base * grow * (1.0 - 0.4 * dissolve);
	float shape = 0.78 + 0.22 * sin(ang * 3.0 + seed * 6.28) + 0.14 * sin(ang * 5.0 + seed * 17.0 + age * 0.6);
	bool inside = r < radius * shape;

	// tendrils: thin arms that wiggle (at a retro 8 fps) and carry travelling pulses
	float step_age = floor(age * 8.0) / 8.0;
	bool on_arm = false;
	float arm_pulse = 0.0;
	for (int k = 0; k < 10; k++) {
		if (k >= arms) {
			break;
		}
		float fk = float(k);
		float a = hash(vec2(fk, 1.7)) * 6.2832 + 0.35 * sin(step_age * 1.6 + fk * 2.0 + r * 0.14);
		float arm_len = base * (1.4 + 1.1 * hash(vec2(fk, 9.1))) * grow * (1.0 - 0.5 * dissolve);
		float across = abs(sin(ang - a)) * r;
		float width = 0.55 + 0.7 * clamp(1.0 - r / arm_len, 0.0, 1.0);
		if (cos(ang - a) > 0.0 && r < arm_len && r > radius * 0.5 && across < width) {
			on_arm = true;
			arm_pulse = 0.5 + 0.5 * sin(r * 0.9 - step_age * 5.0 + fk * 1.7);
		}
	}

	float h = hash(px);
	vec4 col = vec4(0.0);
	if (inside) {
		float blotch = hash(floor(px * 0.5) + 7.0);
		vec3 dark = mix(vec3(0.027, 0.016, 0.05), vec3(0.09, 0.06, 0.16), blotch * 0.8);
		float edge = r / max(radius * shape, 0.001);
		if (edge > 0.68 && bayer(px) < (edge - 0.68) * 2.6) {
			dark = vec3(0.17, 0.11, 0.31); // stippled violet rim
		}
		col = vec4(dark, 0.92);
		float pulse = 0.5 + 0.5 * sin(age * 3.0 + h * 40.0);
		if (h > 0.955 && pulse > 0.6) {
			col.rgb = vec3(0.50, 0.33, 0.92); // glints
		}
	} else if (grow > 0.25) {
		// a faint, dithered glow seeping out of the pool: the ground is being eaten, and it shimmers
		float outside = r - radius * shape;
		float k = 1.0 - outside / 3.5;
		float breath = 0.6 + 0.4 * sin(age * 2.4 + seed * 6.28);
		if (outside > 0.0 && k > 0.0 && bayer(px) < k * 0.6) {
			col = vec4(0.28, 0.17, 0.58, 0.34 * k * breath);
		}
	}
	if (on_arm) {
		col = vec4(mix(vec3(0.22, 0.14, 0.44), vec3(0.62, 0.50, 1.0), arm_pulse * arm_pulse), 0.92);
	}
	// crumble away: outer pixels go first
	if (h < dissolve * (0.5 + 0.7 * clamp(r / max(base, 1.0), 0.0, 1.5))) {
		col.a = 0.0;
	}
	COLOR = col;
}
