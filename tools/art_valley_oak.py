#!/usr/bin/env python3
"""Procedural 2.0 botanical pixel-art generator for Glimmtal-Stieleiche (Quercus glimmensis):
  assets/items/{oak_wood,oak_bark,oak_amber,valley_acorn,oak_polypore}.png
  assets/props/valley_oak/{s0..s5,s4_b,s4_c,coppice,s6_log}.png + *_glow.png
  data/valley_oak_rig.json
  docs/img/valley_oak_sheet.png
Zero #000000 pixels anywhere; stdlib + oak_botany.py only.
"""
import json
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import oak_botany as ob  # noqa: E402

OUT_DIR = ob.ROOT / "props" / "valley_oak"
RIG_JSON = ob.ROOT.parent / "data" / "valley_oak_rig.json"
QA_SHEET = ob.ROOT.parent / "docs" / "img" / "valley_oak_sheet.png"


def pack_strip(frames: list, fw: int, fh: int):
    strip = ob.blank(fw * len(frames), fh)
    for idx, fr in enumerate(frames):
        for y in range(fh):
            strip[y][idx * fw:(idx + 1) * fw] = fr[y][:]
    return strip


def make_rig_entry(fw, fh, fx, fy, cut_y, h_px, clr_px, th_px, ch_px, s_name, g_name, n_cols, g_cols, layers, g_layers, clusters, perches=None, hollow=None, rest=None, traits=None):
    d = {
        "frame_w": fw, "frame_h": fh, "feet_x": fx, "feet_y": fy, "cut_y": cut_y,
        "height_px": h_px, "clear_px": clr_px, "trunk_half_px": th_px, "crown_half_px": ch_px,
        "sheet": f"res://assets/props/valley_oak/{s_name}.png",
        "glow_sheet": f"res://assets/props/valley_oak/{g_name}.png" if g_name else "",
        "num_cols": n_cols, "glow_cols": g_cols,
        "layers": layers, "glow_layers": g_layers, "clusters": clusters,
        "perches": perches or [], "hollow": hollow or [], "rest_seat": rest or [],
    }
    if traits is not None:
        d["traits"] = traits
    return d


def build_s0():
    fw, fh, fx, fy = 24, 24, 12, 20
    skirt, c0 = ob.blank(fw, fh), ob.blank(fw, fh)
    for dy in range(-2, 3):
        for dx in range(-6, 7):
            d = math.hypot(dx / 6.0, dy / 2.5)
            if d < 1.0:
                ob.put_contact_shadow(skirt, fx + dx + 1, fy + dy, int(95 * (1.0 - d)))
    for dx in (-3, -2, -1, 0, 1, 2, 3):
        ob.put(skirt, fx + dx, fy, ob.MOSS[2 if dx <= 0 else 1])
    for dx in (-1, 0, 1):
        ob.put(skirt, fx + dx, fy - 1, ob.AMBER[2 if dx <= 0 else 1])
        ob.put(skirt, fx + dx - 1, fy - 2, ob.BARK[2])
    for y in range(13, 19):
        ob.put(c0, fx, y, ob.CANOPY[4 if y > 15 else 5])
    ob.draw_oak_leaf(c0, 12, 14, -0.85, -0.52, 4.6, ob.CANOPY[3], ob.CANOPY[5], ob.CANOPY[7], pad_x=4)
    ob.draw_oak_leaf(c0, 12, 13, 0.85, -0.48, 4.6, ob.CANOPY[2], ob.CANOPY[4], ob.CANOPY[6], pad_x=4)
    ob.finish_foliage(c0, pad_x=4)
    ob.write_png(OUT_DIR / "s0.png", fw * 2, fh, pack_strip([skirt, c0], fw, fh))
    return make_rig_entry(fw, fh, fx, fy, 18, 10, 2, 2, 6, "s0", "", 2, 0,
        {"root_skirt": 0, "trunk_base": -1, "trunk_upper": -1, "harvest_amber": -1, "kerf_1": -1, "kerf_2": -1, "overhang": -1},
        {"trunk_glow": -1, "harvest_glow": -1, "cluster_glow_start": -1},
        [{"col": 1, "role": "sprout", "side": 0.0, "anchor": [12, 19], "stiffness": 1.35, "flutter": 0.58, "phase": 0.0, "lobe": [0, 0, 6, 4]}])


