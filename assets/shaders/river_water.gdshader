shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
#include "res://assets/shaders/river_noise.gdshaderinc"
global uniform float g_night; // 0..1 night (DayNight): moon glints
global uniform float g_sun; // 0..1 sun height (DayNight): sun glints and caustics

// Sprite TEXTURE: R coverage, G depth, BA direction encoded from [-1,1] to [0,1].
// bank_map R: distance from water / 12 pixels. Both maps have the same dimensions.
uniform sampler2D bank_map : filter_nearest, repeat_disable;
uniform sampler2D water_detail : filter_nearest, repeat_enable;
uniform sampler2D bank_material : source_color, filter_nearest, repeat_enable;
uniform vec2 world_origin = vec2(0.0);
global uniform float g_water_time; // seconds of the river clock (WorldRivers / river_design_patch), shared by all water
uniform float bank_width = 12.0;
// World bake only: bank_map.g holds the depth under the surface (0..8 px) for shore shading.
uniform bool bank_inner = false;
// Positions are in world pixels, radius in pixels, strength in 0..1.
uniform vec4 disturbances[8];
uniform int disturbance_count = 0;
// Swimmers (docs/schwimmen_konzept.md 6.3): xy world pixels, z radius, w energy 0..1; set by SwimWater every frame.
uniform vec4 swimmers[4];
uniform int swimmer_count = 0;
// xy top center, z falling height, w width; world pixels.
uniform vec4 waterfall_links[4];
uniform int fall_link_count = 0;


