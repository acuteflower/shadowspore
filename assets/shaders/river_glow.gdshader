shader_type canvas_item;
render_mode unshaded, blend_add;
#include "res://assets/shaders/river_noise.gdshaderinc"

// Night glow of a river chunk, drawn on top of the water with the same field texture
// (R coverage, G depth, BA direction). Plankton drifts downstream, slow luminous
// patches breathe in the deep, and the shore carries a broken, pulsing teal rim.
uniform sampler2D bank_map : filter_nearest, repeat_disable;
uniform vec2 world_origin = vec2(0.0);
global uniform float g_water_time; // same global river clock as river_water.gdshader
uniform float bank_width = 20.0;
uniform float night = 0.0;

void fragment() {
    vec4 mask = texture(TEXTURE, UV);
    vec2 pixel = floor(UV * vec2(textureSize(TEXTURE, 0))) + floor(world_origin);
    vec3 glow = vec3(0.0);
    if (mask.r > 0.5) {
        vec2 flow = mask.ba * 2.0 - 1.0;
        if (length(flow) < 0.02) { flow = vec2(0.0, 1.0); }
        flow = normalize(flow);
        vec2 across = vec2(-flow.y, flow.x);
        float depth = mask.g;
        // Slow breathing patches in the deeper water, dithered into the pixel grid.
        float patch_noise = vnoise(pixel / 23.0 + vec2(g_water_time * 0.05, 0.0)) * 0.6 + vnoise(pixel / 9.0 - vec2(0.0, g_water_time * 0.08)) * 0.4;
        float breathe = 0.6 + 0.4 * sin(g_water_time * 0.7 + pixel.x * 0.02);
        if (patch_noise > 0.55 && hash21(pixel + 5.0) < (patch_noise - 0.55) * 1.4 * breathe * (0.3 + depth)) {
            glow += vec3(0.04, 0.22, 0.26);
        }
        // Plankton: single pixels twinkling, carried downstream, a few with a short streak.
        vec2 q = vec2(dot(pixel, flow), dot(pixel, across));
        q.x -= floor(g_water_time * mix(1.6, 0.22, texture(bank_map, UV).b));
        vec2 cell = floor(q / vec2(9.0, 7.0));
        vec2 local = mod(q, vec2(9.0, 7.0));
        float h = hash21(cell);
        vec2 at = vec2(floor(hash21(cell + 3.0) * 7.0) + 1.0, floor(hash21(cell + 7.0) * 5.0) + 1.0);
        float twinkle = 0.5 + 0.5 * sin(g_water_time * (1.0 + h * 2.0) + h * 40.0);
        bool streak = h > 0.95 && local.y == at.y && local.x >= at.x - 2.0 && local.x <= at.x;
        if (h > 0.78 && ((local.x == at.x && local.y == at.y) || streak)) {
            vec3 c = h > 0.8 ? vec3(0.55, 0.45, 0.95) : vec3(0.30, 0.95, 0.85);
            glow += c * (0.35 + 0.65 * twinkle) * (0.5 + depth);
        }
        // The shoreline: teal light under the surface along the bank, broken into stretches.
        float inside = texture(bank_map, UV).g * 8.0;
        float stretch = vnoise(pixel / 13.0 + 5.0);
        if (inside < 2.0 && stretch > 0.42) {
            glow += vec3(0.10, 0.50, 0.46) * (1.0 - inside / 2.0) * (0.55 + 0.45 * sin(g_water_time * 0.9 + pixel.x * 0.07 + pixel.y * 0.05));
        }
    } else {
        // Luminous specks on the bank: fungi and glowing moss close to the water.
        float d = texture(bank_map, UV).r * bank_width;
        float h = hash21(pixel + 13.0);
        if (d < 12.0 && h > 0.994) {
            float tw = 0.5 + 0.5 * sin(g_water_time * 1.3 + h * 300.0);
            glow += (h > 0.998 ? vec3(0.55, 0.40, 0.95) : vec3(0.25, 0.85, 0.75)) * (0.4 + 0.6 * tw);
        }
    }
    COLOR = vec4(glow * night, 1.0);
}