def build_s1():
    fw, fh, fx, fy, cut_y = 48, 56, 24, 48, 43
    boughs = [
        ([(fx, 34), (fx - 4, 29)], 1.6, 0.9, 0.0, 0.0, False, 0),
        ([(fx, 31), (fx + 4, 26)], 1.5, 0.9, 0.0, 0.0, False, 0),
    ]
    skirt, tbase, tupper, _ = ob.build_unified_oak_skeleton(fw, fh, fx, fy, cut_y, 30, 3, boughs, 101, n_roots=2, pad_x=10)
    c0, c1 = ob.blank(fw, fh), ob.blank(fw, fh)
    ob.render_oak_cluster_volume(c0, None, [(21, 31, 9, 7, -1.2, -1)], fx, 27, 13, 111, pad_x=10)
    ob.render_oak_cluster_volume(c1, None, [(26, 23, 10, 7, 1.4, 1)], fx, 27, 13, 113, pad_x=10)
    ob.finish_foliage(c0, 10)
    ob.finish_foliage(c1, 10)
    ob.write_png(OUT_DIR / "s1.png", fw * 5, fh, pack_strip([skirt, tbase, tupper, c0, c1], fw, fh))
    return make_rig_entry(fw, fh, fx, fy, cut_y, 34, 10, 3, 13, "s1", "", 5, 0,
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": 2, "harvest_amber": -1, "kerf_1": -1, "kerf_2": -1, "overhang": -1},
        {"trunk_glow": -1, "harvest_glow": -1, "cluster_glow_start": -1},
        [{"col": 3, "role": "back_core", "side": -0.5, "anchor": [22, 33], "stiffness": 1.15, "flutter": 0.50, "phase": 0.0, "lobe": [-4, 2, 10, 6]},
         {"col": 4, "role": "sun_crest", "side": 0.5, "anchor": [25, 25], "stiffness": 1.05, "flutter": 0.54, "phase": 1.3, "lobe": [3, -2, 11, 7]}])


def build_s2():
    fw, fh, fx, fy, cut_y = 88, 104, 44, 92, 83
    boughs = [
        ([(fx, 59), (fx - 8, 54), (fx - 13, 48)], 2.8, 1.2, 0.0, 0.0, False, 0),
        ([(fx, 55), (fx + 8, 50), (fx + 13, 45)], 2.5, 1.2, 0.0, 0.0, False, 0),
    ]
    skirt, tbase, tupper, _ = ob.build_unified_oak_skeleton(fw, fh, fx, fy, cut_y, 54, 5, boughs, 201, n_roots=3, pad_x=10)
    k1 = ob.blank(fw, fh)
    ob.draw_kerf(k1, fx, cut_y, 5, deep=False)
    c0, c1, c2 = ob.blank(fw, fh), ob.blank(fw, fh), ob.blank(fw, fh)
    ob.render_oak_cluster_volume(c0, None, [(44, 52, 20, 14, -2.0, -2)], fx, 44, 26, 211, pad_x=10)
    ob.render_oak_cluster_volume(c1, None, [(30, 52, 16, 13, 0.8, 0), (57, 53, 15, 12, 0.4, -1)], fx, 44, 26, 213, pad_x=10)
    ob.render_oak_cluster_volume(c2, None, [(43, 35, 19, 13, 1.8, 1)], fx, 44, 26, 217, pad_x=10)
    for c in (c0, c1, c2):
        ob.finish_foliage(c, 10)
    ob.write_png(OUT_DIR / "s2.png", fw * 7, fh, pack_strip([skirt, tbase, tupper, k1, c0, c1, c2], fw, fh))
    return make_rig_entry(fw, fh, fx, fy, cut_y, 74, 26, 5, 26, "s2", "", 7, 0,
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": 2, "harvest_amber": -1, "kerf_1": 3, "kerf_2": -1, "overhang": -1},
        {"trunk_glow": -1, "harvest_glow": -1, "cluster_glow_start": -1},
        [{"col": 4, "role": "back_core", "side": 0.0, "anchor": [44, 56], "stiffness": 1.15, "flutter": 0.42, "phase": 0.0, "lobe": [2, 3, 20, 12]},
         {"col": 5, "role": "left_bough", "side": -0.8, "anchor": [38, 54], "stiffness": 0.98, "flutter": 0.48, "phase": 1.2, "lobe": [-8, 2, 22, 13]},
         {"col": 6, "role": "sun_crest", "side": 0.4, "anchor": [44, 40], "stiffness": 0.92, "flutter": 0.52, "phase": 2.4, "lobe": [-2, -4, 20, 12]}])