void fragment() {
    vec4 mask = texture(TEXTURE, UV);
	// B is reserved for calm lake water in composited world fields; river banks stay zero.
	float calm = texture(bank_map, UV).b;
    float distance_to_water = texture(bank_map, UV).r * bank_width;
    vec2 pixel = floor(UV * vec2(textureSize(TEXTURE, 0))) + floor(world_origin);
    vec4 out_color = vec4(0.0);
    if (mask.r > 0.5) {
        vec2 flow = mask.ba * 2.0 - 1.0;
        if (length(flow) < 0.02) { flow = vec2(0.0, 1.0); }
        flow = normalize(flow);
        vec2 across = vec2(-flow.y, flow.x);
        // Larger interlocking color patches, independent of shoreline contours.
        vec2 painted = floor(pixel / mix(3.0, 5.0, calm));
        float field = sin(painted.x * 0.28 + sin(painted.y * 0.25) * 1.6)
                    + sin(painted.y * 0.31 - painted.x * 0.16)
                    + sin((painted.x + painted.y) * 0.15 + 1.1) * 0.65;
        float depth = clamp(mask.g * mix(0.55, 0.68, calm) - field * 0.12 + 0.20, 0.0, 1.0);
        vec3 color = vec3(0.15, 0.31, 0.33);
        if (depth < 0.70) { color = vec3(0.18, 0.36, 0.37); }
        if (depth < 0.48) { color = vec3(0.22, 0.41, 0.40); }
        if (depth < 0.27) { color = vec3(0.29, 0.46, 0.43); }
        // Slow one-pixel refraction shifts submerged stones together in small patches.
        float refract_shift = step(0.72, sin(floor(pixel.y / 8.0) * 0.8 + g_water_time * 0.45));
        vec4 fixed_detail = texture(water_detail, (pixel + vec2(refract_shift, 0.0) + vec2(0.5)) / 128.0);
        if (mask.g < 0.48 && fixed_detail.r > 0.3) {
            color = mix(color, vec3(0.54, 0.54, 0.43), (1.0 - mask.g / 0.48) * 0.72);
        }
        // Broken, multi-pixel painted reflection clusters flowing downstream.
        vec2 q = floor(vec2(dot(pixel, flow), dot(pixel, across)));
        q.x -= floor(g_water_time * mix(1.5, 0.24, calm));
        vec2 cell = floor(q / vec2(22.0, 12.0));
        vec2 local = mod(q, vec2(22.0, 12.0));
        float seed = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
        float wave = floor(4.0 + sin(local.x * 0.32 + seed * 6.28) * 1.5);
        float span = step(2.0, local.x) * step(local.x, 16.0 + seed * 4.0);
        float broken = step(0.19, fract(local.x * 0.12 + seed));
        if (seed > 0.36 + mask.g * 0.07 && abs(local.y - wave) < 1.5 && span * broken > 0.5) {
            color = mix(color, vec3(0.38, 0.60, 0.56), 0.62);
        }
        if (seed > 0.60 + mask.g * 0.05 && abs(local.y - wave - 3.0) < 1.0 && local.x > 5.0 && local.x < 15.0) {
            color = mix(color, vec3(0.48, 0.60, 0.60), 0.48);
        }
        if (g_night > 0.5) { // a few cold glints of moonlight
            vec2 mc = floor(pixel / vec2(7.0, 4.0));
            float mh = hash21(mc + 77.0);
            if (mh > 0.96 && fract(g_water_time * 0.15 + mh * 5.0) < 0.2 && mod(pixel.x, 7.0) == 3.0 && mod(pixel.y, 4.0) == 2.0) {
                color = mix(color, vec3(0.78, 0.88, 1.0), 0.8 * g_night);
            }
        }
        // Sunlight: rare glints that wink on the surface and a drifting net of light over the shallows.
        float daylight = g_day_strength * day_local(pixel);
        if (daylight > 0.05) {
            vec2 gc = floor(pixel / vec2(5.0, 3.0));
            float gh = hash21(gc + 51.0);
            float glint_phase = fract(g_water_time * 0.22 + gh * 7.0);
            float glint_fade = smoothstep(0.0, 0.07, glint_phase) * (1.0 - smoothstep(0.15, 0.25, glint_phase));
            if (gh > 0.90 && abs(local.y - wave) < 2.0 && span > 0.5 && mod(pixel.x, 5.0) >= 2.0 && mod(pixel.x, 5.0) < 4.0 && mod(pixel.y, 3.0) == 1.0) {
                color = mix(color, mix(vec3(1.0, 0.98, 0.88), vec3(1.0, 0.81, 0.48), g_day_gold), daylight * glint_fade);
            }
            if (mask.g < 0.34) {
                float c1 = sin(pixel.x * 0.45 + g_water_time * 0.8 + sin(pixel.y * 0.37 + g_water_time * 0.6) * 1.7);
                float c2 = sin(pixel.y * 0.52 - g_water_time * 0.7 + sin(pixel.x * 0.33) * 1.5);
                if (c1 + c2 > 1.4) { color = mix(color, vec3(0.70, 0.86, 0.66), 0.5 * daylight); }
            }
        }
        // Elliptical broken arcs and short, downstream foam trails around obstacles.
        for (int i = 0; i < 8; i++) {
            if (i >= disturbance_count) { break; }
            vec4 d = disturbances[i];
            vec2 delta = pixel - d.xy;
            vec2 ellipse = vec2(delta.x, delta.y * 1.5);
            float r = length(ellipse);
            float radius = max(d.z, 1.0);
            float phase = mod(r - g_water_time * 2.0 + radius * 8.0, 9.0);
            float angular = sin(atan(ellipse.y, ellipse.x) * 4.0 + r * 0.12 - g_water_time * 0.5);
            float fade = clamp(1.0 - r / radius, 0.0, 1.0) * d.w;
            if (phase < 2.0 && angular > 0.05 && fade > 0.0) {
                color = mix(color, vec3(0.67, 0.78, 0.70), fade * 0.82);
            }
            float downstream = dot(delta, flow);
            float side = dot(delta, across);
            float trail_wave = sin(downstream * 0.35 - g_water_time * 1.3 + side * 0.26);
            float trail = clamp(1.0 - downstream / radius, 0.0, 1.0) * d.w;
            if (downstream > 2.0 && downstream < radius && abs(side) < radius * 0.34 && trail_wave > 0.76) {
                color = mix(color, vec3(0.61, 0.75, 0.68), trail * 0.65);
            }
        }
        // Swimmers: a soft dent under the body and broken rings that travel outwards (louder when she swims hard).
        for (int i = 0; i < 4; i++) {
            if (i >= swimmer_count) { break; }
            vec4 sw = swimmers[i];
            vec2 se = vec2(pixel.x - sw.x, (pixel.y - sw.y) * 2.0);
            float sr = length(se);
            float sradius = max(sw.z, 1.0);
            if (sr < sradius * 0.5) { color = mix(color, color * vec3(0.78, 0.86, 0.90), 0.5); }
            float sfade = clamp(1.0 - sr / (sradius * 2.4), 0.0, 1.0) * sw.w;
            float sphase = mod(sr - g_water_time * (3.0 + 5.0 * sw.w), 7.0);
            if (sr > sradius * 0.5 && sphase < 1.5 && sfade > 0.04 && sin(atan(se.y, se.x) * 5.0 + sr * 0.2 - g_water_time) > -0.35) {
                color = mix(color, vec3(0.67, 0.78, 0.70), sfade * 0.85);
            }
        }
        // Guide surface strokes into the falling sheet and carry its foam out.
        for (int i = 0; i < 4; i++) {
            if (i >= fall_link_count) { break; }
            vec4 fall = waterfall_links[i];
            vec2 rel = pixel - fall.xy;
            float half_width = max(fall.w * 0.5, 1.0);
            if (rel.y >= -12.0 && rel.y < 2.0 && abs(rel.x) < half_width) {
                float inlet = clamp((rel.y + 12.0) / 12.0, 0.0, 1.0);
                float rivulet = sin(rel.x * 0.65 + sin(rel.y * 0.3) - g_water_time * 1.1);
                color = mix(color, vec3(0.29, 0.52, 0.50), inlet * 0.34);
                if (rivulet > 0.65 && mod(rel.y - g_water_time * 2.0 + 64.0, 9.0) < 4.0) {
                    color = mix(color, vec3(0.43, 0.65, 0.60), inlet * 0.52);
                }
            }
            float landing_y = rel.y - fall.z;
            if (landing_y >= 0.0 && landing_y < 25.0 && abs(rel.x) < half_width * 1.25) {
                float fade = (1.0 - landing_y / 25.0) * (1.0 - abs(rel.x) / (half_width * 1.25));
                float wisps = sin(rel.x * 0.50 + landing_y * 0.37 - g_water_time * 1.2)
                            + sin(rel.x * 0.22 - landing_y * 0.57 + g_water_time * 0.7);
                if (wisps > 0.65) { color = mix(color, vec3(0.59, 0.73, 0.67), fade * 0.72); }
            }
        }
        if (bank_inner) {
            // Inside distance (px): pale sandy shallows, a bright breathing foam line,
            // and the cut bank's shadow lying on the water under the north shore.
            float inside = texture(bank_map, UV).g * 8.0;
            vec2 texel = 1.0 / vec2(textureSize(bank_map, 0));
            float north_land = texture(bank_map, UV + vec2(0.0, -texel.y * 3.0)).r
                             + texture(bank_map, UV + vec2(0.0, -texel.y * 5.0)).r;
            float shore = hash21(floor(pixel / vec2(6.0, 3.0)));
            if (inside < 3.0 && mask.g < 0.30) {
                float sandy = (1.0 - inside / 3.0) * 0.5;
                if (bayer4(pixel) < sandy) { color = mix(color, vec3(0.50, 0.58, 0.50), 0.55); }
            }
            if (north_land > 0.0 && inside < 2.5 && bayer4(pixel + vec2(1.0, 2.0)) < 0.6 * (1.0 - inside / 2.5)) {
                color = mix(color, vec3(0.07, 0.17, 0.22), 0.6);
            }
            float foam_line = 0.7 + 0.3 * sin(g_water_time * 1.2 + pixel.x * 0.11);
            if (inside < 1.1 && shore > 0.34 - 0.1 * foam_line) {
                color = mix(color, vec3(0.78, 0.90, 0.84), 0.55 * foam_line);
            } else if (inside < 2.1 && shore > 0.80 && mod(pixel.x + floor(g_water_time * 2.0), 3.0) < 2.0) {
                color = mix(color, vec3(0.66, 0.82, 0.76), 0.32);
            }
        }
        out_color = vec4(color, 1.0);
    } else if (distance_to_water < bank_width) {
        float d = distance_to_water;
        // Outward direction (dry side) from the distance gradient: tells which way the bank faces.
        vec2 texel = 1.0 / vec2(textureSize(bank_map, 0));
        vec2 grad = vec2(texture(bank_map, UV + vec2(texel.x * 2.0, 0.0)).r - texture(bank_map, UV - vec2(texel.x * 2.0, 0.0)).r,
                         texture(bank_map, UV + vec2(0.0, texel.y * 2.0)).r - texture(bank_map, UV - vec2(0.0, texel.y * 2.0)).r) * bank_width;
        // Land to the north = the far bank in the 3/4 view: we see its cut face, in shade.
        float far_bank = clamp(-grad.y * 0.5, 0.0, 1.0);
        // Light comes from the top left: shores facing it get a lit rim.
        float lit = clamp(dot(normalize(grad + vec2(0.001)), vec2(0.6, 0.8)) * 0.6 + 0.4, 0.0, 1.0);

        // Coherent random fields: how wide the bank is, and what it is made of.
        float wide = vnoise(pixel / 43.0) * 0.55 + vnoise(pixel / 17.0 + 9.0) * 0.30 + vnoise(pixel / 7.0 + 3.0) * 0.15;
        float edge = mix(5.5, 16.0, smoothstep(0.22, 0.78, wide));
        float mat = vnoise(pixel / 31.0 + vec2(21.0, 5.0)) * 0.7 + vnoise(pixel / 11.0 + vec2(2.0, 41.0)) * 0.3;
        mat += (bayer4(pixel) - 0.5) * 0.10;
        // 0 mud flat, 1 overgrown moss, 2 gravel bar with sand.
        int kind = mat < 0.36 ? 0 : (mat < 0.64 ? 1 : 2);

        vec2 cell = floor(pixel / vec2(5.0, 4.0));
        float rnd = hash21(cell);
        float speck = hash21(floor(pixel / vec2(2.0, 1.0)) + 71.0);
        vec3 col = vec3(0.0);
        float alpha = 1.0;
        bool paint = true;
        float dither = bayer4(pixel);

        if (d < edge) {
            float wet = 1.0 - smoothstep(0.0, 3.5 + 2.0 * (1.0 - lit), d);
            if (kind == 0) {
                // Damp plum-brown mud with a wet sheen towards the light and twig flecks.
                col = mix(vec3(0.40, 0.33, 0.31), vec3(0.27, 0.22, 0.26), wet);
                if (speck > 0.90) { col = mix(col, vec3(0.55, 0.46, 0.38), 0.7); }
                if (wet > 0.35 && lit > 0.55 && speck < 0.12) { col = mix(col, vec3(0.62, 0.63, 0.70), 0.45); }
                if (rnd > 0.86 && mod(pixel.x, 5.0) < 3.0 && mod(pixel.y, 4.0) < 1.0) { col = vec3(0.23, 0.18, 0.21); }
            } else if (kind == 1) {
                // Overgrown moss and clover in the game's grass ramp, darker towards the water.
                col = mix(vec3(0.24, 0.49, 0.34), vec3(0.18, 0.38, 0.30), wet);
                if (speck > 0.84) { col = mix(col, vec3(0.49, 0.73, 0.43), 0.8); }
                if (speck < 0.16) { col = mix(col, vec3(0.12, 0.26, 0.23), 0.85); }
                // Now and then a tiny bloom on the mossy shore: violet, pink or pale.
                float bloom = hash21(pixel + 91.0);
                if (bloom > 0.985 && d > 2.0) {
                    col = bloom > 0.995 ? vec3(0.93, 0.89, 0.76) : (bloom > 0.99 ? vec3(0.91, 0.66, 0.82) : vec3(0.66, 0.54, 0.94));
                }
            } else {
                // Gravel bar: warm silt and pebbles lit from the top left like the world's rocks.
                col = mix(vec3(0.52, 0.49, 0.42), vec3(0.36, 0.35, 0.36), wet);
                if (speck > 0.86) { col = mix(col, vec3(0.64, 0.60, 0.50), 0.7); }
                if (speck < 0.08) { col = mix(col, vec3(0.30, 0.28, 0.30), 0.8); }
                vec2 pc = floor(pixel / vec2(4.0, 3.0));
                vec2 local = pixel - pc * vec2(4.0, 3.0);
                float pr = hash21(pc + 2.0);
                float pw = 2.0 + floor(hash21(pc + 5.0) * 2.0);
                float px0 = floor(hash21(pc + 9.0) * (5.0 - pw));
                if (pr > 0.38 && local.x >= px0 && local.x < px0 + pw && local.y >= 0.0 && local.y < 2.0 + step(0.7, pr)) {
                    float row = local.y;
                    bool corner = (local.x == px0 && row == 0.0 && pw > 2.0);
                    if (!corner) {
                        float tone = hash21(pc + 17.0);
                        vec3 top = tone > 0.6 ? vec3(0.68, 0.66, 0.76) : (tone > 0.3 ? vec3(0.62, 0.58, 0.66) : vec3(0.70, 0.64, 0.52));
                        vec3 body = tone > 0.6 ? vec3(0.40, 0.37, 0.58) : (tone > 0.3 ? vec3(0.42, 0.40, 0.50) : vec3(0.48, 0.42, 0.36));
                        col = row < 1.0 ? top : (row < 2.0 ? body : body * 0.55);
                        if (local.x == px0 + pw - 1.0 && row > 0.0) { col *= 0.8; }
                    }
                }
            }
            // Waterline: a dark wet lip, deepest where the cut bank hangs over the water.
            if (d < 1.2) { col = mix(col, vec3(0.11, 0.10, 0.18), 0.72); }
            else if (d < 2.4 + far_bank * 2.0) { col *= 0.68 + 0.2 * lit; }
            // Far shore: a vertical earth face with hanging roots; the near shore gets a light rim.
            if (far_bank > 0.35 && d < 3.5) {
                col = mix(col, vec3(0.20, 0.15, 0.22), 0.55);
                if (hash21(vec2(floor(pixel.x / 2.0), 3.0)) > 0.62 && d > 1.0 && d < 3.0) { col = vec3(0.45, 0.33, 0.28); }
            } else if (lit > 0.72 && d > 1.8 && d < 3.2 && speck > 0.5) {
                col = mix(col, vec3(0.80, 0.78, 0.66), 0.28);
            }
            // The outer 3 px dither out into the meadow instead of ending on a hard line.
            float rim = clamp((d - (edge - 3.0)) / 3.0, 0.0, 1.0);
            if (dither < rim) { paint = false; }
        } else {
            paint = false;
        }
        // Wet ground: the grass beyond the bank darkens in a dithered halo, with taller, darker blades.
        if (!paint) {
            float halo_reach = edge + 3.0 + wide * 5.0;
            if (d < halo_reach) {
                float k = 1.0 - (d - edge + 3.0) / (halo_reach - edge + 3.0);
                if (dither < 0.55 * k) {
                    paint = true;
                    col = vec3(0.10, 0.24, 0.24);
                    alpha = 0.34 * k + 0.12;
                }
                // Tufts of tall wet grass, 1 px blades in 2-4 px stacks, leaning with the wind-less shore.
                vec2 tc = floor((pixel + vec2(floor(hash21(floor(pixel / 12.0)) * 5.0), 0.0)) / vec2(6.0, 5.0));
                float th = hash21(tc + 31.0);
                vec2 tl = pixel + vec2(floor(hash21(floor(pixel / 12.0)) * 5.0), 0.0) - tc * vec2(6.0, 5.0);
                float tall = 2.0 + floor(hash21(tc + 7.0) * 3.0);
                if (th > 0.74 && d > edge - 2.0 && d < edge + 7.0 && mod(tl.x + floor(th * 3.0), 2.0) < 1.0 && tl.y >= 4.0 - tall) {
                    float tip = (tl.y - (4.0 - tall)) / tall;
                    col = tip < 0.34 ? vec3(0.49, 0.73, 0.43) : (tip < 0.7 ? vec3(0.24, 0.49, 0.34) : vec3(0.13, 0.30, 0.26));
                    alpha = 1.0;
                    paint = true;
                }
            }
        }
        if (paint) { out_color = vec4(col, alpha); }
    }
    out_color.rgb = day_grade(out_color.rgb, pixel, 0.25);
    COLOR = out_color;
}
