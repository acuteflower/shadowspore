// Shared by night_fog and night_moon: integer-free hash, value noise and a 4 octave fbm (about 0.1 .. 0.8).
const float N_BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float n_bayer(vec2 px) {
	return N_BAYER[int(mod(px.y, 4.0)) * 4 + int(mod(px.x, 4.0))] / 16.0;
}

float n_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float n_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(n_hash(i), n_hash(i + vec2(1.0, 0.0)), f.x), mix(n_hash(i + vec2(0.0, 1.0)), n_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float n_fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * n_vnoise(p);
		p = p * 2.03 + 11.7;
		a *= 0.5;
	}
	return s;
}