def build_s3():
    fw, fh, fx, fy, cut_y = 136, 152, 68, 136, 125
    tg, k1, k2 = ob.blank(fw, fh), ob.blank(fw, fh), ob.blank(fw, fh)
    # Compact, staggered crooked inner boughs (stay well inside crown; leaves drape BELOW fork!)
    boughs = [
        ([(fx - 1, 88), (fx - 13, 82), (fx - 23, 74)], 4.2, 1.6, 0.0, 0.0, False, 0),
        ([(fx + 1, 82), (fx + 13, 76), (fx + 22, 69)], 3.8, 1.5, 0.0, 0.0, False, 0),
        ([(fx, 80), (fx - 6, 66), (fx + 4, 58)], 3.0, 1.3, 0.0, 0.0, False, -1),
    ]
    skirt, tbase, tupper, spans = ob.build_unified_oak_skeleton(fw, fh, fx, fy, cut_y, 80, 8, boughs, 301, n_roots=4, glow_root=tg, pad_x=10)
    ob.draw_kerf(k1, fx, cut_y, 8, deep=False)
    ob.draw_kerf(k2, fx, cut_y, 8, deep=True)
    cs, gs = [ob.blank(fw, fh) for _ in range(4)], [ob.blank(fw, fh) for _ in range(4)]
    ob.render_oak_cluster_volume(cs[0], gs[0], [(54, 74, 24, 16, -2.5, -2), (82, 75, 24, 16, -2.5, -2), (68, 58, 25, 16, -2.0, -2)], fx, 64, 46, 311, 10, glows=2)
    ob.render_oak_cluster_volume(cs[1], gs[1], [(40, 78, 22, 15, 0.9, 0), (54, 62, 19, 13, 1.3, 1)], fx, 64, 46, 315, 10, acorns=2, glows=2)
    ob.render_oak_cluster_volume(cs[2], gs[2], [(96, 80, 21, 15, 0.7, -1), (84, 64, 18, 13, 1.0, 0)], fx, 64, 46, 319, 10, acorns=2, glows=2)
    ob.render_oak_cluster_volume(cs[3], gs[3], [(65, 43, 25, 16, 2.2, 1), (78, 50, 19, 13, 1.8, 1)], fx, 64, 46, 323, 10, acorns=0, glows=2)
    for c in cs:
        ob.finish_foliage(c, 10)
    t_frames, fg_teal, traits = ob.build_modular_traits(fw, fh, fx, fy, cut_y, 84, 8, spans, 331, base_col=9, glow_col=5, pad_x=10)
    all_cols = [skirt, tbase, tupper, k1, k2, *cs, *t_frames]
    all_glows = [tg, *gs, fg_teal]
    ob.write_png(OUT_DIR / "s3.png", fw * len(all_cols), fh, pack_strip(all_cols, fw, fh))
    ob.write_png(OUT_DIR / "s3_glow.png", fw * len(all_glows), fh, pack_strip(all_glows, fw, fh))
    return make_rig_entry(fw, fh, fx, fy, cut_y, 118, 44, 8, 46, "s3", "s3_glow", len(all_cols), len(all_glows),
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": 2, "harvest_amber": -1, "kerf_1": 3, "kerf_2": 4, "overhang": -1},
        {"trunk_glow": 0, "harvest_glow": -1, "cluster_glow_start": 1},
        [{"col": 5, "role": "back_core", "side": 0.0, "anchor": [68, 78], "stiffness": 1.15, "flutter": 0.36, "phase": 0.0, "lobe": [0, 4, 32, 18]},
         {"col": 6, "role": "left_bough", "side": -1.0, "anchor": [54, 78], "stiffness": 0.94, "flutter": 0.44, "phase": 1.1, "lobe": [-18, 2, 26, 15]},
         {"col": 7, "role": "right_bough", "side": 1.0, "anchor": [82, 78], "stiffness": 0.94, "flutter": 0.44, "phase": 2.3, "lobe": [18, 2, 26, 15]},
         {"col": 8, "role": "sun_crest", "side": 0.0, "anchor": [68, 54], "stiffness": 0.88, "flutter": 0.48, "phase": 3.5, "lobe": [-2, -6, 28, 16]}],
        perches=[[-24, 68, 1], [22, 64, 2]], traits=traits)


