/**
 * Interactive Shadowspore World Map Engine.
 * WebGL2 shader renderer ported from assets/shaders/world_map.gdshader + map_veil.gdshaderinc,
 * paired with a high-contrast cartographic 2D overlay and automatic 2D Canvas fallback.
 */

import {
  WORLD_TILES,
  MAP_CELL,
  START_TILE,
  SUPERS,
  BIOMES_ORDER,
  BIOMES,
  WAYSTONES,
  VISTAS,
  WONDERS,
  WATCHTOWERS,
  BORDER_STONES,
  WATERMILLS,
  PIERS,
  ARENAS,
  HALLGRAT,
} from './map-data.mjs';

const VS_SRC = `#version 300 es
in vec2 a_pos;
out vec2 v_uv;
void main() {
  v_uv = a_pos * 0.5 + 0.5;
  v_uv.y = 1.0 - v_uv.y;
  gl_Position = vec4(a_pos, 0.0, 1.0);
}`;

const FS_SRC = `#version 300 es
precision highp float;

in vec2 v_uv;
out vec4 fragColor;

uniform vec2 u_res;
uniform vec2 u_center;
uniform float u_scale;
uniform float u_px_step;
uniform float u_world_tiles;
uniform float u_time;
uniform float u_mood;         // 0=night, 1=day, 2=bloodmoon
uniform float u_fog_mode;     // 0=open, 1=lantern fog
uniform vec2 u_cursor_tile;   // negative if inactive
uniform vec2 u_pulse_tile;    // negative if inactive
uniform float u_pulse_age;    // 0..1
uniform float u_active_super; // -1 or 0..2
uniform vec3 u_pal[21];       // 7 biomes * 3 tones (shadow, mid, highlight)
uniform float u_reveal_count;
uniform vec2 u_reveals[16];   // xy tile centers revealed

uniform sampler2D u_outer_sdf;
uniform sampler2D u_lakes_sdf;
uniform sampler2D u_water;
uniform sampler2D u_relief;
uniform sampler2D u_relief_field;
uniform sampler2D u_areas;
uniform sampler2D u_paths;

const vec3 VOID0 = vec3(0.018, 0.010, 0.036);
const vec3 VOID1 = vec3(0.042, 0.024, 0.078);
const vec3 VOID2 = vec3(0.076, 0.046, 0.138);
const vec3 VOID3 = vec3(0.118, 0.072, 0.215);
const vec3 VOID4 = vec3(0.175, 0.105, 0.315);
const vec3 VIO5  = vec3(0.353, 0.212, 0.722);
const vec3 VIO6  = vec3(0.541, 0.302, 1.000);
const vec3 VIO7  = vec3(0.690, 0.420, 1.000);
const vec3 VIO8  = vec3(0.925, 0.824, 1.000);
const vec3 INK   = vec3(0.068, 0.044, 0.112);

const vec3 LAKE_DEEP  = vec3(0.064, 0.130, 0.212);
const vec3 LAKE_MID   = vec3(0.112, 0.268, 0.342);
const vec3 LAKE_SHELF = vec3(0.205, 0.405, 0.438);
const vec3 LAKE_LIGHT = vec3(0.502, 0.742, 0.706);

const float BAYER[16] = float[16](
   0.0,  8.0,  2.0, 10.0,
  12.0,  4.0, 14.0,  6.0,
   3.0, 11.0,  1.0,  9.0,
  15.0,  7.0, 13.0,  5.0
);

// 5x5 hand-inked cartographer symbols per biome (from assets/shaders/world_map.gdshader)
const uint GLYPHS[14] = uint[14](
  146080u, 135620u,
  32969156u, 163268u,
  33073280u, 145860u,
  14815374u, 18400814u,
  4543812u, 18157905u,
  17978692u, 476608u,
  19285440u, 32986244u
);
const float DENSITY[7] = float[7](0.34, 0.50, 0.40, 0.40, 0.45, 0.40, 0.38);

float invs(float lo, float hi, float x) {
  return 1.0 - smoothstep(lo, hi, x);
}

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
    mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
    u.y
  );
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * vnoise(p);
    p = p * 2.03 + vec2(13.7, 7.1);
    a *= 0.5;
  }
  return v / 0.9375;
}

float bayer(vec2 p) {
  int x = int(mod(floor(p.x), 4.0));
  int y = int(mod(floor(p.y), 4.0));
  return BAYER[y * 4 + x] / 16.0;
}

vec3 biomeColor(int idx, int toneIdx) {
  int i = clamp(idx, 0, 6) * 3 + clamp(toneIdx, 0, 2);
  return u_pal[i];
}

int areaRaw(vec2 t) {
  if (t.x < 0.0 || t.y < 0.0 || t.x >= u_world_tiles || t.y >= u_world_tiles) return -1;
  vec2 u = clamp(t / u_world_tiles, vec2(0.0005), vec2(0.9995));
  int raw = int(floor(texture(u_areas, u).r * 255.0 + 0.5));
  return raw - 1; // -1 = unset, 0 = Die Lichtung, 1 = Hexenwald, 2 = Sonnenquarz-Oede
}

int areaAt(vec2 t) {
  int a = areaRaw(t);
  if (a >= 0) return a;
  int n0 = areaRaw(t + vec2( 3.5,  0.0)); if (n0 >= 0) return n0;
  int n1 = areaRaw(t + vec2(-3.5,  0.0)); if (n1 >= 0) return n1;
  int n2 = areaRaw(t + vec2( 0.0,  3.5)); if (n2 >= 0) return n2;
  int n3 = areaRaw(t + vec2( 0.0, -3.5)); if (n3 >= 0) return n3;
  int n4 = areaRaw(t + vec2( 7.0,  0.0)); if (n4 >= 0) return n4;
  int n5 = areaRaw(t + vec2(-7.0,  0.0)); if (n5 >= 0) return n5;
  int n6 = areaRaw(t + vec2( 0.0,  7.0)); if (n6 >= 0) return n6;
  int n7 = areaRaw(t + vec2( 0.0, -7.0)); if (n7 >= 0) return n7;
  return 0;
}

// Organic multi-scale domain warp breaks up grid-stepped superregion borders (e.g. Sonnenquarz-Oede / Die Lichtung)
vec2 areaWarpCoord(vec2 t) {
  vec2 slow = vec2(
    fbm(t * 0.015 + vec2(3.1, 8.4)) - 0.5,
    fbm(t * 0.015 + vec2(17.9, 2.3)) - 0.5
  ) * 24.0;
  vec2 mid = vec2(
    vnoise(t * 0.085 + vec2(5.2, 1.7)) - 0.5,
    vnoise(t * 0.085 + vec2(9.4, 14.1)) - 0.5
  ) * 7.0;
  return t + slow + mid;
}

int areaWarped(vec2 t) {
  return areaAt(areaWarpCoord(t));
}

int biomeForArea(int areaId) {
  if (areaId == 1) return 5;
  if (areaId == 2) return 6;
  return 0;
}

float sampleCoast(vec2 t) {
  vec2 u = t / u_world_tiles;
  if (u.x < 0.0 || u.x > 1.0 || u.y < 0.0 || u.y > 1.0) return -24.0;
  float sd = (texture(u_outer_sdf, u).r * 255.0 - 128.0) / 8.0;
  return sd + (vnoise(t * 0.35) - 0.5) * 1.3 + (vnoise(t * 1.1) - 0.5) * 0.45;
}

float sampleHeight(vec2 t) {
  vec2 u = clamp(t / u_world_tiles, vec2(0.0005), vec2(0.9995));
  vec3 f = texture(u_relief_field, u).rgb;
  return f.r + f.g + f.b;
}

bool glyphBit(uint g, ivec2 l) {
  if (l.x < 0 || l.y < 0 || l.x > 4 || l.y > 4) return false;
  return ((g >> uint(l.y * 5 + l.x)) & 1u) == 1u;
}

vec3 drawSymbols(vec3 col, vec2 w, vec2 p, float sc, float cDist) {
  float lod = clamp(floor(log2(max(0.45, sc) / 0.45)), 0.0, 2.0);
  float spacing = 28.0 / exp2(lod);
  vec2 cell = floor(w / spacing);
  float fade = smoothstep(0.42, 0.72, sc);
  for (int oy = -1; oy <= 1; oy++) {
    for (int ox = -1; ox <= 1; ox++) {
      vec2 cg = cell + vec2(float(ox), float(oy));
      float h = hash21(cg + lod * 31.0);
      vec2 at = (cg + vec2(0.22) + 0.56 * vec2(hash21(cg + 5.0), hash21(cg + 9.0))) * spacing;
      vec2 atUv = at / u_world_tiles;
      if (atUv.x < 0.0 || atUv.x > 1.0 || atUv.y < 0.0 || atUv.y > 1.0) continue;
      int ab = biomeForArea(areaWarped(at));
      if (h > DENSITY[ab] * fade) continue;

      vec2 sp = floor(((at - u_center) * sc + u_res * 0.5) / u_px_step);
      ivec2 l = ivec2(p - sp) + ivec2(2);
      if (l.x < -1 || l.y < -1 || l.x > 5 || l.y > 5) continue;

      vec3 f = texture(u_relief_field, atUv).rgb;
      float nearCliff = min(min(abs(f.r - 0.5), abs(f.g - 0.5)), abs(f.b - 0.5));
      float lakeD = (128.0 - texture(u_lakes_sdf, atUv).r * 255.0) / 8.0;
      if (cDist < 4.5 || nearCliff < 0.16 || lakeD > -2.0 || texture(u_water, atUv).r > 0.04 || texture(u_paths, atUv).r > 0.08) continue;

      uint g = GLYPHS[ab * 2 + (hash21(cg + 3.0) > 0.5 ? 1 : 0)];
      if (glyphBit(g, l)) return mix(col, biomeColor(ab, 2), 0.34);
      if (glyphBit(g, l - ivec2(1, 1))) return mix(col, INK, 0.24);
    }
  }
  return col;
}

vec3 voidSmoke(vec2 w, vec2 p, float depth, float isDay, float isBlood) {
  vec2 q = w * 0.017;
  vec2 flow = vec2(u_time * 0.008, -u_time * 0.005);
  float a = fbm(q + flow + 2.2 * vec2(fbm(q * 0.6 - flow), fbm(q * 0.6 + 3.0 + flow)));
  float t = a * 5.0 - 1.0 + (1.0 - depth) * 1.45 + (bayer(p) - 0.5) * 0.85;
  int k = int(clamp(floor(t), 0.0, 4.0));
  vec3 c = k == 0 ? VOID0 : (k == 1 ? VOID1 : (k == 2 ? VOID2 : (k == 3 ? VOID3 : VOID4)));
  float b = fbm(q * 1.6 - flow * 1.8 + 9.0);
  float ridge = 1.0 - smoothstep(0.0, 0.018, abs(b - 0.5));
  if (ridge > 0.45 && bayer(p + 1.0) < 0.72) {
    vec3 ridgeTint = mix(VIO5, vec3(0.75, 0.22, 0.42), isBlood);
    c = mix(c, ridgeTint, 0.38 + 0.16 * (1.0 - depth));
  }
  c = mix(c, c * vec3(1.18, 1.15, 1.24) + vec3(0.015, 0.012, 0.03), isDay);
  if (isBlood > 0.1) c = mix(c, c * vec3(1.35, 0.68, 0.80) + vec3(0.028, 0.004, 0.012), isBlood * 0.85);
  return c;
}

vec3 drawLakeWaves(vec3 col, vec2 w, vec2 p, vec3 lightCol) {
  float lod = clamp(floor(log2(max(0.35, u_scale) / 0.32)), 0.0, 2.0);
  float spacing = 52.0 / exp2(lod);
  vec2 cell = floor(w / spacing);
  for (int oy = -1; oy <= 1; oy++) {
    for (int ox = -1; ox <= 1; ox++) {
      vec2 cg = cell + vec2(float(ox), float(oy));
      float seed = hash21(cg + lod * 29.0 + 81.0);
      if (seed < 0.52) continue;
      vec2 at = (cg + vec2(0.24) + vec2(hash21(cg + 32.0), hash21(cg + 67.0)) * 0.52) * spacing;
      vec2 local = p - floor(((at - u_center) * u_scale + u_res * 0.5) / u_px_step);
      if (abs(local.x) > 3.0 || local.y < -1.0 || local.y > 2.0) continue;
      vec2 atUv = at / u_world_tiles;
      if (atUv.x < 0.0 || atUv.x > 1.0 || atUv.y < 0.0 || atUv.y > 1.0) continue;
      float inset = (128.0 - texture(u_lakes_sdf, atUv).r * 255.0) / 8.0;
      if (inset * u_scale < 5.5) continue;
      bool crest = (local.y == 0.0 && local.x >= -3.0 && local.x <= -1.0) || (local.y == -1.0 && local.x >= 0.0 && local.x <= 2.0);
      bool echo = local.y == 2.0 && local.x >= 0.0 && local.x <= 2.0;
      float shimmer = 0.78 + 0.22 * sin(u_time * 0.75 + seed * 6.283);
      if (crest) return mix(col, lightCol, 0.40 * shimmer);
      if (echo) return mix(col, lightCol, 0.20 * shimmer);
    }
  }
  return col;
}

vec3 lakeInk(vec2 w, vec2 p, float basin, float isDay, float isBlood) {
  float depth = clamp((basin - 0.10) / 0.90, 0.0, 1.0);
  float pigment = vnoise(w * 0.05 + 17.0) * 0.6 + vnoise(w * 0.018) * 0.4;
  depth = clamp(depth + (pigment - 0.5) * 0.14, 0.0, 1.0);
  float tone = floor(clamp(depth * 3.99 + (bayer(p) - 0.5) * 0.24, 0.0, 3.0));

  vec3 lDeep  = mix(LAKE_DEEP,  vec3(0.10, 0.22, 0.34), isDay * 0.65);
  vec3 lMid   = mix(LAKE_MID,   vec3(0.16, 0.38, 0.46), isDay * 0.65);
  vec3 lShelf = mix(LAKE_SHELF, vec3(0.28, 0.54, 0.56), isDay * 0.65);
  vec3 lLight = mix(LAKE_LIGHT, vec3(0.62, 0.85, 0.80), isDay * 0.65);

  if (isBlood > 0.1) {
    lDeep  = mix(lDeep,  vec3(0.12, 0.03, 0.09), isBlood * 0.85);
    lMid   = mix(lMid,   vec3(0.26, 0.07, 0.16), isBlood * 0.85);
    lShelf = mix(lShelf, vec3(0.42, 0.13, 0.25), isBlood * 0.82);
    lLight = mix(lLight, vec3(0.84, 0.34, 0.48), isBlood * 0.82);
  }

  vec3 ink = lShelf;
  if (tone >= 1.0) ink = lMid;
  if (tone >= 2.0) ink = mix(lMid, lDeep, 0.52);
  if (tone >= 3.0) ink = lDeep;

  float dist = (128.0 - texture(u_lakes_sdf, w / u_world_tiles).r * 255.0) / 8.0;
  float insetPx = max(dist, 0.0) * u_scale;
  float e = max(1.0, 0.9 / max(0.35, u_scale));
  vec2 grad = vec2(
    texture(u_lakes_sdf, (w + vec2(e, 0.0)) / u_world_tiles).r - texture(u_lakes_sdf, (w - vec2(e, 0.0)) / u_world_tiles).r,
    texture(u_lakes_sdf, (w + vec2(0.0, e)) / u_world_tiles).r - texture(u_lakes_sdf, (w - vec2(0.0, e)) / u_world_tiles).r
  );
  float light = 0.5 + 0.5 * dot(grad / max(length(grad), 0.0001), normalize(vec2(-0.6, -0.8)));
  float shelfBand = 1.0 - smoothstep(0.4, 5.2, max(dist, 0.0));
  ink = mix(ink, lShelf, shelfBand * 0.58);

  // Sunlit top-left water lip vs shadowed bank
  float rim = 1.0 - smoothstep(0.15, 1.35, insetPx);
  ink = mix(ink, mix(INK, lLight, light), rim * 0.78);

  // Delicate broken contour curve inside lakes
  float contour = 1.0 - smoothstep(0.2, 0.75, abs(insetPx - 2.6));
  float broken = smoothstep(0.30, 0.65, vnoise(w * 0.18 + 4.0));
  ink = mix(ink, lLight, contour * broken * 0.22 * (1.0 - smoothstep(1.3, 2.8, u_scale)));

  return drawLakeWaves(ink, w, p, lLight);
}

void main() {
  float pxStep = max(1.0, u_px_step);
  vec2 px = gl_FragCoord.xy;
  vec2 screenPx = vec2(px.x, u_res.y - px.y);
  // Crisp art-pixel coordinate matching Shadowspore in-game cartography
  vec2 p = floor(screenPx / pxStep);
  vec2 artScreen = (p + 0.5) * pxStep;
  vec2 tile = (artScreen - u_res * 0.5) / u_scale + u_center;
  vec2 uv = tile / u_world_tiles;

  float isDay = smoothstep(0.3, 0.8, 1.0 - abs(u_mood - 1.0));
  float isBlood = smoothstep(1.3, 1.8, u_mood);

  float c = sampleCoast(tile);
  float ds = c * u_scale;

  // 1. OUTER VOID & COASTAL RIPPLES (No random dot speckles!)
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || c <= 0.0) {
    float outsideDist = max(0.0, -c);
    float voidDepth = smoothstep(6.0, 90.0, outsideDist);
    vec3 col = voidSmoke(tile, p, voidDepth, isDay, isBlood);

    // Three gentle undulating cartographer ripples following the organic coast
    float wavePhase = sin(outsideDist * 0.42 - u_time * 0.9) * 0.35;
    float ripPx = -ds;
    float rip1 = abs(fract((ripPx - 3.5 + wavePhase) / 9.0 + 0.5) - 0.5) * 9.0;
    if (ripPx > 2.5 && ripPx < 25.0 && rip1 < 0.75 && mod(p.x + p.y, 3.0) < 2.0) {
      vec3 ripTint = mix(VIO5, vec3(0.84, 0.24, 0.40), isBlood * 0.85);
      col = mix(col, ripTint, 0.52 * (1.0 - (ripPx - 2.5) / 22.5));
    }

    // Soft coastal amethyst aura
    float halo = invs(0.0, 6.5, outsideDist);
    vec3 haloTint = mix(mix(VIO6, vec3(0.30, 0.86, 0.76), 0.28), vec3(0.92, 0.24, 0.38), isBlood * 0.85);
    col = mix(col, haloTint, halo * 0.28);

    // Subtle viewport edge vignette
    vec2 edgeN = screenPx / u_res;
    float vig = smoothstep(0.0, 0.28, min(min(edgeN.x, 1.0 - edgeN.x), min(edgeN.y, 1.0 - edgeN.y)));
    col *= mix(0.66, 1.0, vig);

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
    return;
  }

  // 2. WARPED ORGANIC REGION LOOKUP + SMOOTH BIOME ECOTONE BLEND
  vec2 aw = areaWarpCoord(tile);
  int areaId = areaAt(aw);
  int biomeIdx = biomeForArea(areaId);

  // Blend slightly across warped territory frontier to remove harsh pixel staircases
  int aN = areaAt(aw + vec2( 0.0, -5.0));
  int aS = areaAt(aw + vec2( 0.0,  5.0));
  int aW = areaAt(aw + vec2(-5.0,  0.0));
  int aE = areaAt(aw + vec2( 5.0,  0.0));
  float borderHits = float(aN != areaId) + float(aS != areaId) + float(aW != areaId) + float(aE != areaId);
  int blendBiome = biomeIdx;
  if (aN != areaId) blendBiome = biomeForArea(aN);
  else if (aS != areaId) blendBiome = biomeForArea(aS);
  else if (aW != areaId) blendBiome = biomeForArea(aW);
  else if (aE != areaId) blendBiome = biomeForArea(aE);

  float e = max(1.4, 1.2 / max(0.35, u_scale));
  float h = sampleHeight(tile);
  float lit = sampleHeight(tile + vec2(e)) - sampleHeight(tile - vec2(e));
  float grain = (fbm(tile * 0.055) - 0.5) * 0.36 + (vnoise(tile * 0.52) - 0.5) * 0.12;
  float v = 0.42 + 0.11 * h + lit * 0.58 + grain;
  int tone = int(clamp(floor(v * 3.0 + (bayer(p) - 0.5) * 0.88), 0.0, 2.0));

  vec3 col = biomeColor(biomeIdx, tone);
  if (blendBiome != biomeIdx && bayer(p) < borderHits * 0.18) {
    col = biomeColor(blendBiome, tone);
  }

  // 3. RAZOR-SHARP INKED CLIFF CONTOURS & DITHERED CAST SHADOWS
  float pixStepW = pxStep / max(0.35, u_scale);
  vec3 f  = texture(u_relief_field, uv).rgb;
  vec3 fx = texture(u_relief_field, clamp((tile + vec2(pixStepW, 0.0)) / u_world_tiles, vec2(0.0005), vec2(0.9995))).rgb;
  vec3 fy = texture(u_relief_field, clamp((tile + vec2(0.0, pixStepW)) / u_world_tiles, vec2(0.0005), vec2(0.9995))).rgb;
  float best = 99.0;
  float side = 0.0;
  for (int k = 0; k < 3; k++) {
    float cVal = f[k] - 0.5 + (vnoise(tile * 0.42 + float(k) * 11.0) - 0.5) * 0.10;
    float g = max(length(vec2(fx[k] - f[k], fy[k] - f[k])), 0.0045);
    float d = abs(cVal) / g;
    if (d < best) {
      best = d;
      side = cVal;
    }
  }
  float band = 1.6 + 1.1 * u_scale;
  if (side < 0.0 && best < band && bayer(p) < (1.0 - best / band) * 0.85) {
    col = mix(col, biomeColor(biomeIdx, 0) * 0.72, 0.72);
  } else if (side > 0.0 && best < 1.65) {
    col = mix(col, biomeColor(biomeIdx, 2), 0.28);
  }
  if (best < 0.78) {
    col = mix(INK, biomeColor(biomeIdx, 0), 0.24);
  }

  // Ramps, staircases & wall faces from baked relief
  vec4 rel = texture(u_relief, uv);
  int kind = int(floor(rel.g * 255.0 + 0.5)) & 15;
  if (kind == 1) {
    col = mix(col * 0.74, INK, 0.24);
  } else if (u_scale > 0.72 && kind >= 2 && kind <= 4 && mod(p.y + floor(p.x * 0.5), 3.0) < 2.0) {
    col = mix(col, vec3(0.84, 0.74, 0.60), 0.70);
  }

  // Subtle etched 5x5 flora/quartz/pine cartographer symbols on flat plateaus
  if (u_scale > 0.46 && best > 1.6) {
    col = drawSymbols(col, tile, p, u_scale, c);
  }

  // 4. ANCIENT TRAILS & CARAVAN PATHS
  float pathCov = texture(u_paths, uv).r;
  if (pathCov > 0.05) {
    vec3 roadCol = (biomeIdx == 6) ? vec3(0.88, 0.74, 0.50) : vec3(0.76, 0.66, 0.52);
    if (isDay < 0.4) roadCol = mix(roadCol, roadCol * 0.84, 0.6);
    float pMask = smoothstep(0.08, 0.65, pathCov);
    col = mix(col, roadCol, pMask * 0.64);
  }

  // 5. FINE ENGRAVED TERRITORY STITCH BORDER
  bool frontier =
    areaWarped(tile + vec2(pixStepW, 0.0)) != areaId ||
    areaWarped(tile + vec2(0.0, pixStepW)) != areaId;
  if (frontier && c > 2.6 && mod(p.x + p.y, 4.0) < 2.0) {
    vec3 dashCol = mix(VIO8, vec3(0.95, 0.80, 0.52), float(biomeIdx == 6) * 0.5);
    col = mix(col, dashCol, 0.58);
  }

  // 6. CARTOGRAPHER LAKES & TRIBUTARY RIVERS
  vec3 waterInfo = texture(u_water, uv).rgb;
  float lakeSdf = texture(u_lakes_sdf, uv).r;
  float lakeInset = (128.0 - lakeSdf * 255.0) / 8.0;
  float riverCov = waterInfo.r;
  float lakeDepth = waterInfo.b;
  bool inLake = (lakeInset > 0.0) || (lakeDepth > 0.10);

  if (inLake) {
    float basinVal = max(lakeDepth, clamp(lakeInset / 10.0, 0.14, 1.0));
    vec3 wCol = lakeInk(tile, p, basinVal, isDay, isBlood);
    float lMask = max(smoothstep(-0.35, 0.45, lakeInset), smoothstep(0.08, 0.20, lakeDepth));
    col = mix(col, wCol, lMask);
  } else {
    float neighbour = max(
      max(texture(u_water, clamp((tile + vec2(e, 0.0)) / u_world_tiles, 0.0005, 0.9995)).r,
          texture(u_water, clamp((tile - vec2(e, 0.0)) / u_world_tiles, 0.0005, 0.9995)).r),
      max(texture(u_water, clamp((tile + vec2(0.0, e)) / u_world_tiles, 0.0005, 0.9995)).r,
          texture(u_water, clamp((tile - vec2(0.0, e)) / u_world_tiles, 0.0005, 0.9995)).r)
    );
    float coverage = smoothstep(0.03, 0.60, riverCov);
    float bank = smoothstep(0.04, 0.45, neighbour) * (1.0 - coverage);
    col = mix(col, INK, bank * 0.48);
    if (coverage > 0.02) {
      vec3 rShallow = mix(LAKE_SHELF, vec3(0.28, 0.56, 0.58), isDay * 0.7);
      vec3 rDeep    = mix(LAKE_DEEP,  vec3(0.11, 0.25, 0.38), isDay * 0.7);
      if (isBlood > 0.1) {
        rShallow = mix(rShallow, vec3(0.45, 0.14, 0.26), isBlood * 0.8);
        rDeep    = mix(rDeep,    vec3(0.18, 0.04, 0.12), isBlood * 0.85);
      }
      vec3 rCol = mix(rShallow, rDeep, smoothstep(0.15, 0.88, waterInfo.g));
      float rimLight = (1.0 - smoothstep(0.3, 0.92, riverCov)) * coverage;
      rCol = mix(rCol, LAKE_LIGHT, rimLight * 0.34);
      col = mix(col, rCol, coverage * 0.94);
    }
  }

  // 7. ILLUMINATED COASTLINE RIM & INNER INK BANK
  if (ds < 1.25 * pxStep) {
    vec3 rimCol = mix(VIO7, VIO8, 0.38);
    if (isDay > 0.3) rimCol = mix(rimCol, vec3(0.76, 0.96, 0.88), 0.35);
    if (isBlood > 0.2) rimCol = mix(rimCol, vec3(0.98, 0.34, 0.48), isBlood * 0.85);
    col = rimCol;
  } else if (ds < 2.8 * pxStep && bayer(p) < 0.68) {
    col = mix(col, INK, 0.62);
  }

  // 8. MOOD GRADING & ACTIVE REGION FOCUS
  vec3 moodGrade = mix(vec3(0.95, 0.97, 1.04), vec3(1.10, 1.08, 1.00), isDay);
  moodGrade = mix(moodGrade, vec3(1.08, 0.72, 0.84), isBlood);
  col *= moodGrade;

  if (u_active_super >= -0.2) {
    float sid = float(areaId);
    if (abs(sid - u_active_super) < 0.3) col *= 1.12;
    else col *= 0.68;
  }

  // 9. LANTERN FOG MODE ("Laternen-Nebel")
  if (u_fog_mode > 0.5) {
    float vis = 0.0;
    for (int i = 0; i < 16; i++) {
      if (float(i) >= u_reveal_count) break;
      vis = max(vis, invs(48.0, 110.0, distance(tile, u_reveals[i])));
    }
    if (u_cursor_tile.x >= 0.0) {
      vis = max(vis, invs(24.0, 86.0, distance(tile, u_cursor_tile)));
    }
    float veil = 1.0 - vis;
    if (veil > 0.02) {
      vec3 fogTone = voidSmoke(tile, p, veil, isDay, isBlood);
      if (bayer(p) < clamp(veil * 1.05, 0.0, 1.0)) {
        col = mix(col, fogTone, 0.90);
      }
    }
  }

  // 10. WARM CURSOR LANTERN & WAYSTONE SHOCKWAVE
  if (u_cursor_tile.x >= 0.0) {
    float lantern = invs(0.0, 58.0, distance(tile, u_cursor_tile));
    col += vec3(0.11, 0.09, 0.16) * lantern * (1.0 - isDay * 0.6);
  }
  if (u_pulse_tile.x >= 0.0 && u_pulse_age > 0.0 && u_pulse_age < 1.0) {
    float pd = distance(tile, u_pulse_tile);
    float rad = u_pulse_age * 240.0;
    float wave = invs(0.0, 16.0, abs(pd - rad)) * (1.0 - u_pulse_age);
    col += vec3(0.31, 0.92, 0.84) * wave * 0.95;
  }

  // Subtle viewport vignette
  vec2 edgeN = screenPx / u_res;
  float vig = smoothstep(0.0, 0.24, min(min(edgeN.x, 1.0 - edgeN.x), min(edgeN.y, 1.0 - edgeN.y)));
  col *= mix(0.70, 1.0, vig);

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}`;

