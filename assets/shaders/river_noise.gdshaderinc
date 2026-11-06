float hash21(vec2 p) {
    // The sin hash has no visible lattice on integer pixel coordinates (the fract-product one did).
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
// Smooth value noise: coherent patches, so banks vary in stretches, not per pixel.
float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float bayer4(vec2 p) {
    vec2 q = mod(floor(p), 4.0);
    int idx = int(q.x) + int(q.y) * 4;
    // 4x4 ordered-dither matrix, same family as the ground shader's dither.
    float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
    return (m[idx] + 0.5) / 16.0;
}