def build_s4_variant(variant_key: str, seed_base: int):
    fw, fh, fx, fy, cut_y = 196, 200, 98, 180, 167
    tg, hg, harv, k1, k2 = ob.blank(fw, fh), ob.blank(fw, fh), ob.blank(fw, fh), ob.blank(fw, fh), ob.blank(fw, fh)
    if variant_key == "s4":
        fork_y = 108
        bole = [(fx + 1, fy + 1), (fx, cut_y), (fx - 3, 142), (fx + 1, fork_y)]
        boughs = [
            ([(fx - 1, 118), (fx - 18, 110), (fx - 34, 102)], 5.2, 1.7, 0.0, 0.0, False, 0),
            ([(fx + 1, 110), (fx + 18, 102), (fx + 33, 95)], 4.8, 1.7, 0.0, 0.0, False, 0),
            ([(fx, 108), (fx - 9, 88), (fx - 16, 74)], 3.8, 1.5, 0.0, 0.0, False, -1),
            ([(fx + 1, 108), (fx + 10, 88), (fx + 16, 76)], 3.6, 1.5, 0.0, 0.0, False, -1),
        ]
        c_bolsters = [
            [(68, 98, 28, 18, -3.0, -2), (128, 98, 28, 18, -3.0, -2), (98, 104, 25, 17, -3.4, -2), (98, 68, 34, 18, -2.5, -2)],
            [(44, 107, 26, 17, 0.9, 0), (68, 111, 21, 15, 0.8, -1), (56, 84, 24, 16, 1.5, 1)],
            [(150, 106, 26, 17, 0.6, -1), (128, 109, 21, 15, 0.5, -1), (140, 84, 23, 15, 1.1, 0)],
            [(96, 94, 29, 17, 1.8, 0), (74, 74, 24, 15, 1.5, 0), (120, 76, 24, 15, 1.3, -1)],
            [(80, 48, 28, 17, 2.5, 1), (114, 52, 26, 16, 2.1, 1), (96, 38, 26, 15, 2.7, 1)],
        ]
    elif variant_key == "s4_b":
        # Crooked twin-stem valley oak splitting lower at y=136 into unequal ascending stems
        fork_y = 134
        bole = [(fx, fy + 1), (fx, cut_y), (fx - 1, 150), (fx, fork_y)]
        boughs = [
            ([(fx - 1, 136), (fx - 10, 118), (fx - 17, 96)], 7.6, 2.4, 0.0, 0.0, False, 0),
            ([(fx + 2, 135), (fx + 12, 119), (fx + 20, 100)], 6.5, 2.2, 0.0, 0.0, False, 0),
            ([(fx - 12, 112), (fx - 26, 104), (fx - 38, 96)], 4.2, 1.6, 0.0, 0.0, False, -1),
            ([(fx + 14, 114), (fx + 28, 106), (fx + 39, 98)], 3.8, 1.6, 0.0, 0.0, False, -1),
        ]
        c_bolsters = [
            [(66, 96, 28, 18, -3.0, -2), (130, 100, 28, 18, -3.0, -2), (98, 96, 26, 17, -3.2, -2), (94, 66, 32, 18, -2.5, -2)],
            [(42, 104, 25, 17, 0.9, 0), (66, 108, 22, 15, 0.8, 0), (54, 80, 24, 16, 1.5, 1)],
            [(152, 109, 25, 17, 0.6, -1), (128, 111, 22, 15, 0.5, -1), (142, 86, 23, 15, 1.1, 0)],
            [(86, 92, 26, 16, 1.8, 0), (114, 96, 25, 16, 1.6, -1), (98, 74, 26, 16, 1.5, 0)],
            [(74, 46, 28, 17, 2.6, 1), (118, 54, 26, 16, 2.1, 1), (94, 40, 24, 15, 2.4, 1)],
        ]
    else:
        # s4_c: Wind-swept leaning glade oak sweeping gracefully rightward
        fork_y = 110
        bole = [(fx - 1, fy + 1), (fx, cut_y), (fx + 6, 138), (fx + 11, fork_y)]
        boughs = [
            ([(fx + 8, 118), (fx - 8, 108), (fx - 24, 98)], 4.8, 1.6, 0.0, 0.0, False, 0),
            ([(fx + 11, 114), (fx + 28, 106), (fx + 44, 100)], 5.4, 1.8, 0.0, 0.0, False, 0),
            ([(fx + 10, 110), (fx + 4, 88), (fx - 2, 74)], 4.0, 1.5, 0.0, 0.0, False, -1),
            ([(fx + 11, 110), (fx + 22, 90), (fx + 30, 78)], 3.8, 1.5, 0.0, 0.0, False, -1),
        ]
        c_bolsters = [
            [(74, 94, 27, 17, -3.0, -2), (134, 100, 28, 18, -3.0, -2), (106, 104, 25, 17, -3.4, -2), (104, 68, 33, 18, -2.5, -2)],
            [(50, 98, 24, 16, 0.9, 0), (72, 104, 21, 15, 0.8, 0), (62, 78, 24, 16, 1.5, 1)],
            [(152, 110, 25, 17, 0.7, -1), (130, 112, 22, 15, 0.6, -1), (144, 88, 24, 16, 1.1, 0)],
            [(104, 94, 28, 17, 1.8, 0), (84, 74, 24, 15, 1.5, 0), (126, 78, 24, 15, 1.3, -1)],
            [(86, 48, 27, 16, 2.5, 1), (120, 52, 26, 16, 2.2, 1), (102, 38, 26, 15, 2.7, 1)],
        ]

    skirt, tbase, tupper, spans = ob.build_unified_oak_skeleton(fw, fh, fx, fy, cut_y, fork_y, 11, boughs, seed_base, n_roots=5, glow_root=tg, pad_x=10, bole_pts=bole)
    ob.draw_harvest_amber_only(harv, hg, spans, 148, seed_base + 13)
    ob.draw_kerf(k1, fx, cut_y, 11, deep=False)
    ob.draw_kerf(k2, fx, cut_y, 11, deep=True)

    cs, gs = [ob.blank(fw, fh) for _ in range(5)], [ob.blank(fw, fh) for _ in range(5)]
    for ci in range(5):
        ac_n = 3 if ci in (1, 2) else (2 if ci == 3 else 0)
        ob.render_oak_cluster_volume(cs[ci], gs[ci], c_bolsters[ci], fx, 78, 76, seed_base + 21 + ci * 7, 10, acorns=ac_n, glows=2)
        ob.finish_foliage(cs[ci], 10)

    t_frames, fg_teal, traits = ob.build_modular_traits(fw, fh, fx, fy, cut_y, min(fork_y, 118), 11, spans, seed_base + 71, base_col=11, glow_col=7, pad_x=10)
    all_cols = [skirt, tbase, tupper, harv, k1, k2, *cs, *t_frames]
    all_glows = [tg, hg, *gs, fg_teal]
    ob.write_png(OUT_DIR / f"{variant_key}.png", fw * len(all_cols), fh, pack_strip(all_cols, fw, fh))
    ob.write_png(OUT_DIR / f"{variant_key}_glow.png", fw * len(all_glows), fh, pack_strip(all_glows, fw, fh))
    return make_rig_entry(fw, fh, fx, fy, cut_y, 164, 52, 11, 76, variant_key, f"{variant_key}_glow", len(all_cols), len(all_glows),
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": 2, "harvest_amber": 3, "kerf_1": 4, "kerf_2": 5, "overhang": -1},
        {"trunk_glow": 0, "harvest_glow": 1, "cluster_glow_start": 2},
        [{"col": 6, "role": "back_core", "side": 0.0, "anchor": [98, 98], "stiffness": 1.18, "flutter": 0.34, "phase": 0.0, "lobe": [0, 6, 48, 28]},
         {"col": 7, "role": "left_bough", "side": -1.0, "anchor": [68, 102], "stiffness": 0.90, "flutter": 0.44, "phase": 1.1, "lobe": [-32, 4, 38, 22]},
         {"col": 8, "role": "right_bough", "side": 1.0, "anchor": [128, 102], "stiffness": 0.90, "flutter": 0.44, "phase": 2.2, "lobe": [32, 4, 38, 22]},
         {"col": 9, "role": "mid_heart", "side": 0.0, "anchor": [98, 92], "stiffness": 1.02, "flutter": 0.38, "phase": 3.3, "lobe": [0, 2, 40, 24]},
         {"col": 10, "role": "sun_crest", "side": 0.0, "anchor": [96, 62], "stiffness": 0.85, "flutter": 0.48, "phase": 4.4, "lobe": [-4, -8, 42, 24]}],
        perches=[[-36, 92, 1], [34, 86, 2], [-6, 144, 4]], traits=traits)


