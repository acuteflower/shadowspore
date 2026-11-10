shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
varying vec2 daylight_position;
// Flashes the sprite in `flash_color` (white by default). `flash` 1 = fully tinted, 0 = normal.
// `wound` 0..1 is how much blood she has lost: the colours drain towards a cool grey (the skin goes pale) and blood spreads over her body
// from a wound at the waist, following the baked `blood_map` of the current sheet. It starts gently and is strong at the end.

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float wound : hint_range(0.0, 1.0) = 0.0;
uniform float soak : hint_range(0.0, 1.0) = 0.0; // soaked from the water: darker, richer colours, glints on the lit pixels (Player._wet)
uniform float bandage : hint_range(0.0, 1.0) = 0.0; // 1 = draw the bandage (the pixels the blood map marks with alpha 254)
uniform sampler2D blood_map : filter_nearest, hint_default_white; // baked blood thresholds, same layout as the colour sheet (tools/art_hero3d.py blood)

void vertex() {
	daylight_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	if (wound > 0.0 && COLOR.a > 0.01) {
		float lum = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
		vec3 pale = vec3(lum * 0.93, lum * 0.98, lum * 1.06);
		COLOR.rgb = mix(COLOR.rgb, pale, wound * 0.6);
		vec4 map = texture(blood_map, UV);
		if (map.a > 0.5 && wound * 0.99 > map.r) {
			// blood lies on the cloth, the skin and the hair as they are shaded: the baked map says where (it grows from the wound), the colour
			// underneath keeps the form, so it is darker in the folds and wet and bright on the lit side; the outline stays ink
			float wet = smoothstep(0.5, 0.85, lum);
			vec3 blood = mix(vec3(0.22, 0.015, 0.05), vec3(0.5, 0.045, 0.1), smoothstep(0.1, 0.7, lum));
			blood = mix(blood, vec3(0.86, 0.26, 0.3), wet * 0.45);
			float ink = 1.0 - smoothstep(0.06, 0.16, lum);
			COLOR.rgb = mix(blood, COLOR.rgb * vec3(0.5, 0.3, 0.34), ink);
		}
	}
	if (bandage > 0.5 && COLOR.a > 0.01) {
		vec4 band_map = texture(blood_map, UV);
		if (band_map.a > 0.5 && band_map.a < 0.999) {
			// a wrap of old linen round the waist: the shading underneath keeps the form, a fine weave breaks it up, the outline stays ink
			float lum = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
			vec3 cloth = mix(vec3(0.40, 0.34, 0.33), vec3(0.95, 0.89, 0.80), smoothstep(0.04, 0.45, lum));
			vec2 px = UV * vec2(textureSize(blood_map, 0));
			if (mod(floor(px.x) + floor(px.y), 4.0) < 1.0) {
				cloth *= 0.86;
			}
			float ink = 1.0 - smoothstep(0.06, 0.16, lum);
			COLOR.rgb = mix(cloth, COLOR.rgb, ink * 0.8);
		}
	}
	if (soak > 0.0 && COLOR.a > 0.01) {
		float wl = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
		vec3 soaked = mix(vec3(wl), COLOR.rgb, 1.25) * 0.8;
		COLOR.rgb = mix(COLOR.rgb, soaked, soak * 0.85);
		vec2 wpx = floor(UV * vec2(textureSize(TEXTURE, 0)));
		if (wl > 0.55 && mod(wpx.x + wpx.y * 2.0, 7.0) < 1.0) {
			COLOR.rgb += vec3(0.1, 0.14, 0.14) * soak;
		}
	}
	COLOR.rgb = day_grade(COLOR.rgb, daylight_position, 1.0);
	COLOR.rgb = mix(COLOR.rgb, flash_color.rgb, flash);
}