function hexToVec3(hex) {
  const clean = String(hex || '#5fb36b').replace('#', '');
  const n = parseInt(clean, 16);
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
}

function buildPaletteArray() {
  const lerp3 = (a, b, t) => [
    a[0] + (b[0] - a[0]) * t,
    a[1] + (b[1] - a[1]) * t,
    a[2] + (b[2] - a[2]) * t,
  ];
  const out = [];
  for (const key of BIOMES_ORDER) {
    if (key === 'meadow') {
      // Curated Shadowspore docs/design_guide.md emerald meadow tones
      out.push(...hexToVec3('#22483c'), ...hexToVec3('#387654'), ...hexToVec3('#6cb46a'));
      continue;
    }
    if (key === 'witch_forest') {
      out.push(...hexToVec3('#1b1d34'), ...hexToVec3('#34415e'), ...hexToVec3('#617496'));
      continue;
    }
    if (key === 'quartz_desert') {
      out.push(...hexToVec3('#422926'), ...hexToVec3('#97613e'), ...hexToVec3('#e2b36c'));
      continue;
    }
    const base = hexToVec3(BIOMES[key]?.color || '#5fb36b');
    const c0 = lerp3(base, [0.055, 0.036, 0.11], 0.68);
    const c1 = lerp3(base, [0.14, 0.11, 0.25], 0.36);
    const c2 = lerp3(base, [0.92, 0.89, 1.0], 0.22);
    out.push(...c0, ...c1, ...c2);
  }
  return new Float32Array(out);
}