def build_s5():
    fw, fh, fx, fy, cut_y = 264, 244, 132, 220, 205
    tg, hg, harv, k1, k2, over = ob.blank(fw, fh), ob.blank(fw, fh), ob.blank(fw, fh), ob.blank(fw, fh), ob.blank(fw, fh), ob.blank(fw, fh)
    # Compact, crooked staggered inner scaffold limbs (ZERO bare top stag-head sticks, ZERO slingshot logs!)
    fork_y = 132
    bole = [(fx + 1, fy + 1), (fx, cut_y), (fx - 4, 172), (fx + 2, fork_y)]
    boughs = [
        ([(fx - 2, 144), (fx - 24, 134), (fx - 46, 124)], 7.6, 2.2, 0.0, 0.0, False, 0),
        ([(fx + 3, 136), (fx + 26, 126), (fx + 46, 118)], 7.2, 2.2, 0.0, 0.0, False, 0),
        ([(fx, 132), (fx - 14, 108), (fx - 24, 92)], 5.4, 1.8, 0.0, 0.0, False, -1),
        ([(fx + 2, 132), (fx + 15, 106), (fx + 24, 92)], 5.2, 1.8, 0.0, 0.0, False, -1),
    ]
    skirt, tbase, tupper, spans = ob.build_unified_oak_skeleton(fw, fh, fx, fy, cut_y, fork_y, 16, boughs, 501, n_roots=5, clover=(28, 4), glow_root=tg, pad_x=12, bole_pts=bole)
    ob.draw_harvest_amber_only(harv, hg, spans, 176, 519)
    ob.draw_kerf(k1, fx, cut_y, 16, deep=False)
    ob.draw_kerf(k2, fx, cut_y, 16, deep=True)

    cs, gs = [ob.blank(fw, fh) for _ in range(6)], [ob.blank(fw, fh) for _ in range(6)]
    # Enveloping bough clusters draping down over & below the branch forks (bell-arched oak crown underside!)
    ob.render_oak_cluster_volume(cs[0], gs[0], [(88, 116, 36, 21, -3.2, -2), (176, 118, 36, 21, -3.2, -2), (132, 124, 34, 20, -3.6, -2), (132, 82, 42, 22, -2.6, -2)], fx, 96, 102, 521, 12, glows=2)
    ob.render_oak_cluster_volume(cs[1], gs[1], [(52, 132, 32, 19, 0.9, 0), (84, 135, 26, 17, 0.8, -1), (68, 104, 30, 18, 1.5, 1)], fx, 96, 102, 527, 12, acorns=3, glows=2)
    ob.render_oak_cluster_volume(cs[2], gs[2], [(212, 133, 32, 19, 0.6, -1), (180, 135, 26, 17, 0.5, -1), (196, 106, 30, 18, 1.1, 0)], fx, 96, 102, 533, 12, acorns=3, glows=2)
    ob.render_oak_cluster_volume(cs[3], gs[3], [(82, 74, 32, 18, 1.9, 1), (56, 92, 25, 16, 1.5, 1)], fx, 96, 102, 539, 12, acorns=2, glows=2)
    ob.render_oak_cluster_volume(cs[4], gs[4], [(132, 114, 36, 19, 1.9, 0), (100, 96, 28, 16, 1.5, 0), (164, 98, 28, 16, 1.3, -1)], fx, 96, 102, 543, 12, acorns=3, glows=2)
    ob.render_oak_cluster_volume(cs[5], gs[5], [(114, 52, 34, 19, 2.7, 1), (154, 56, 32, 18, 2.3, 1), (182, 78, 28, 17, 1.8, 0)], fx, 96, 102, 549, 12, acorns=0, glows=2)
    for c in cs:
        ob.finish_foliage(c, 12)
    ob.render_oak_cluster_volume(over, None, [(68, 66, 23, 13, 2.4, 1), (196, 68, 23, 13, 2.0, 0)], fx, 96, 102, 555, 12)
    ob.finish_foliage(over, 12)

    t_frames, fg_teal, traits = ob.build_modular_traits(fw, fh, fx, fy, cut_y, fork_y, 16, spans, 571, base_col=13, glow_col=8, dendro_at=(fx - 5, fy - 60), pad_x=12)
    all_cols = [skirt, tbase, tupper, harv, k1, k2, *cs, over, *t_frames]
    all_glows = [tg, hg, *gs, fg_teal]
    ob.write_png(OUT_DIR / "s5.png", fw * len(all_cols), fh, pack_strip(all_cols, fw, fh))
    ob.write_png(OUT_DIR / "s5_glow.png", fw * len(all_glows), fh, pack_strip(all_glows, fw, fh))
    return make_rig_entry(fw, fh, fx, fy, cut_y, 204, 60, 16, 102, "s5", "s5_glow", len(all_cols), len(all_glows),
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": 2, "harvest_amber": 3, "kerf_1": 4, "kerf_2": 5, "overhang": 12},
        {"trunk_glow": 0, "harvest_glow": 1, "cluster_glow_start": 2},
        [{"col": 6, "role": "back_core", "side": 0.0, "anchor": [132, 120], "stiffness": 1.22, "flutter": 0.32, "phase": 0.0, "lobe": [0, 8, 66, 36]},
         {"col": 7, "role": "left_bough", "side": -1.0, "anchor": [88, 126], "stiffness": 0.88, "flutter": 0.42, "phase": 1.0, "lobe": [-48, 6, 48, 28]},
         {"col": 8, "role": "right_bough", "side": 1.0, "anchor": [176, 126], "stiffness": 0.88, "flutter": 0.42, "phase": 2.1, "lobe": [48, 6, 48, 28]},
         {"col": 9, "role": "left_upper", "side": -0.7, "anchor": [96, 86], "stiffness": 0.92, "flutter": 0.45, "phase": 3.2, "lobe": [-30, -4, 40, 24]},
         {"col": 10, "role": "mid_heart", "side": 0.0, "anchor": [132, 114], "stiffness": 1.05, "flutter": 0.36, "phase": 4.3, "lobe": [0, 4, 52, 30]},
         {"col": 11, "role": "sun_crest", "side": 0.2, "anchor": [138, 74], "stiffness": 0.84, "flutter": 0.48, "phase": 5.4, "lobe": [8, -10, 52, 30]}],
        perches=[[-54, 98, 1], [52, 94, 2], [-18, 158, 4], [24, 152, 5]],
        hollow=[-5, -60], rest=[28, 4], traits=traits)


