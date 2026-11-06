shader_type canvas_item;
render_mode unshaded, blend_add;

// A jelly seen through the water surface: rows shift sideways in whole art pixels with the
// ripples, now and then a row is washed out by a glint, and the colour is dimmed and pulled
// towards the water's teal so it lies under the surface instead of hovering over it.
uniform float depth_dim = 0.78;

void fragment() {
    vec2 size = vec2(textureSize(TEXTURE, 0));
    float row = floor(UV.y * size.y);
    float shift = floor(sin(row * 0.9 + TIME * 1.7) * 1.2 + sin(row * 0.37 - TIME * 0.9) * 0.6 + 0.5);
    vec4 c = texture(TEXTURE, UV + vec2(shift / size.x, 0.0));
    float glint = step(0.88, sin(row * 2.3 + TIME * 1.5 + floor(UV.x * size.x / 8.0) * 1.7));
    float a = c.a * depth_dim * (1.0 - 0.55 * glint);
    vec3 water = vec3(0.10, 0.42, 0.46);
    COLOR = vec4(mix(c.rgb, water * (0.5 + max(c.r, max(c.g, c.b))), 0.32), a);
}