const PIN_STYLES = {
  waymark: { label: 'Wegzeichen', color: '#4fe3c1', symbol: '◆' },
  danger: { label: 'Gefahr', color: '#ff6b7b', symbol: '▲' },
  target: { label: 'Ziel', color: '#f2c36b', symbol: '★' },
  camp: { label: 'Lager', color: '#b48bff', symbol: '⚑' },
  event: { label: 'Server-Event', color: '#ffd86b', symbol: '✦' },
};

export class WorldMapEngine {
  constructor({
    stageEl,
    glCanvas,
    overlayCanvas,
    onHover = () => {},
    onSelect = () => {},
    onCamera = () => {},
    onCustomPinsChange = () => {},
    onPickCoord = null,
  }) {
    this.stage = stageEl;
    this.glCanvas = glCanvas;
    this.overlayCanvas = overlayCanvas;
    this.octx = overlayCanvas.getContext('2d');
    this.onHover = onHover;
    this.onSelect = onSelect;
    this.onCamera = onCamera;
    this.onCustomPinsChange = onCustomPinsChange;
    this.onPickCoord = onPickCoord;

    this.center = { x: 525, y: 520 };
    this.targetCenter = { x: 525, y: 520 };
    this.scale = 0.72;
    this.targetScale = 0.72;
    this.velocity = { x: 0, y: 0 };
    this.minScale = 0.36;
    this.maxScale = 4.6;

    this.mood = 'night';
    this.fogMode = false;
    this.paused = false;
    this.reducedMotion = false;
    this.time = 0;
    this.lastFrame = 0;
    this.rafId = 0;

    this.cursorScreen = { x: -1, y: -1, inside: false };
    this.cursorTile = { x: -1, y: -1 };
    this.hoveredFeature = null;
    this.selectedFeature = null;
    this.activeSuper = -1;
    this.pinTool = ''; // '' or 'waymark' | 'danger' | 'target' | 'camp' | 'pick'
    this.pickCallback = null;

    this.awakenedWaystones = new Set(['ebene_wachterin', 'glaskamm_wachterin']);
    this.pulse = { x: -1, y: -1, age: 0 };
    this.tour = null;
    this.playerCloudDay = null;

    this.layers = {
      waystones: false,
      wonders: true,
      arenas: true,
      hallgrat: true,
      vistas: false,
      orders: false,
      custom: true,
      admin: true,
    };

    this.customPins = this.loadCustomPins();
    this.adminPins = [];
    this.areasBytes = null;
    this.reliefBytes = null;

    this.gl = null;
    this.program = null;
    this.textures = {};
    this.texturesReady = false;
    this.fallbackCanvas = null;

    this.pointers = new Map();
    this.dragMoved = false;
    this.dragSample = null;
    this.keysHeld = new Set();

    this.features = this.buildFeatureIndex();
    this.bindEvents();
    this.initRenderer();
    this.resize();
  }