def build_coppice():
    fw, fh, fx, fy, cut_y = 96, 88, 48, 72, 60
    skirt, tbase, _, _ = ob.build_unified_oak_skeleton(fw, fh, fx, fy, cut_y, cut_y - 1, 11, [], 601, n_roots=5, pad_x=6)
    c0 = ob.blank(fw, fh)
    for sx, tx, ty, sd in ((fx - 9, fx - 19, 44, 611), (fx - 4, fx - 7, 38, 613), (fx + 4, fx + 8, 40, 615), (fx + 9, fx + 18, 46, 617)):
        ob.draw_limb(c0, [(sx, cut_y - 1), ((sx + tx) // 2, (cut_y + ty) // 2), (tx, ty)], 1.6, 0.9, sd, moss=0.0, pad_x=10)
    ob.render_oak_cluster_volume(c0, None, [(fx - 18, 44, 10, 7, 0.8, 1), (fx - 6, 38, 11, 8, 1.4, 1), (fx + 8, 40, 11, 8, 1.1, 0), (fx + 18, 46, 10, 7, 0.6, -1)], fx, 42, 24, 621, pad_x=10)
    ob.finish_foliage(c0, 10)
    ob.write_png(OUT_DIR / "coppice.png", fw * 3, fh, pack_strip([skirt, tbase, c0], fw, fh))
    return make_rig_entry(fw, fh, fx, fy, cut_y, 30, 4, 11, 22, "coppice", "", 3, 0,
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": -1, "harvest_amber": -1, "kerf_1": -1, "kerf_2": -1, "overhang": -1},
        {"trunk_glow": -1, "harvest_glow": -1, "cluster_glow_start": -1},
        [{"col": 2, "role": "coppice_shoots", "side": 0.0, "anchor": [48, 60], "stiffness": 1.10, "flutter": 0.56, "phase": 0.0, "lobe": [0, 0, 22, 13]}])


def build_s6_log():
    fw, fh, fx, fy, cut_y = 152, 64, 76, 48, 42
    skirt, tbase, c0, tg = ob.blank(fw, fh), ob.blank(fw, fh), ob.blank(fw, fh), ob.blank(fw, fh)
    for y in range(fy - 8, fy + 12):
        for x in range(18, fw - 16):
            d = math.hypot((x - fx - 3) / 54.0, (y - fy - 2) / 9.0) + (ob.vnoise(x * 0.2, y * 0.25, 701) - 0.5) * 0.2
            if d < 1.0:
                ob.put_contact_shadow(skirt, x, y, int(115 * ((1.0 - d) ** 1.4)))
    ob.draw_limb(tbase, [(28, 44), (62, 40), (96, 42), (124, 45)], 10.5, 8.2, 705, moss=0.78, lichen=0.25, pad_x=10)
    ob.selout_bark(tbase, pad_x=10, stop_y=fy + 2)
    ob.draw_hollow(tbase, 28, 44, 5, 7)
    ob.draw_cut_rings(tbase, 124, 45, 5, 7)
    ob.draw_amber_polypore(tbase, tg, 66, 44, 9, 707)
    ob.draw_amber_polypore(tbase, tg, 98, 45, 8, 709)
    ob.draw_moss_and_litter(skirt, tbase, fx, fy + 2, 18, 703)
    for gx in (42, 54, 82, 110):
        ob.put(tg, gx, 43 + (gx % 3), ob.GLOW[1])
    for sx, sy, sd in ((48, 30, 711), (78, 28, 713), (104, 32, 715)):
        for y in range(sy, sy + 7):
            ob.put(c0, sx, y, ob.CANOPY[4])
        ob.draw_oak_leaf(c0, sx, sy + 1, -0.85, -0.5, 4.6, ob.CANOPY[3], ob.CANOPY[5], ob.CANOPY[7], pad_x=10)
        ob.draw_oak_leaf(c0, sx, sy, 0.85, -0.45, 4.6, ob.CANOPY[2], ob.CANOPY[4], ob.CANOPY[6], pad_x=10)
    for fx0 in (62, 90):
        for a in (-2.2, -1.57, -0.95):
            ob.draw_oak_leaf(c0, fx0, 34, math.cos(a), math.sin(a), 5.2, ob.MOSS[1], ob.MOSS[2], ob.MOSS[4], pad_x=10)
    ob.finish_foliage(c0, 10)
    ob.write_png(OUT_DIR / "s6_log.png", fw * 3, fh, pack_strip([skirt, tbase, c0], fw, fh))
    ob.write_png(OUT_DIR / "s6_log_glow.png", fw, fh, tg)
    return make_rig_entry(fw, fh, fx, fy, cut_y, 32, 4, 14, 48, "s6_log", "s6_log_glow", 3, 1,
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": -1, "harvest_amber": -1, "kerf_1": -1, "kerf_2": -1, "overhang": -1},
        {"trunk_glow": 0, "harvest_glow": -1, "cluster_glow_start": -1},
        [{"col": 2, "role": "nurse_sprouts", "side": 0.0, "anchor": [76, 36], "stiffness": 1.20, "flutter": 0.58, "phase": 0.0, "lobe": [0, 0, 44, 12]}])


def composite_onto(dst, ox: int, oy: int, frames: list, glows: list, r: dict, night: bool = False, trait_cols=None, show_amber: bool = False, glow_trait_cols=None) -> None:
    lay = r["layers"]
    gl = r["glow_layers"]
    amber_c = lay["harvest_amber"] if show_amber else -1
    order = [lay["root_skirt"], lay["trunk_base"], lay["trunk_upper"]] + (trait_cols or []) + [amber_c] + [c["col"] for c in r["clusters"]] + [lay["overhang"]]
    for ci in order:
        if 0 <= ci < len(frames):
            fr = frames[ci]
            if night:
                tinted = [[(max(12, int(p[0] * 0.34)), max(16, int(p[1] * 0.40)), max(28, int(p[2] * 0.54)), p[3]) if p[3] > 0 else ob.CLEAR for p in row] for row in fr]
                ob.blit(dst, tinted, ox, oy)
            else:
                ob.blit(dst, fr, ox, oy)
    if night and glows:
        g_order = [gl["trunk_glow"]] + ([gl["harvest_glow"]] if show_amber else []) + (glow_trait_cols or [])
        if gl["cluster_glow_start"] >= 0:
            g_order.extend(range(gl["cluster_glow_start"], gl["cluster_glow_start"] + len(r["clusters"])))
        for gi in g_order:
            if 0 <= gi < len(glows):
                ob.blit(dst, glows[gi], ox, oy)


def read_frames_from_disk(path: pathlib.Path, fw: int, fh: int, ncols: int) -> list:
    import struct, zlib
    raw = path.read_bytes()
    pos, idat, w_all = 8, bytearray(), fw * ncols
    while pos < len(raw):
        ln = struct.unpack(">I", raw[pos:pos + 4])[0]
        if raw[pos + 4:pos + 8] == b"IDAT":
            idat.extend(raw[pos + 8:pos + 8 + ln])
        pos += 12 + ln
    dec = zlib.decompress(bytes(idat))
    stride = 1 + w_all * 4
    frames = [ob.blank(fw, fh) for _ in range(ncols)]
    for y in range(fh):
        row = dec[y * stride + 1:(y + 1) * stride]
        for x in range(w_all):
            p = x * 4
            rgba = (row[p], row[p + 1], row[p + 2], row[p + 3])
            if rgba[3] > 0 and rgba[0] == 0 and rgba[1] == 0 and rgba[2] == 0:
                raise RuntimeError(f"Forbidden #000000 pixel in {path} at ({x},{y})!")
            frames[x // fw][y][x % fw] = rgba
    return frames


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    icon_paths = ob.build_oak_icons()
    for ip in icon_paths:
        read_frames_from_disk(ip, 16, 16, 1)
    rig = {
        "s0": build_s0(), "s1": build_s1(), "s2": build_s2(), "s3": build_s3(),
        "s4": build_s4_variant("s4", 401), "s4_b": build_s4_variant("s4_b", 451), "s4_c": build_s4_variant("s4_c", 481),
        "s5": build_s5(), "coppice": build_coppice(), "s6_log": build_s6_log(),
    }
    RIG_JSON.write_text(json.dumps(rig, indent=1) + "\n", encoding="utf-8")

    # Wide QA sheet showcasing s0..s3 + s4/s4_b/s4_c/s5 with distinct modular trait loadouts (day + night)!
    sw, sh = 1280, 530
    qa = ob.blank(sw, sh)
    meadow_tones = [ob.hexc("264a3b"), ob.hexc("2e5944"), ob.hexc("386a4d"), ob.hexc("447a55")]
    night_tones = [ob.hexc("111828"), ob.hexc("141d2e"), ob.hexc("182334")]
    for y in range(sh):
        for x in range(sw):
            v = ob.fbm(x * 0.08, y * 0.12, 999)
            qa[y][x] = meadow_tones[ob.clampi(int(v * 4.2), 0, 3)] if y < 276 else night_tones[ob.clampi(int(v * 3.2), 0, 2)]

    lineup = [
        ("s0", [], False, []),
        ("s1", [], False, []),
        ("s2", [], False, []),
        ("s3", [rig["s3"]["traits"]["moss"][0], rig["s3"]["traits"]["sprig"][1]], False, []),
        # s4: Clean sun-bark + epicormic left sprig (zero mushrooms, zero holes!)
        ("s4", [rig["s4"]["traits"]["sprig"][0]], False, []),
        # s4_b: Crooked twin-stem + root moss + warm ochre brackets + basal root burrow
        ("s4_b", [rig["s4_b"]["traits"]["moss"][0], rig["s4_b"]["traits"]["hollow"][2], rig["s4_b"]["traits"]["fungi"][0]], False, []),
        # s4_c: Wind-swept leaning oak + dark woodland ivy + high woodpecker hole + ripe Wundharz
        ("s4_c", [rig["s4_c"]["traits"]["ivy"][0], rig["s4_c"]["traits"]["hollow"][0]], True, []),
        # s5: Ancient Matriarch + root moss + dark right ivy + fork Dendrotelm + Glimmschwamm polypores + Wundharz
        ("s5", [rig["s5"]["traits"]["moss"][0], rig["s5"]["traits"]["ivy"][1], rig["s5"]["traits"]["hollow"][1], rig["s5"]["traits"]["fungi"][1]], True, [rig["s5"]["traits"]["fungi_glow"][1]]),
    ]
    x_cur = 8
    for key, tcols, amb, gtcols in lineup:
        r = rig[key]
        frs = read_frames_from_disk(OUT_DIR / f"{key}.png", r["frame_w"], r["frame_h"], r["num_cols"])
        gfs = read_frames_from_disk(OUT_DIR / f"{key}_glow.png", r["frame_w"], r["frame_h"], r["glow_cols"]) if r["glow_cols"] > 0 else []
        composite_onto(qa, x_cur, 266 - r["feet_y"], frs, gfs, r, night=False, trait_cols=tcols, show_amber=amb, glow_trait_cols=gtcols)
        if key in ("s3", "s4", "s4_b", "s4_c", "s5"):
            composite_onto(qa, x_cur, 518 - r["feet_y"], frs, gfs, r, night=True, trait_cols=tcols, show_amber=amb, glow_trait_cols=gtcols)
        x_cur += r["frame_w"] + 2

    for key, ox, oy, is_n in (("coppice", 12, 58, False), ("s6_log", 112, 58, False), ("coppice", 12, 310, True), ("s6_log", 12, 435, True)):
        r = rig[key]
        frs = read_frames_from_disk(OUT_DIR / f"{key}.png", r["frame_w"], r["frame_h"], r["num_cols"])
        gfs = read_frames_from_disk(OUT_DIR / f"{key}_glow.png", r["frame_w"], r["frame_h"], r["glow_cols"]) if r["glow_cols"] > 0 else []
        composite_onto(qa, ox, oy, frs, gfs, r, night=is_n)
    for idx, ip in enumerate(icon_paths):
        ic = read_frames_from_disk(ip, 16, 16, 1)[0]
        for y in range(16):
            for x in range(16):
                if ic[y][x][3] > 0:
                    for dy in (0, 1):
                        for dx in (0, 1):
                            ob.put(qa, 18 + idx * 38 + x * 2 + dx, 14 + y * 2 + dy, ic[y][x])
    ob.write_png(QA_SHEET, sw, sh, qa)
    read_frames_from_disk(QA_SHEET, sw, sh, 1)
    print("Generated modular 2.0 Glimmtal-Stieleiche variants, traits, rig JSON & QA sheet (0 #000000 verified).")


if __name__ == "__main__":
    main()
