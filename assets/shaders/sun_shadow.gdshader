shader_type canvas_item;
render_mode unshaded, blend_mul;
#include "res://assets/shaders/daylight.gdshaderinc"
// SunShadows (docs/sonnenschatten.md): darkens the ground where the shadow buffer holds a silhouette. Drawn in the world
// right above the ground layers (ground, decals, relief, water, meadow details) and below everything that stands up, so
// a shadow never lies on its own caster. One art pixel per buffer pixel: hard, stepped edges like the rest of the art.
uniform sampler2D shadow_tex : filter_nearest, repeat_disable;
uniform vec4 shadow_rect = vec4(0.0, 0.0, 1.0, 1.0); // world px: top left of the buffer, its size
uniform vec3 tone = vec3(0.6, 0.64, 0.8); // what a fully shadowed pixel is multiplied with (sky-blue ambient light)
uniform float strength = 0.0; // 0 none .. 1 full (sun height, weather, moonlight)
varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 px = floor(world);
	vec2 uv = (px + 0.5 - shadow_rect.xy) / shadow_rect.zw;
	float a = 0.0;
	if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
		a = texture(shadow_tex, uv).a;
	}
	float k = 0.0;
	if (a > 0.5) {
		// under a cloud's shadow the sun is gone: the cast shadow fades into it
		k = strength * (1.0 - 0.9 * smoothstep(0.04, 0.5, cloud_thick(px)));
	}
	COLOR = vec4(mix(vec3(1.0), tone, k), 1.0);
}