  loadCustomPins() {
    try {
      const raw = localStorage.getItem('shadowspore_map_pins_v1');
      const parsed = JSON.parse(raw || '[]');
      return Array.isArray(parsed) ? parsed.slice(0, 24) : [];
    } catch {
      return [];
    }
  }

  saveCustomPins() {
    try {
      localStorage.setItem('shadowspore_map_pins_v1', JSON.stringify(this.customPins));
    } catch {
      // Ignore storage quota errors
    }
    this.onCustomPinsChange(this.customPins);
  }

  setAdminPins(pins) {
    this.adminPins = Array.isArray(pins) ? pins : [];
  }

  setPlayerCloudInfo(info) {
    this.playerCloudDay = info && typeof info.day === 'number' ? info.day : null;
  }

  buildFeatureIndex() {
    const list = [];
    list.push({
      id: 'start_home',
      kind: 'start',
      category: 'Lagerfeuer · Start',
      name: 'Glimmrast — Dein Lagerfeuer',
      sub: 'DIE LICHTUNG · ANKUNFTSORT',
      tile: [...START_TILE],
      desc: 'Hier erwachst du am Rand der Lichtung. Errichte Laternen, bestelle Felder bei Tag und verteidige deinen Hof in der Nacht.',
      minZoom: 0,
      image: './img/daylight_golden.png',
    });

    list.push({
      id: 'hallgrat_city',
      kind: 'hallgrat',
      category: 'Stille Stadt',
      name: `${HALLGRAT.name} · ${HALLGRAT.title}`,
      sub: 'GLASKAMM · WESTKÜSTE',
      tile: [...HALLGRAT.tile],
      desc: HALLGRAT.about,
      districts: HALLGRAT.districts,
      bounds: HALLGRAT.bounds,
      minZoom: 0,
      image: './img/hallgrat.png',
    });

    for (const w of WAYSTONES) {
      list.push({
        id: w.id,
        kind: 'waystone',
        category: 'Wächterin · Schnellreise',
        name: w.name,
        sub: w.paved ? 'GEPFLASTERTER WEGSTEIN' : 'SCHLAFENDE WÄCHTERSTATUE',
        tile: [...w.tile],
        desc: 'Erwecke diese Wächterin, um den Nebel des Vergessens zurückzudrängen und über das Leylinien-Netz zu reisen.',
        minZoom: 0,
      });
    }

    for (const wn of WONDERS) {
      list.push({
        id: wn.id,
        kind: 'wonder',
        category: 'Weltwunder',
        name: wn.name,
        sub: wn.sub,
        tile: [...wn.tile],
        desc: 'Einmaliges Weltwunder der Wiesenlande mit legendärer Segens-Truhe und leuchtendem Sporen-Echo.',
        minZoom: 0,
      });
    }

    for (const ar of ARENAS) {
      list.push({
        id: ar.id,
        kind: 'arena',
        category: 'Boss-Arena',
        name: ar.name,
        sub: ar.sub,
        tile: [...ar.tile],
        desc: `Wächter-Boss: ${ar.boss} (${ar.superName}). Eine offene Kampfarena voller Quarz- oder Spiegelfallen.`,
        minZoom: 0,
        image: ar.boss === 'Aurelith' ? './img/sternensaal.png' : './img/blutmond.png',
      });
    }

    for (const v of VISTAS) {
      list.push({
        id: v.id,
        kind: 'vista',
        category: 'Aussichtskanzel',
        name: v.name,
        sub: v.sub,
        tile: [...v.tile],
        desc: 'Ein hoher Raststein über der Landschaft — schenkt Weitblick und deckt umliegende Kacheln auf.',
        minZoom: 0.72,
      });
    }

    for (const wt of WATCHTOWERS) {
      list.push({
        id: wt.id,
        kind: 'order',
        category: wt.speaker || 'Roter Orden',
        name: wt.name,
        sub: wt.sub,
        tile: [...wt.tile],
        desc: wt.text,
        thought: wt.thought,
        minZoom: 0.72,
      });
    }

    for (const st of BORDER_STONES) {
      list.push({
        id: st.id,
        kind: 'order',
        category: st.speaker || 'Grenzstein',
        name: st.speaker || 'Alter Grenzstein',
        sub: 'INSCHRIFT DES ROTEN ORDENS',
        tile: [...st.tile],
        desc: st.text,
        thought: st.thought,
        minZoom: 1.05,
      });
    }

    for (const wm of WATERMILLS) {
      list.push({
        id: wm.id,
        kind: 'watermill',
        category: 'Alte Wassermühle',
        name: wm.name,
        sub: wm.sub,
        tile: [...wm.tile],
        desc: 'Am Flussufer gebaute Steinmühle, deren Mühlrad wieder befreit werden kann.',
        minZoom: 0.85,
      });
    }

    for (const p of PIERS) {
      list.push({
        id: p.id,
        kind: 'pier',
        category: 'Fischersteg',
        name: 'Stiller Bootsteg',
        sub: 'UFERPLATZ & ANGELGEWÄSSER',
        tile: [...p.tile],
        desc: 'Verlassener Holzsteg mit kleinem Ruderboot und leuchtenden Schwimmern.',
        minZoom: 1.15,
        image: './img/fishing.png',
      });
    }

    return list;
  }

  initRenderer() {
    const gl = this.glCanvas.getContext('webgl2', {
      alpha: false,
      antialias: false,
      depth: false,
      preserveDrawingBuffer: false,
    });
    if (gl) {
      this.gl = gl;
      this.setupWebGL(gl);
    }
    this.loadWorldTextures();
  }

