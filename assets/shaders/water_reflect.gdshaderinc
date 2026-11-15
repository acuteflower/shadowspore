// Mirror images on water (docs/wasserspiegelung.md). WaterReflections renders upside-down copies of
// Ellie, trees, animals ... into one small screen-sized buffer; every water surface (rivers, lakes,
// rain puddles) looks its world pixel up in it. Off (g_reflect_on 0) = no texture read at all.
global uniform sampler2D g_reflect : filter_nearest, repeat_disable;
global uniform vec4 g_reflect_rect; // world px: top left of the buffer, size in world px
global uniform float g_reflect_on;

// The mirror image at world pixel `px`, its rows slid sideways in whole pixels by the water's
// ripples (`wobble` = how far, in px). Alpha = how much of a reflected thing lies there.
vec4 reflect_at(vec2 px, float wobble, float t) {
	if (g_reflect_on < 0.5) { return vec4(0.0); }
	float row = floor(px.y);
	float slide = sin(row * 0.61 + t * 2.1) * wobble + sin(row * 0.17 - t * 0.83 + px.x * 0.013) * wobble * 0.7;
	vec2 at = vec2(floor(px.x) + floor(slide + 0.5), row) + 0.5;
	vec2 uv = (at - g_reflect_rect.xy) / g_reflect_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) { return vec4(0.0); }
	return texture(g_reflect, uv);
}

// The reflected colour as water shows it: darker, cooler, a breath of the water's own colour.
vec3 reflect_tint(vec3 reflected, vec3 water) {
	vec3 cool = reflected * vec3(0.86, 0.95, 1.0) + water * 0.08;
	return mix(cool, water, 0.08);
}