  compileShader(gl, type, src) {
    const sh = gl.createShader(type);
    gl.shaderSource(sh, src);
    gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
      console.warn('Map shader error:', gl.getShaderInfoLog(sh));
      gl.deleteShader(sh);
      return null;
    }
    return sh;
  }

  setupWebGL(gl) {
    const vs = this.compileShader(gl, gl.VERTEX_SHADER, VS_SRC);
    const fs = this.compileShader(gl, gl.FRAGMENT_SHADER, FS_SRC);
    if (!vs || !fs) {
      this.gl = null;
      return;
    }
    const prog = gl.createProgram();
    gl.attachShader(prog, vs);
    gl.attachShader(prog, fs);
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      console.warn('Map program link error:', gl.getProgramInfoLog(prog));
      this.gl = null;
      return;
    }
    this.program = prog;
    gl.useProgram(prog);

    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(prog, 'a_pos');
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);

    this.uLoc = {
      res: gl.getUniformLocation(prog, 'u_res'),
      center: gl.getUniformLocation(prog, 'u_center'),
      scale: gl.getUniformLocation(prog, 'u_scale'),
      px_step: gl.getUniformLocation(prog, 'u_px_step'),
      world_tiles: gl.getUniformLocation(prog, 'u_world_tiles'),
      time: gl.getUniformLocation(prog, 'u_time'),
      mood: gl.getUniformLocation(prog, 'u_mood'),
      fog_mode: gl.getUniformLocation(prog, 'u_fog_mode'),
      cursor_tile: gl.getUniformLocation(prog, 'u_cursor_tile'),
      pulse_tile: gl.getUniformLocation(prog, 'u_pulse_tile'),
      pulse_age: gl.getUniformLocation(prog, 'u_pulse_age'),
      active_super: gl.getUniformLocation(prog, 'u_active_super'),
      pal: gl.getUniformLocation(prog, 'u_pal'),
      reveal_count: gl.getUniformLocation(prog, 'u_reveal_count'),
      reveals: gl.getUniformLocation(prog, 'u_reveals'),
    };
    this.paletteVec = buildPaletteArray();
  }

  loadImage(src) {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.decoding = 'async';
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = src;
    });
  }

  sampleImageBytes(img) {
    const c = document.createElement('canvas');
    c.width = img.width;
    c.height = img.height;
    const ctx = c.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(img, 0, 0);
    return { width: img.width, height: img.height, data: ctx.getImageData(0, 0, img.width, img.height).data };
  }

  async loadWorldTextures() {
    const files = {
      outer_sdf: './img/map/outer_sdf.png',
      lakes_sdf: './img/map/lakes_sdf.png',
      water: './img/map/map_water.png',
      relief: './img/map/relief.png',
      relief_field: './img/map/relief_field.png',
      areas: './img/map/areas.png',
      paths: './img/map/paths.png',
    };
    try {
      const entries = await Promise.all(
        Object.entries(files).map(async ([k, src]) => [k, await this.loadImage(src)])
      );
      const imgs = Object.fromEntries(entries);
      this.areasBytes = this.sampleImageBytes(imgs.areas);
      this.reliefBytes = this.sampleImageBytes(imgs.relief);
      this.outerBytes = this.sampleImageBytes(imgs.outer_sdf);
      this.buildFallbackCanvas(imgs);

      if (this.gl && this.program) {
        const gl = this.gl;
        gl.useProgram(this.program);
        const order = ['outer_sdf', 'lakes_sdf', 'water', 'relief', 'relief_field', 'areas', 'paths'];
        order.forEach((key, unit) => {
          const tex = gl.createTexture();
          gl.activeTexture(gl.TEXTURE0 + unit);
          gl.bindTexture(gl.TEXTURE_2D, tex);
          gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
          const linear = key === 'outer_sdf' || key === 'lakes_sdf' || key === 'relief_field' || key === 'water' || key === 'paths';
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, linear ? gl.LINEAR : gl.NEAREST);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, linear ? gl.LINEAR : gl.NEAREST);
          gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, imgs[key]);
          gl.uniform1i(gl.getUniformLocation(this.program, `u_${key}`), unit);
          this.textures[key] = tex;
        });
      }
      this.texturesReady = true;
      this.drawFrame(true);
    } catch (err) {
      console.warn('World textures load failed:', err);
    }
  }

  lookupAreaRaw(tx, ty) {
    if (!this.areasBytes || tx < 0 || ty < 0 || tx >= WORLD_TILES || ty >= WORLD_TILES) return -1;
    const cx = Math.max(0, Math.min(this.areasBytes.width - 1, Math.floor(tx / MAP_CELL)));
    const cy = Math.max(0, Math.min(this.areasBytes.height - 1, Math.floor(ty / MAP_CELL)));
    const raw = this.areasBytes.data[(cy * this.areasBytes.width + cx) * 4];
    return raw - 1;
  }

  lookupAreaId(tx, ty) {
    const a = this.lookupAreaRaw(tx, ty);
    if (a >= 0) return a;
    const offsets = [[3, 0], [-3, 0], [0, 3], [0, -3], [6, 0], [-6, 0], [0, 6], [0, -6]];
    for (const [dx, dy] of offsets) {
      const n = this.lookupAreaRaw(tx + dx, ty + dy);
      if (n >= 0) return n;
    }
    return 0;
  }

  buildFallbackCanvas(imgs) {
    // 2D fallback canvas if WebGL2 context isn't available
    const c = document.createElement('canvas');
    c.width = WORLD_TILES;
    c.height = WORLD_TILES;
    const ctx = c.getContext('2d');
    const out = ctx.createImageData(WORLD_TILES, WORLD_TILES);
    const outer = this.outerBytes.data;
    const water = this.sampleImageBytes(imgs.water).data;
    const lakes = this.sampleImageBytes(imgs.lakes_sdf).data;
    const paths = this.sampleImageBytes(imgs.paths).data;
    const rel = this.reliefBytes.data;
    const areaPal = [
      [48, 108, 62],  // Die Lichtung (meadow)
      [50, 60, 88],   // Hexenwald (witch_forest)
      [142, 108, 62], // Sonnenquarz-Oede (quartz_desert)
    ];
    for (let y = 0; y < WORLD_TILES; y++) {
      for (let x = 0; x < WORLD_TILES; x++) {
        const p = (y * WORLD_TILES + x) * 4;
        const land = outer[p] >= 128;
        if (!land) {
          out.data[p] = 10; out.data[p + 1] = 7; out.data[p + 2] = 18; out.data[p + 3] = 255;
          continue;
        }
        const areaId = Math.max(0, Math.min(2, this.lookupAreaId(x, y)));
        const lvl = rel[p];
        let [r, g, b] = areaPal[areaId];
        r = Math.min(255, r + lvl * 18);
        g = Math.min(255, g + lvl * 18);
        b = Math.min(255, b + lvl * 18);
        if (lakes[p] < 128 || water[p] > 20 || water[p + 2] > 30) {
          r = 40; g = 106; b = 152;
        } else if (paths[p] > 25) {
          r = 192; g = 160; b = 114;
        }
        out.data[p] = r; out.data[p + 1] = g; out.data[p + 2] = b; out.data[p + 3] = 255;
      }
    }
    ctx.putImageData(out, 0, 0);
    this.fallbackCanvas = c;
  }

  sampleTileInfo(tx, ty) {
    const x = Math.floor(tx);
    const y = Math.floor(ty);
    if (x < 0 || y < 0 || x >= WORLD_TILES || y >= WORLD_TILES) {
      return { land: false, biomeName: 'Die Leere (Ozean)', superName: 'Äußere Leere', level: 0 };
    }
    let biomeName = 'Lichtung';
    let level = 0;
    let land = false;
    const idx = (y * WORLD_TILES + x) * 4;
    if (this.outerBytes) {
      land = this.outerBytes.data[idx] >= 128;
    } else if (this.reliefBytes) {
      land = this.reliefBytes.data[idx + 3] >= 200;
    }
    if (land && this.reliefBytes) {
      level = this.reliefBytes.data[idx];
    }
    let superName = land ? 'Die Lichtung' : 'Äußere Leere';
    if (land && this.areasBytes) {
      const sid = this.lookupAreaId(x, y);
      if (SUPERS[sid]) {
        superName = SUPERS[sid].name;
        const bKey = SUPERS[sid].biome || (sid === 0 ? 'meadow' : sid === 1 ? 'witch_forest' : 'quartz_desert');
        biomeName = BIOMES[bKey]?.name || superName;
      }
    }
    return { land, biomeName, superName, level };
  }

  worldToScreen(wx, wy) {
    const w = this.overlayCanvas.clientWidth || 1;
    const h = this.overlayCanvas.clientHeight || 1;
    return {
      x: (wx - this.center.x) * this.scale + w * 0.5,
      y: (wy - this.center.y) * this.scale + h * 0.5,
    };
  }

  screenToWorld(sx, sy) {
    const w = this.overlayCanvas.clientWidth || 1;
    const h = this.overlayCanvas.clientHeight || 1;
    return {
      x: (sx - w * 0.5) / this.scale + this.center.x,
      y: (sy - h * 0.5) / this.scale + this.center.y,
    };
  }

  clampCamera() {
    this.targetCenter.x = Math.max(-160, Math.min(WORLD_TILES + 160, this.targetCenter.x));
    this.targetCenter.y = Math.max(-160, Math.min(WORLD_TILES + 160, this.targetCenter.y));
    this.center.x = Math.max(-160, Math.min(WORLD_TILES + 160, this.center.x));
    this.center.y = Math.max(-160, Math.min(WORLD_TILES + 160, this.center.y));
  }

  zoomAt(factor, sx, sy) {
    const next = Math.max(this.minScale, Math.min(this.maxScale, this.targetScale * factor));
    const before = this.screenToWorld(sx, sy);
    this.targetScale = next;
    const w = this.overlayCanvas.clientWidth || 1;
    const h = this.overlayCanvas.clientHeight || 1;
    this.targetCenter.x = before.x - (sx - w * 0.5) / next;
    this.targetCenter.y = before.y - (sy - h * 0.5) / next;
    this.velocity.x = 0;
    this.velocity.y = 0;
    this.tour = null;
    this.clampCamera();
  }

  flyTo(wx, wy, zoom = null) {
    this.targetCenter = { x: wx, y: wy };
    if (zoom !== null) {
      this.targetScale = Math.max(this.minScale, Math.min(this.maxScale, zoom));
    }
    this.velocity = { x: 0, y: 0 };
    this.clampCamera();
  }

  resetView() {
    this.tour = null;
    this.activeSuper = -1;
    const w = this.overlayCanvas.clientWidth || 900;
    const h = this.overlayCanvas.clientHeight || 600;
    const fit = Math.max(0.42, Math.min(0.85, Math.min(w, h) / 1180));
    this.flyTo(540, 520, fit);
  }

  awakenWaystone(waystone) {
    this.awakenedWaystones.add(waystone.id);
    this.pulse = { x: waystone.tile[0], y: waystone.tile[1], age: 0.001 };
  }

  startWindTour() {
    const stops = [
      { id: 'start_home', zoom: 1.55, duration: 4.0 },
      { id: 'hallgrat_city', zoom: 1.85, duration: 4.5 },
      { id: 'wonder_sleeping_guardians', zoom: 1.65, duration: 4.2 },
      { id: 'wonder_bell_pond', zoom: 1.75, duration: 4.2 },
      { id: 'singing_basin', zoom: 1.55, duration: 4.4 },
      { id: 'raven_hollow', zoom: 1.65, duration: 4.4 },
    ];
    this.tour = { stops, idx: 0, elapsed: 0 };
    this.applyTourStop(0);
    return true;
  }

  stopTour() {
    this.tour = null;
  }

  applyTourStop(idx) {
    if (!this.tour) return;
    const stop = this.tour.stops[idx];
    if (!stop) {
      this.tour = null;
      return;
    }
    const feat = this.features.find((f) => f.id === stop.id);
    if (feat) {
      this.selectedFeature = feat;
      this.flyTo(feat.tile[0], feat.tile[1], stop.zoom);
      this.onSelect(feat);
    }
  }

  setMood(mood) {
    this.mood = mood;
    this.drawFrame(true);
  }

  setFogMode(on) {
    this.fogMode = !!on;
    this.drawFrame(true);
  }

  setPaused(paused) {
    this.paused = !!paused;
  }

  setReducedMotion(reduced) {
    this.reducedMotion = !!reduced;
  }

  setLayer(key, enabled) {
    if (key in this.layers) this.layers[key] = !!enabled;
  }

  setPinTool(tool, callback = null) {
    this.pinTool = tool || '';
    this.pickCallback = callback;
    this.stage.dataset.pinMode = this.pinTool ? 'active' : 'off';
  }

  addCustomPin(wx, wy, kind = 'waymark', label = '') {
    const style = PIN_STYLES[kind] || PIN_STYLES.waymark;
    const tile = [Math.round(wx), Math.round(wy)];
    const info = this.sampleTileInfo(tile[0], tile[1]);
    const pin = {
      id: `pin_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
      kind,
      name: label || `${style.label} · ${info.biomeName}`,
      tile,
      desc: `Eigene Markierung bei (${tile[0]}, ${tile[1]}) in ${info.superName}.`,
    };
    this.customPins = [pin, ...this.customPins].slice(0, 24);
    this.saveCustomPins();
    return pin;
  }

  removeCustomPin(id) {
    this.customPins = this.customPins.filter((p) => p.id !== id);
    this.saveCustomPins();
    if (this.selectedFeature?.id === id) {
      this.selectedFeature = null;
      this.onSelect(null);
    }
  }

  setActiveSuper(superId) {
    this.activeSuper = typeof superId === 'number' ? superId : -1;
    if (this.activeSuper >= 0 && SUPERS[this.activeSuper]) {
      const s = SUPERS[this.activeSuper];
      this.flyTo(s.center[0], s.center[1], 1.15);
    }
  }

  selectFeatureById(id) {
    const feat = this.features.find((f) => f.id === id);
    if (!feat) return null;
    this.selectedFeature = feat;
    if (feat.kind === 'waystone') this.awakenWaystone(feat);
    this.flyTo(feat.tile[0], feat.tile[1], Math.max(1.55, this.targetScale));
    this.onSelect(feat);
    return feat;
  }

  resize() {
    const rect = this.stage.getBoundingClientRect();
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const cssW = Math.max(300, Math.round(rect.width));
    const cssH = Math.max(260, Math.round(rect.height));

    this.glCanvas.width = Math.round(cssW * dpr);
    this.glCanvas.height = Math.round(cssH * dpr);
    this.overlayCanvas.width = Math.round(cssW * dpr);
    this.overlayCanvas.height = Math.round(cssH * dpr);
    this.dpr = dpr;

    if (this.gl) {
      this.gl.viewport(0, 0, this.glCanvas.width, this.glCanvas.height);
    }
    this.drawFrame(true);
  }

  allVisibleFeatures() {
    const zoom = this.scale;
    const items = [];
    for (const f of this.features) {
      const focused = this.selectedFeature?.id === f.id || this.hoveredFeature?.id === f.id;
      if (!focused) {
        if (f.kind === 'waystone' && !this.layers.waystones) continue;
        if (f.kind === 'wonder' && !this.layers.wonders) continue;
        if (f.kind === 'arena' && !this.layers.arenas) continue;
        if (f.kind === 'hallgrat' && !this.layers.hallgrat) continue;
        if (f.kind === 'vista' && !this.layers.vistas) continue;
        if ((f.kind === 'order' || f.kind === 'watermill' || f.kind === 'pier') && !this.layers.orders) continue;
        if (zoom < (f.minZoom || 0)) continue;
      }
      items.push(f);
    }
    if (this.layers.custom) {
      for (const p of this.customPins) {
        items.push({ ...p, kind: 'custom', category: PIN_STYLES[p.kind]?.label || 'Eigener Marker', sub: `PIN · ${p.tile[0]}, ${p.tile[1]}`, isCustom: true, customKind: p.kind });
      }
    }
    if (this.layers.admin) {
      for (const a of this.adminPins) {
        items.push({
          id: a.id,
          kind: 'admin',
          category: 'Offizielles Server-Event',
          name: a.title || 'Welt-Anomalie',
          sub: `SERVER-PIN · ${a.tile?.[0] ?? 550}, ${a.tile?.[1] ?? 550}`,
          tile: a.tile || [550, 550],
          desc: a.note || '',
          isAdmin: true,
        });
      }
    }
    return items;
  }

  hitTest(sx, sy) {
    const list = this.allVisibleFeatures();
    let best = null;
    let bestD = 18;
    for (let i = list.length - 1; i >= 0; i--) {
      const f = list[i];
      const sp = this.worldToScreen(f.tile[0], f.tile[1]);
      const d = Math.hypot(sp.x - sx, sp.y - sy);
      if (d < bestD) {
        bestD = d;
        best = f;
      }
    }
    return best;
  }

  bindEvents() {
    window.addEventListener('resize', () => this.resize(), { passive: true });
    if ('ResizeObserver' in window) {
      new ResizeObserver(() => this.resize()).observe(this.stage);
    }

    this.stage.addEventListener('pointerdown', (e) => {
      if (e.button !== 0 && e.button !== 2) return;
      if (e.target.closest('[data-map-hud]')) return;
      this.stage.setPointerCapture(e.pointerId);
      const rect = this.overlayCanvas.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      this.pointers.set(e.pointerId, { x, y, startX: x, startY: y });
      this.dragMoved = false;
      this.velocity = { x: 0, y: 0 };
      this.dragSample = { x, y, t: performance.now() };
      this.tour = null;
    });

    this.stage.addEventListener('pointermove', (e) => {
      const rect = this.overlayCanvas.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      this.cursorScreen = { x, y, inside: true };
      const wt = this.screenToWorld(x, y);
      this.cursorTile = wt;
      const info = this.sampleTileInfo(wt.x, wt.y);
      const hoverFeat = this.hitTest(x, y);
      this.hoveredFeature = hoverFeat;
      this.stage.style.cursor = this.pinTool
        ? 'crosshair'
        : (this.pointers.size > 0 ? 'grabbing' : (hoverFeat ? 'pointer' : 'grab'));
      this.onHover({ tile: [Math.round(wt.x), Math.round(wt.y)], ...info, feature: hoverFeat });

      if (!this.pointers.has(e.pointerId)) return;
      const prev = this.pointers.get(e.pointerId);
      const dx = x - prev.x;
      const dy = y - prev.y;
      prev.x = x;
      prev.y = y;

      if (Math.hypot(x - prev.startX, y - prev.startY) > 4) {
        this.dragMoved = true;
      }

      if (this.pointers.size === 1 && !e.shiftKey) {
        this.center.x -= dx / this.scale;
        this.center.y -= dy / this.scale;
        this.targetCenter.x = this.center.x;
        this.targetCenter.y = this.center.y;
        this.clampCamera();
        const now = performance.now();
        const dt = Math.max(8, now - this.dragSample.t) / 1000;
        this.velocity.x = -(x - this.dragSample.x) / this.scale / dt;
        this.velocity.y = -(y - this.dragSample.y) / this.scale / dt;
        this.dragSample = { x, y, t: now };
      } else if (this.pointers.size === 2) {
        const pts = [...this.pointers.values()];
        const curDist = Math.hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y);
        if (this.lastPinchDist && curDist > 4) {
          const mx = (pts[0].x + pts[1].x) * 0.5;
          const my = (pts[0].y + pts[1].y) * 0.5;
          this.zoomAt(curDist / this.lastPinchDist, mx, my);
        }
        this.lastPinchDist = curDist;
      }
    });

    const endPointer = (e) => {
      const rect = this.overlayCanvas.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      const wasDown = this.pointers.has(e.pointerId);
      this.pointers.delete(e.pointerId);
      if (this.pointers.size < 2) this.lastPinchDist = 0;

      if (!wasDown) return;
      if (e.button === 2) {
        // Right-click drops a custom pin cleanly
        const wt = this.screenToWorld(x, y);
        const pin = this.addCustomPin(wt.x, wt.y, 'waymark');
        const feat = { ...pin, kind: 'custom', category: 'Wegzeichen', sub: `PIN · ${pin.tile[0]}, ${pin.tile[1]}`, isCustom: true, customKind: pin.kind };
        this.selectedFeature = feat;
        this.onSelect(feat);
        return;
      }

      if (!this.dragMoved) {
        const wt = this.screenToWorld(x, y);
        if (this.pinTool === 'pick' && this.pickCallback) {
          const coords = [Math.round(wt.x), Math.round(wt.y)];
          const cb = this.pickCallback;
          this.setPinTool('');
          cb(coords);
          return;
        }
        if (this.pinTool) {
          const pin = this.addCustomPin(wt.x, wt.y, this.pinTool);
          const feat = { ...pin, kind: 'custom', category: PIN_STYLES[this.pinTool]?.label || 'Marker', sub: `PIN · ${pin.tile[0]}, ${pin.tile[1]}`, isCustom: true, customKind: this.pinTool };
          this.selectedFeature = feat;
          this.setPinTool('');
          this.onSelect(feat);
          return;
        }

        const hit = this.hitTest(x, y);
        if (hit) {
          this.selectedFeature = hit;
          if (hit.kind === 'waystone') this.awakenWaystone(hit);
          this.flyTo(hit.tile[0], hit.tile[1], Math.max(this.targetScale, 1.35));
          this.onSelect(hit);
        } else {
          this.selectedFeature = null;
          this.onSelect(null);
        }
      }
    };

    this.stage.addEventListener('pointerup', endPointer);
    this.stage.addEventListener('pointercancel', endPointer);
    this.stage.addEventListener('pointerleave', () => {
      this.cursorScreen.inside = false;
      this.cursorTile = { x: -1, y: -1 };
    });
    this.stage.addEventListener('contextmenu', (e) => {
      if (!e.target.closest('[data-map-hud]')) e.preventDefault();
    });

    this.stage.addEventListener('dblclick', (e) => {
      if (e.target.closest('[data-map-hud]')) return;
      const rect = this.overlayCanvas.getBoundingClientRect();
      this.zoomAt(1.65, e.clientX - rect.left, e.clientY - rect.top);
    });

    this.stage.addEventListener(
      'wheel',
      (e) => {
        if (e.target.closest('[data-map-hud]')) return;
        e.preventDefault();
        const rect = this.overlayCanvas.getBoundingClientRect();
        const step = e.deltaY < 0 ? 1.18 : 1 / 1.18;
        this.zoomAt(step, e.clientX - rect.left, e.clientY - rect.top);
      },
      { passive: false }
    );

    this.stage.addEventListener('keydown', (e) => {
      if (e.target.matches('input, textarea, select')) return;
      if (e.key === '+' || e.key === '=') {
        e.preventDefault();
        const w = this.overlayCanvas.clientWidth * 0.5;
        const h = this.overlayCanvas.clientHeight * 0.5;
        this.zoomAt(1.3, w, h);
      } else if (e.key === '-') {
        e.preventDefault();
        const w = this.overlayCanvas.clientWidth * 0.5;
        const h = this.overlayCanvas.clientHeight * 0.5;
        this.zoomAt(1 / 1.3, w, h);
      } else if (e.key === 'r' || e.key === 'R' || e.key === 'Home') {
        e.preventDefault();
        this.resetView();
      } else if (e.key === 'Escape') {
        this.tour = null;
        this.setPinTool('');
        this.selectedFeature = null;
        this.onSelect(null);
      } else {
        this.keysHeld.add(e.key.toLowerCase());
      }
    });

    window.addEventListener('keyup', (e) => {
      this.keysHeld.delete(e.key.toLowerCase());
    });
  }

  start() {
    if (this.rafId) return;
    this.lastFrame = performance.now();
    const loop = (now) => {
      const dt = Math.min(0.05, Math.max(0.001, (now - this.lastFrame) / 1000));
      this.lastFrame = now;
      this.step(dt);
      this.drawFrame(false);
      this.rafId = requestAnimationFrame(loop);
    };
    this.rafId = requestAnimationFrame(loop);
  }

  stop() {
    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
      this.rafId = 0;
    }
  }

  step(dt) {
    if (!this.paused && !this.reducedMotion) {
      this.time = (this.time + dt) % 10000;
    }
    if (this.pulse.age > 0) {
      this.pulse.age += dt * 1.15;
      if (this.pulse.age >= 1.0) this.pulse = { x: -1, y: -1, age: 0 };
    }

    // Guided Tour progression
    if (this.tour) {
      this.tour.elapsed += dt;
      const cur = this.tour.stops[this.tour.idx];
      if (!cur || this.tour.elapsed >= cur.duration) {
        this.tour.idx += 1;
        this.tour.elapsed = 0;
        if (this.tour.idx >= this.tour.stops.length) {
          this.tour = null;
          this.resetView();
        } else {
          this.applyTourStop(this.tour.idx);
        }
      }
    }

    // Keyboard panning when map stage or body active
    let kx = 0;
    let ky = 0;
    if (this.keysHeld.has('arrowleft') || this.keysHeld.has('a')) kx -= 1;
    if (this.keysHeld.has('arrowright') || this.keysHeld.has('d')) kx += 1;
    if (this.keysHeld.has('arrowup') || this.keysHeld.has('w')) ky -= 1;
    if (this.keysHeld.has('arrowdown') || this.keysHeld.has('s')) ky += 1;
    if (kx || ky) {
      const speed = (340 / this.scale) * dt;
      this.targetCenter.x += kx * speed;
      this.targetCenter.y += ky * speed;
      this.tour = null;
      this.clampCamera();
    }

    // Momentum inertia when not dragging
    if (this.pointers.size === 0 && (Math.abs(this.velocity.x) > 0.5 || Math.abs(this.velocity.y) > 0.5)) {
      this.targetCenter.x += this.velocity.x * dt;
      this.targetCenter.y += this.velocity.y * dt;
      const damp = Math.exp(-5.4 * dt);
      this.velocity.x *= damp;
      this.velocity.y *= damp;
      this.clampCamera();
    }

    const camEase = this.reducedMotion ? 1 : 1 - Math.exp(-10.5 * dt);
    this.center.x += (this.targetCenter.x - this.center.x) * camEase;
    this.center.y += (this.targetCenter.y - this.center.y) * camEase;
    this.scale *= Math.pow(this.targetScale / this.scale, camEase);

    this.onCamera({
      center: { ...this.center },
      scale: this.scale,
      touring: !!this.tour,
    });
  }

  drawFrame(force = false) {
    if (!this.texturesReady && !force) return;

    if (this.gl && this.program && this.texturesReady) {
      const gl = this.gl;
      gl.useProgram(this.program);
      const cssW = this.overlayCanvas.clientWidth || 1;
      const cssH = this.overlayCanvas.clientHeight || 1;
      // Pass CSS-scaled center & scale matching gl_FragCoord (which is in physical pixels = css * dpr)
      gl.uniform2f(this.uLoc.res, this.glCanvas.width, this.glCanvas.height);
      gl.uniform2f(this.uLoc.center, this.center.x, this.center.y);
      gl.uniform1f(this.uLoc.scale, this.scale * this.dpr);
      gl.uniform1f(this.uLoc.px_step, Math.max(1.0, Math.round((this.dpr || 1) * 2.0)));
      gl.uniform1f(this.uLoc.world_tiles, WORLD_TILES);
      gl.uniform1f(this.uLoc.time, this.time);
      gl.uniform1f(this.uLoc.mood, this.mood === 'day' ? 1.0 : (this.mood === 'blood' ? 2.0 : 0.0));
      gl.uniform1f(this.uLoc.fog_mode, this.fogMode ? 1.0 : 0.0);
      gl.uniform2f(
        this.uLoc.cursor_tile,
        this.cursorScreen.inside ? this.cursorTile.x : -1.0,
        this.cursorScreen.inside ? this.cursorTile.y : -1.0
      );
      gl.uniform2f(this.uLoc.pulse_tile, this.pulse.x, this.pulse.y);
      gl.uniform1f(this.uLoc.pulse_age, this.pulse.age);
      gl.uniform1f(this.uLoc.active_super, this.activeSuper);
      gl.uniform3fv(this.uLoc.pal, this.paletteVec);

      // Build reveal tiles array (start + awakened waystones)
      const rev = new Float32Array(32);
      rev[0] = START_TILE[0];
      rev[1] = START_TILE[1];
      let rCount = 1;
      for (const w of WAYSTONES) {
        if (this.awakenedWaystones.has(w.id) && rCount < 16) {
          rev[rCount * 2] = w.tile[0];
          rev[rCount * 2 + 1] = w.tile[1];
          rCount++;
        }
      }
      gl.uniform1f(this.uLoc.reveal_count, rCount);
      gl.uniform2fv(this.uLoc.reveals, rev);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    } else if (this.fallbackCanvas) {
      // Crisp 2D fallback
      const ctx = this.octx;
      const dpr = this.dpr || 1;
      ctx.save();
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      const w = this.overlayCanvas.clientWidth || 1;
      const h = this.overlayCanvas.clientHeight || 1;
      ctx.fillStyle = '#0a0712';
      ctx.fillRect(0, 0, w, h);
      ctx.imageSmoothingEnabled = false;
      const tl = this.worldToScreen(0, 0);
      ctx.drawImage(this.fallbackCanvas, tl.x, tl.y, WORLD_TILES * this.scale, WORLD_TILES * this.scale);
      ctx.restore();
    }

    this.drawOverlay();
  }

  drawOverlay() {
    const ctx = this.octx;
    const dpr = this.dpr || 1;
    const w = this.overlayCanvas.clientWidth || 1;
    const h = this.overlayCanvas.clientHeight || 1;

    ctx.save();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    if (this.gl && this.program && this.texturesReady) {
      ctx.clearRect(0, 0, w, h);
    }

    // 1. Subtle Leyline Web only when Waystones layer is explicitly active or a Waystone is focused
    const focusWaystone =
      this.hoveredFeature?.kind === 'waystone'
        ? this.hoveredFeature
        : (this.selectedFeature?.kind === 'waystone' ? this.selectedFeature : null);
    if (this.layers.waystones || focusWaystone) {
      ctx.save();
      for (let i = 0; i < WAYSTONES.length; i++) {
        const a = WAYSTONES[i];
        const ap = this.worldToScreen(a.tile[0], a.tile[1]);
        for (let j = i + 1; j < WAYSTONES.length; j++) {
          const b = WAYSTONES[j];
          const dist = Math.hypot(a.tile[0] - b.tile[0], a.tile[1] - b.tile[1]);
          if (dist > 340) continue;
          const hot = focusWaystone && (focusWaystone.id === a.id || focusWaystone.id === b.id);
          if (!hot && (!this.layers.waystones || !this.awakenedWaystones.has(a.id))) continue;
          const bp = this.worldToScreen(b.tile[0], b.tile[1]);
          ctx.beginPath();
          ctx.moveTo(ap.x, ap.y);
          ctx.lineTo(bp.x, bp.y);
          ctx.strokeStyle = hot ? 'rgba(79, 227, 193, 0.56)' : 'rgba(139, 92, 255, 0.18)';
          ctx.lineWidth = hot ? 1.8 : 1;
          ctx.setLineDash([4, 6]);
          ctx.lineDashOffset = -this.time * 12;
          ctx.stroke();
        }
      }
      ctx.restore();
    }

    // 2. Hallgrat Citadel District Bounding Silhouette when zoomed in
    if (this.layers.hallgrat && this.scale >= 1.35) {
      const [bx0, by0, bx1, by1] = HALLGRAT.bounds;
      const p0 = this.worldToScreen(bx0, by0);
      const p1 = this.worldToScreen(bx1, by1);
      ctx.save();
      ctx.strokeStyle = 'rgba(217, 200, 255, 0.30)';
      ctx.lineWidth = 1;
      ctx.setLineDash([3, 4]);
      ctx.strokeRect(p0.x, p0.y, p1.x - p0.x, p1.y - p0.y);
      ctx.restore();
    }

    // 3. Superregion Watermark Titles on Overview Zoom
    if (this.scale <= 1.55) {
      ctx.save();
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      const titlePos = {
        0: [492, 540],
        1: [822, 856], // sit clearly above Schieferkessel Arena
        2: [805, 192],
      };
      const tierTag = { 0: 'WIESENLANDE', 1: 'SCHATTENWALD', 2: 'SONNENÖDE' };
      for (const s of SUPERS) {
        const pt = titlePos[s.id] || s.center;
        const sp = this.worldToScreen(pt[0], pt[1]);
        if (sp.x < -100 || sp.y < -40 || sp.x > w + 100 || sp.y > h + 40) continue;
        const alpha = Math.max(0.28, Math.min(0.92, (1.58 - this.scale) * 1.45));
        const text = s.name.toUpperCase();
        ctx.font = '700 13px "Alegreya Sans", sans-serif';
        ctx.letterSpacing = '0.20em';
        ctx.lineWidth = 4;
        ctx.strokeStyle = `rgba(9, 6, 16, ${alpha * 0.92})`;
        ctx.strokeText(text, sp.x, sp.y - 6);
        ctx.fillStyle = this.activeSuper === s.id ? `rgba(242, 195, 107, ${alpha})` : `rgba(240, 232, 255, ${alpha * 0.92})`;
        ctx.fillText(text, sp.x, sp.y - 6);

        ctx.font = '700 8.5px "Alegreya Sans", sans-serif';
        ctx.letterSpacing = '0.26em';
        const sub = tierTag[s.id] || '';
        if (sub) {
          ctx.lineWidth = 3;
          ctx.strokeStyle = `rgba(9, 6, 16, ${alpha * 0.85})`;
          ctx.strokeText(sub, sp.x, sp.y + 9);
          ctx.fillStyle = this.activeSuper === s.id ? `rgba(242, 195, 107, ${alpha * 0.8})` : `rgba(182, 170, 224, ${alpha * 0.72})`;
          ctx.fillText(sub, sp.x, sp.y + 9);
        }
      }
      ctx.restore();
    }

    // 4. All Visible Landmarks & Pins
    const list = this.allVisibleFeatures();
    for (const f of list) {
      const sp = this.worldToScreen(f.tile[0], f.tile[1]);
      if (sp.x < -30 || sp.y < -30 || sp.x > w + 30 || sp.y > h + 30) continue;
      const isSelected = this.selectedFeature?.id === f.id;
      const isHovered = this.hoveredFeature?.id === f.id;
      this.drawMarker(ctx, f, sp.x, sp.y, isSelected, isHovered);
    }

    // 5. Delicate Atlas Compass Rose (Desktop margin above zoom bar)
    if (w >= 720 && h >= 420) {
      this.drawCompassRose(ctx, w - 34, h - 78);
    }

    // 6. Pin-Placement Crosshair Preview
    if (this.pinTool && this.cursorScreen.inside) {
      const { x, y } = this.cursorScreen;
      const pStyle = PIN_STYLES[this.pinTool] || { color: '#4fe3c1' };
      ctx.save();
      ctx.strokeStyle = pStyle.color;
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(x, y, 10 + Math.sin(this.time * 5) * 1.5, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    }

    ctx.restore();
  }

  drawCompassRose(ctx, cx, cy) {
    ctx.save();
    ctx.translate(Math.round(cx) + 0.5, Math.round(cy) + 0.5);
    ctx.strokeStyle = 'rgba(139, 92, 255, 0.34)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.arc(0, 0, 14, 0, Math.PI * 2);
    ctx.stroke();

    // Cardinal pointers
    ctx.fillStyle = 'rgba(242, 195, 107, 0.78)';
    ctx.beginPath();
    ctx.moveTo(0, -11);
    ctx.lineTo(2.5, -2);
    ctx.lineTo(-2.5, -2);
    ctx.closePath();
    ctx.fill();

    ctx.fillStyle = 'rgba(201, 190, 236, 0.48)';
    ctx.beginPath();
    ctx.moveTo(0, 11); ctx.lineTo(2, 2); ctx.lineTo(-2, 2); ctx.closePath();
    ctx.moveTo(-11, 0); ctx.lineTo(-2, -2); ctx.lineTo(-2, 2); ctx.closePath();
    ctx.moveTo(11, 0); ctx.lineTo(2, -2); ctx.lineTo(2, 2); ctx.closePath();
    ctx.fill();

    ctx.font = '700 8px "Alegreya Sans", sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'bottom';
    ctx.fillStyle = 'rgba(242, 195, 107, 0.88)';
    ctx.fillText('N', 0, -16);
    ctx.restore();
  }

  drawMarker(ctx, f, x, y, selected, hovered) {
    const pulse = 0.78 + 0.22 * Math.sin(this.time * 2.8 + f.tile[0] * 0.03);
    const active = selected || hovered;

    if (f.kind === 'start') {
      const r = active ? 13 : 10;
      const g = ctx.createRadialGradient(x, y, 1, x, y, r + 9);
      g.addColorStop(0, `rgba(242, 195, 107, ${0.42 * pulse})`);
      g.addColorStop(1, 'rgba(242, 195, 107, 0)');
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(x, y, r + 9, 0, Math.PI * 2);
      ctx.fill();

      this.drawHearthBeacon(ctx, x, y, active);
      const label = this.playerCloudDay !== null ? `DEIN HOF · TAG ${this.playerCloudDay}` : 'GLIMMRAST';
      // Put Glimmrast label slightly above beacon so it stays clear of Blumen-Amphitheater below
      this.drawCartoPill(ctx, label, x, y - 19, '#f7d98b', 'rgba(242, 195, 107, 0.52)', active);
      return;
    }

    if (f.kind === 'hallgrat') {
      this.drawHallgratCrest(ctx, x, y, active);
      this.drawCartoPill(ctx, 'HALLGRAT', x, y + 18, '#e6dcff', 'rgba(182, 164, 240, 0.5)', active || this.scale > 0.52);
      return;
    }

    if (f.kind === 'wonder') {
      const g = ctx.createRadialGradient(x, y, 1, x, y, active ? 18 : 13);
      g.addColorStop(0, `rgba(255, 216, 107, ${0.32 * pulse})`);
      g.addColorStop(1, 'rgba(255, 216, 107, 0)');
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(x, y, active ? 18 : 13, 0, Math.PI * 2);
      ctx.fill();

      this.drawStar(ctx, x, y, active ? 8 : 6, '#ffd86b', '#1b0f0a');
      ctx.fillStyle = '#7bf5e2';
      ctx.fillRect(Math.round(x - 1), Math.round(y - 1), 2, 2);

      if (active || this.scale > 0.72) {
        const shortName = f.name === 'KREIS DER SCHLAFENDEN WÄCHTER' && !active && this.scale < 1.1
          ? 'SCHLAFENDE WÄCHTER'
          : f.name;
        this.drawCartoPill(ctx, shortName, x, y + 17, '#ffe08a', 'rgba(242, 195, 107, 0.42)', active);
      }
      return;
    }

    if (f.kind === 'arena') {
      const g = ctx.createRadialGradient(x, y, 1, x, y, active ? 19 : 14);
      g.addColorStop(0, `rgba(255, 107, 123, ${0.34 * pulse})`);
      g.addColorStop(1, 'rgba(255, 107, 123, 0)');
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(x, y, active ? 19 : 14, 0, Math.PI * 2);
      ctx.fill();

      this.drawArenaSigil(ctx, x, y, active);
      if (active || this.scale > 0.58) {
        const lbl = active ? f.name : `${f.boss?.toUpperCase() || f.name}`;
        this.drawCartoPill(ctx, lbl, x, y + 18, '#ff9ea9', 'rgba(255, 107, 123, 0.48)', active);
      }
      return;
    }

    if (f.kind === 'waystone') {
      const awake = this.awakenedWaystones.has(f.id);
      const col = awake ? '#4fe3c1' : '#8a7ea6';
      if (awake || active) {
        ctx.fillStyle = awake ? `rgba(79, 227, 193, ${0.20 * pulse})` : 'rgba(139, 92, 255, 0.22)';
        ctx.beginPath();
        ctx.arc(x, y, active ? 13 : 9, 0, Math.PI * 2);
        ctx.fill();
      }
      this.drawDiamond(ctx, x, y, active ? 6.5 : 4.5, col, '#120a22');
      if (active || this.scale > 1.12) {
        this.drawCartoPill(ctx, f.name, x, y + 15, awake ? '#9af2dc' : '#cfc5e8', 'rgba(79, 227, 193, 0.36)', active);
      }
      return;
    }

    if (f.kind === 'custom' || f.kind === 'admin') {
      const style = f.isAdmin ? PIN_STYLES.event : (PIN_STYLES[f.customKind] || PIN_STYLES.waymark);
      this.drawDiamond(ctx, x, y, active ? 7 : 5.5, style.color, '#0d0818');
      this.drawCartoPill(ctx, f.name, x, y + 16, style.color, 'rgba(79, 227, 193, 0.4)', active);
      return;
    }

    // Optional Vistas / Order / Mills / Piers (only shown if explicitly toggled on in Ebenen)
    const minorColor = f.kind === 'vista' ? '#9ac6ff' : f.kind === 'order' ? '#e57c6a' : '#67d4c0';
    this.drawDiamond(ctx, x, y, active ? 5.5 : 3.8, active ? '#ffffff' : minorColor, '#0f091a');
    if (active || this.scale > 1.85) {
      this.drawCartoPill(ctx, f.name, x, y + 14, minorColor, 'rgba(139, 92, 255, 0.3)', active);
    }
  }

  drawHearthBeacon(ctx, x, y, active) {
    const px = Math.round(x);
    const py = Math.round(y);
    ctx.save();
    ctx.strokeStyle = '#120a1c';
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(px, py, active ? 7.5 : 6, 0, Math.PI * 2);
    ctx.stroke();

    ctx.fillStyle = '#331d10';
    ctx.beginPath();
    ctx.arc(px, py, active ? 7 : 5.5, 0, Math.PI * 2);
    ctx.fill();

    // Inner amber flame
    ctx.fillStyle = '#ff9a42';
    ctx.beginPath();
    ctx.moveTo(px, py - (active ? 5 : 4));
    ctx.lineTo(px + (active ? 4 : 3), py + 2);
    ctx.lineTo(px - (active ? 4 : 3), py + 2);
    ctx.closePath();
    ctx.fill();

    ctx.fillStyle = '#fff0b0';
    ctx.fillRect(px - 1, py - 1, 2, 3);
    ctx.restore();
  }

  drawHallgratCrest(ctx, x, y, active) {
    const px = Math.round(x);
    const py = Math.round(y);
    const s = active ? 1.25 : 1;
    ctx.save();
    ctx.translate(px, py);
    ctx.scale(s, s);
    // Dark outline base
    ctx.fillStyle = '#120a22';
    ctx.fillRect(-7, -6, 14, 12);
    // Triple citadel towers in cool moonstone lavender
    ctx.fillStyle = '#c4b3f5';
    ctx.fillRect(-5, -3, 3, 7);
    ctx.fillRect(-1.5, -5, 3, 9);
    ctx.fillRect(2, -3, 3, 7);
    ctx.fillRect(-5, 2, 10, 3);
    // Glowing turquoise spire light
    ctx.fillStyle = '#7bf5e2';
    ctx.fillRect(-1, -1, 2, 3);
    ctx.restore();
  }

  drawArenaSigil(ctx, x, y, active) {
    const r = active ? 8 : 6.5;
    ctx.save();
    ctx.beginPath();
    for (let i = 0; i < 6; i++) {
      const a = (i * Math.PI) / 3 - Math.PI / 2;
      const px = x + Math.cos(a) * r;
      const py = y + Math.sin(a) * r;
      if (i === 0) ctx.moveTo(px, py);
      else ctx.lineTo(px, py);
    }
    ctx.closePath();
    ctx.fillStyle = '#240b16';
    ctx.fill();
    ctx.lineWidth = 2;
    ctx.strokeStyle = '#ff6b7b';
    ctx.stroke();

    ctx.fillStyle = '#ffd0d6';
    ctx.beginPath();
    ctx.arc(x, y, active ? 2.6 : 2, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  drawCartoPill(ctx, text, x, y, color, borderColor, emphasize = false) {
    if (!text) return;
    ctx.save();
    ctx.font = emphasize
      ? '700 10.5px "Alegreya Sans", sans-serif'
      : '700 9.5px "Alegreya Sans", sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const metrics = ctx.measureText(text);
    const padX = emphasize ? 7 : 5.5;
    const w = Math.ceil(metrics.width + padX * 2);
    const h = emphasize ? 16 : 14;
    const rx = Math.round(x - w * 0.5);
    const ry = Math.round(y - h * 0.5);

    ctx.fillStyle = emphasize ? 'rgba(14, 9, 25, 0.94)' : 'rgba(11, 7, 20, 0.80)';
    ctx.fillRect(rx, ry, w, h);
    ctx.strokeStyle = borderColor || 'rgba(139, 92, 255, 0.35)';
    ctx.lineWidth = 1;
    ctx.strokeRect(rx + 0.5, ry + 0.5, w - 1, h - 1);

    ctx.fillStyle = emphasize ? '#ffffff' : color;
    ctx.fillText(text, Math.round(x), Math.round(y) + 0.5);
    ctx.restore();
  }

  drawDiamond(ctx, x, y, r, fill, stroke) {
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(x, y - r);
    ctx.lineTo(x + r, y);
    ctx.lineTo(x, y + r);
    ctx.lineTo(x - r, y);
    ctx.closePath();
    ctx.fillStyle = fill;
    ctx.fill();
    ctx.lineWidth = 1.6;
    ctx.strokeStyle = stroke;
    ctx.stroke();
    ctx.restore();
  }

  drawSquareShield(ctx, x, y, r, fill, stroke) {
    ctx.save();
    ctx.fillStyle = stroke;
    ctx.fillRect(Math.round(x - r - 1), Math.round(y - r - 1), (r + 1) * 2, (r + 1) * 2);
    ctx.fillStyle = fill;
    ctx.fillRect(Math.round(x - r + 1), Math.round(y - r + 1), (r - 1) * 2, (r - 1) * 2);
    ctx.restore();
  }

  drawTriangle(ctx, x, y, r, fill, stroke) {
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(x, y - r);
    ctx.lineTo(x + r, y + r * 0.8);
    ctx.lineTo(x - r, y + r * 0.8);
    ctx.closePath();
    ctx.fillStyle = fill;
    ctx.fill();
    ctx.lineWidth = 1.6;
    ctx.strokeStyle = stroke;
    ctx.stroke();
    ctx.restore();
  }

  drawStar(ctx, x, y, r, fill, stroke) {
    ctx.save();
    ctx.beginPath();
    for (let i = 0; i < 8; i++) {
      const ang = (i * Math.PI) / 4 - Math.PI / 2;
      const rad = i % 2 === 0 ? r : r * 0.42;
      const px = x + Math.cos(ang) * rad;
      const py = y + Math.sin(ang) * rad;
      if (i === 0) ctx.moveTo(px, py);
      else ctx.lineTo(px, py);
    }
    ctx.closePath();
    ctx.fillStyle = fill;
    ctx.fill();
    ctx.lineWidth = 1.4;
    ctx.strokeStyle = stroke;
    ctx.stroke();
    ctx.restore();
  }

  drawTagLabel(ctx, text, x, y, color, show) {
    if (!show || !text) return;
    ctx.save();
    ctx.font = '700 10px "Alegreya Sans", sans-serif';
    ctx.textAlign = 'center';
    ctx.lineWidth = 3;
    ctx.strokeStyle = 'rgba(10, 7, 18, 0.94)';
    ctx.strokeText(text, x, y);
    ctx.fillStyle = color;
    ctx.fillText(text, x, y);
    ctx.restore();
  }
}
