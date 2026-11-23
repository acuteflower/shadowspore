#!/usr/bin/env python3
"""Procedural 2.0 botanical pixel-art generator for Glimmtal-Hängebirke (Betula pendula glimmensis):
  assets/items/{birch_wood,birch_bark,birch_sap,birch_catkin,birch_chaga}.png
  assets/props/silver_birch/{s0..s5,s4_b,s4_c,coppice,s6_log}.png + *_glow.png
  data/silver_birch_rig.json
  docs/img/silver_birch_sheet.png + docs/img/silver_birch_zoom_3x.png
Zero #000000 pixels anywhere; stdlib + birch_botany.py only.
"""
import json
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import birch_botany as bb  # noqa: E402

OUT_DIR = bb.ROOT / "props" / "silver_birch"
RIG_JSON = bb.ROOT.parent / "data" / "silver_birch_rig.json"
QA_SHEET = bb.ROOT.parent / "docs" / "img" / "silver_birch_sheet.png"
ZOOM_SHEET = bb.ROOT.parent / "docs" / "img" / "silver_birch_zoom_3x.png"


def pack_strip(frames: list, fw: int, fh: int):
    strip = bb.blank(fw * len(frames), fh)
    for idx, fr in enumerate(frames):
        for y in range(fh):
            strip[y][idx * fw:(idx + 1) * fw] = fr[y][:]
    return strip


def make_rig_entry(fw, fh, fx, fy, cut_y, h_px, clr_px, th_px, ch_px, s_name, g_name, n_cols, g_cols, layers, g_layers, clusters, perches=None, hollow=None, rest=None, traits=None):
    d = {
        "frame_w": fw, "frame_h": fh, "feet_x": fx, "feet_y": fy, "cut_y": cut_y,
        "height_px": h_px, "clear_px": clr_px, "trunk_half_px": th_px, "crown_half_px": ch_px,
        "sheet": f"res://assets/props/silver_birch/{s_name}.png",
        "glow_sheet": f"res://assets/props/silver_birch/{g_name}.png" if g_name else "",
        "num_cols": n_cols, "glow_cols": g_cols,
        "layers": layers, "glow_layers": g_layers, "clusters": clusters,
        "perches": perches or [], "hollow": hollow or [], "rest_seat": rest or [],
    }
    if traits is not None:
        d["traits"] = traits
    return d


def build_s0():
    fw, fh, fx, fy = 24, 24, 12, 20
    skirt, c0 = bb.blank(fw, fh), bb.blank(fw, fh)
    for dy in range(-2, 3):
        for dx in range(-5, 6):
            d = math.hypot(dx / 5.5, dy / 2.2)
            if d < 1.0:
                bb.put_contact_shadow(skirt, fx + dx + 1, fy + dy, int(90 * (1.0 - d)))
    for dx in (-2, -1, 0, 1, 2):
        bb.put(skirt, fx + dx, fy, bb.MOSS[2 if dx <= 0 else 1])
    # Tiny V-winged golden-tan birch samara seed scale
    bb.put(skirt, fx, fy - 1, bb.CATKIN[1])
    bb.put(skirt, fx - 1, fy - 2, bb.CATKIN[3])
    bb.put(skirt, fx + 1, fy - 2, bb.CATKIN[2])
    for y in range(13, 19):
        bb.put(c0, fx, y, bb.COPPER[2] if y > 16 else bb.LEAF[4])
    bb.draw_diamond_leaf(c0, fx - 2, 13, None, bb.LEAF[3], bb.LEAF[5], bb.LEAF[6], pad_x=4)
    bb.draw_diamond_leaf(c0, fx + 2, 14, None, bb.LEAF[2], bb.LEAF[4], None, pad_x=4)
    bb.finish_birch_foliage(c0, pad_x=4)
    bb.write_png(OUT_DIR / "s0.png", fw * 2, fh, pack_strip([skirt, c0], fw, fh))
    return make_rig_entry(fw, fh, fx, fy, 18, 9, 2, 2, 5, "s0", "", 2, 0,
        {"root_skirt": 0, "trunk_base": -1, "trunk_upper": -1, "harvest_amber": -1, "kerf_1": -1, "kerf_2": -1, "overhang": -1},
        {"trunk_glow": -1, "harvest_glow": -1, "cluster_glow_start": -1},
        [{"col": 1, "role": "sprout", "side": 0.0, "anchor": [12, 19], "stiffness": 1.25, "flutter": 0.65, "phase": 0.0, "lobe": [0, 0, 5, 4]}])


def build_s1():
    fw, fh, fx, fy, cut_y = 48, 60, 24, 52, 47
    # Juvenile copper-bronze birch whip (Jugendrinde)
    stems = [([(fx, fy + 1), (fx, cut_y), (fx - 1, 35), (fx + 1, 24)], 2.1, 1.0)]
    boughs = [([(fx, 35), (fx - 5, 29)], 1.2, 0.8, True), ([(fx, 31), (fx + 5, 25)], 1.2, 0.8, True)]
    skirt, tbase, tupper, _ = bb.build_birch_skeleton(fw, fh, fx, fy, cut_y, 30, 2, stems, boughs, 0, 101, n_roots=2, pad_x=12, juvenile=True)
    c0, c1 = bb.blank(fw, fh), bb.blank(fw, fh)
    bb.render_weeping_birch_cluster(c0, None, [(22, 30, 7, 5, 7, -1.0, 0)], fx, 26, 10, 111, pad_x=12, catkins=0, glows=0)
    bb.render_weeping_birch_cluster(c1, None, [(26, 22, 8, 6, 8, 1.2, 1)], fx, 26, 10, 113, pad_x=12, catkins=1, glows=0)
    bb.finish_birch_foliage(c0, 12)
    bb.finish_birch_foliage(c1, 12)
    bb.write_png(OUT_DIR / "s1.png", fw * 5, fh, pack_strip([skirt, tbase, tupper, c0, c1], fw, fh))
    return make_rig_entry(fw, fh, fx, fy, cut_y, 38, 12, 2, 10, "s1", "", 5, 0,
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": 2, "harvest_amber": -1, "kerf_1": -1, "kerf_2": -1, "overhang": -1},
        {"trunk_glow": -1, "harvest_glow": -1, "cluster_glow_start": -1},
        [{"col": 3, "role": "back_core", "side": -0.5, "anchor": [23, 34], "stiffness": 0.95, "flutter": 0.58, "phase": 0.0, "lobe": [-3, 2, 8, 5]},
         {"col": 4, "role": "sun_crest", "side": 0.5, "anchor": [25, 25], "stiffness": 0.88, "flutter": 0.62, "phase": 1.4, "lobe": [2, -2, 9, 6]}])


def build_s2():
    fw, fh, fx, fy, cut_y = 88, 112, 44, 98, 89
    stems = [([(fx, fy + 1), (fx, cut_y), (fx - 2, 68), (fx + 1, 46)], 3.8, 1.8)]
    boughs = [
        ([(fx - 1, 64), (fx - 9, 54), (fx - 14, 48)], 2.0, 1.0, True),
        ([(fx + 1, 58), (fx + 9, 49), (fx + 14, 44)], 1.9, 1.0, True),
    ]
    skirt, tbase, tupper, _ = bb.build_birch_skeleton(fw, fh, fx, fy, cut_y, 56, 4, stems, boughs, 7, 201, n_roots=3, pad_x=12)
    k1 = bb.blank(fw, fh)
    bb.draw_birch_kerf(k1, fx, cut_y, 4, deep=False)
    c0, c1, c2 = bb.blank(fw, fh), bb.blank(fw, fh), bb.blank(fw, fh)
    bb.render_weeping_birch_cluster(c0, None, [(44, 50, 16, 10, 11, -2.0, -1)], fx, 44, 22, 211, pad_x=12, catkins=1, glows=0)
    bb.render_weeping_birch_cluster(c1, None, [(32, 50, 13, 9, 12, 0.8, 0), (56, 51, 13, 9, 12, 0.5, -1)], fx, 44, 22, 213, pad_x=12, catkins=2, glows=0)
    bb.render_weeping_birch_cluster(c2, None, [(43, 33, 16, 10, 11, 1.8, 1)], fx, 44, 22, 217, pad_x=12, catkins=2, glows=0)
    for c in (c0, c1, c2):
        bb.finish_birch_foliage(c, 12)
    bb.write_png(OUT_DIR / "s2.png", fw * 7, fh, pack_strip([skirt, tbase, tupper, k1, c0, c1, c2], fw, fh))
    return make_rig_entry(fw, fh, fx, fy, cut_y, 80, 28, 4, 22, "s2", "", 7, 0,
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": 2, "harvest_amber": -1, "kerf_1": 3, "kerf_2": -1, "overhang": -1},
        {"trunk_glow": -1, "harvest_glow": -1, "cluster_glow_start": -1},
        [{"col": 4, "role": "back_core", "side": 0.0, "anchor": [44, 56], "stiffness": 0.95, "flutter": 0.52, "phase": 0.0, "lobe": [0, 3, 18, 11]},
         {"col": 5, "role": "left_bough", "side": -0.8, "anchor": [39, 54], "stiffness": 0.82, "flutter": 0.58, "phase": 1.2, "lobe": [-7, 2, 19, 11]},
         {"col": 6, "role": "sun_crest", "side": 0.4, "anchor": [44, 38], "stiffness": 0.78, "flutter": 0.62, "phase": 2.4, "lobe": [-1, -3, 18, 11]}])


def build_s3():
    fw, fh, fx, fy, cut_y = 136, 164, 68, 148, 136
    tg, k1, k2 = bb.blank(fw, fh), bb.blank(fw, fh), bb.blank(fw, fh)
    stems = [([(fx, fy + 1), (fx, cut_y), (fx - 3, 108), (fx + 1, 78)], 5.8, 2.4)]
    boughs = [
        ([(fx - 2, 96), (fx - 14, 80), (fx - 22, 74)], 2.8, 1.2, True),
        ([(fx + 1, 90), (fx + 14, 76), (fx + 21, 70)], 2.6, 1.2, True),
        ([(fx, 80), (fx - 7, 62), (fx - 10, 52)], 2.2, 1.0, True),
    ]
    skirt, tbase, tupper, spans = bb.build_birch_skeleton(fw, fh, fx, fy, cut_y, 88, 6, stems, boughs, 13, 301, n_roots=4, glow_root=tg, pad_x=12)
    bb.draw_birch_kerf(k1, fx, cut_y, 6, deep=False)
    bb.draw_birch_kerf(k2, fx, cut_y, 6, deep=True)
    cs, gs = [bb.blank(fw, fh) for _ in range(4)], [bb.blank(fw, fh) for _ in range(4)]
    bb.render_weeping_birch_cluster(cs[0], gs[0], [(56, 74, 20, 12, 14, -2.5, -2), (80, 76, 20, 12, 14, -2.5, -2), (68, 58, 22, 12, 12, -2.0, -1)], fx, 64, 40, 311, 12, catkins=2, glows=2)
    bb.render_weeping_birch_cluster(cs[1], gs[1], [(44, 78, 18, 11, 16, 0.9, 0), (56, 62, 17, 11, 14, 1.3, 1)], fx, 64, 40, 315, 12, catkins=3, glows=3)
    bb.render_weeping_birch_cluster(cs[2], gs[2], [(92, 80, 18, 11, 16, 0.7, -1), (82, 64, 17, 11, 14, 1.0, 0)], fx, 64, 40, 319, 12, catkins=3, glows=3)
    bb.render_weeping_birch_cluster(cs[3], gs[3], [(66, 41, 22, 12, 14, 2.2, 1), (78, 49, 17, 10, 12, 1.8, 1)], fx, 64, 40, 323, 12, catkins=3, glows=3)
    for c in cs:
        bb.finish_birch_foliage(c, 12)
    t_frames, fg_chaga, traits = bb.build_birch_traits(fw, fh, fx, fy, cut_y, 90, 6, spans, 331, base_col=9, glow_col=5, pad_x=12)
    all_cols = [skirt, tbase, tupper, k1, k2, *cs, *t_frames]
    all_glows = [tg, *gs, fg_chaga]
    bb.write_png(OUT_DIR / "s3.png", fw * len(all_cols), fh, pack_strip(all_cols, fw, fh))
    bb.write_png(OUT_DIR / "s3_glow.png", fw * len(all_glows), fh, pack_strip(all_glows, fw, fh))
    return make_rig_entry(fw, fh, fx, fy, cut_y, 128, 48, 6, 40, "s3", "s3_glow", len(all_cols), len(all_glows),
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": 2, "harvest_amber": -1, "kerf_1": 3, "kerf_2": 4, "overhang": -1},
        {"trunk_glow": 0, "harvest_glow": -1, "cluster_glow_start": 1},
        [{"col": 5, "role": "back_core", "side": 0.0, "anchor": [68, 78], "stiffness": 0.96, "flutter": 0.48, "phase": 0.0, "lobe": [0, 4, 28, 16]},
         {"col": 6, "role": "left_bough", "side": -1.0, "anchor": [56, 80], "stiffness": 0.78, "flutter": 0.58, "phase": 1.1, "lobe": [-16, 2, 22, 14]},
         {"col": 7, "role": "right_bough", "side": 1.0, "anchor": [80, 80], "stiffness": 0.78, "flutter": 0.58, "phase": 2.3, "lobe": [16, 2, 22, 14]},
         {"col": 8, "role": "sun_crest", "side": 0.0, "anchor": [68, 52], "stiffness": 0.74, "flutter": 0.62, "phase": 3.5, "lobe": [-2, -5, 24, 14]}],
        perches=[[-18, 74, 1], [18, 70, 2]], traits=traits)


def build_s4_variant(variant_key: str, seed_base: int):
    fw, fh, fx, fy, cut_y = 188, 208, 94, 188, 175
    tg, hg, harv, k1, k2 = bb.blank(fw, fh), bb.blank(fw, fh), bb.blank(fw, fh), bb.blank(fw, fh), bb.blank(fw, fh)
    if variant_key == "s4":
        th_px, clr_px, ch_px, borken_h, fork_y = 7, 58, 58, 22, 124
        stems = [([(fx + 1, fy + 1), (fx, cut_y), (fx - 3, 146), (fx + 1, 114), (fx - 2, 80)], 7.0, 1.5)]
        boughs = [
            ([(fx - 1, 124), (fx - 16, 108), (fx - 26, 100)], 2.8, 1.1, True),
            ([(fx + 1, 118), (fx + 16, 102), (fx + 26, 96)], 2.6, 1.1, True),
        ]
        c_veils = [
            [(72, 100, 25, 14, 20, -3.0, -2), (116, 102, 25, 14, 20, -3.0, -2), (94, 72, 29, 15, 18, -2.4, -1)],
            [(52, 106, 22, 13, 21, 0.9, 0), (74, 112, 19, 12, 19, 0.8, -1), (64, 80, 22, 13, 17, 1.4, 1)],
            [(136, 106, 22, 13, 21, 0.6, -1), (114, 112, 19, 12, 19, 0.5, -1), (124, 82, 21, 13, 17, 1.1, 0)],
            [(94, 96, 26, 14, 20, 1.8, 0), (76, 72, 21, 13, 17, 1.5, 1), (112, 74, 21, 13, 17, 1.3, 0)],
            [(80, 46, 25, 14, 17, 2.5, 1), (108, 50, 24, 13, 17, 2.1, 1), (94, 36, 23, 13, 16, 2.7, 1)],
        ]
    elif variant_key == "s4_b":
        # Iconic Multi-Stem Birch Clump: 3 slender pale-silver birch stems curving gently into weeping canopy!
        th_px, clr_px, ch_px, borken_h, fork_y = 11, 54, 62, 24, 128
        stems = [
            ([(fx - 2, fy + 1), (fx - 3, cut_y), (fx - 8, 144), (fx - 11, 112), (fx - 8, 82)], 5.4, 1.5),
            ([(fx + 3, fy + 1), (fx + 4, cut_y), (fx + 10, 146), (fx + 15, 116), (fx + 12, 86)], 4.7, 1.5),
            ([(fx - 6, fy + 1), (fx - 8, cut_y + 1), (fx - 17, 152), (fx - 20, 126), (fx - 16, 94)], 3.5, 1.4),
        ]
        boughs = [
            ([(fx - 11, 120), (fx - 26, 106)], 2.2, 1.0, True),
            ([(fx + 14, 122), (fx + 28, 108)], 2.2, 1.0, True),
        ]
        c_veils = [
            [(68, 102, 26, 14, 20, -3.0, -2), (120, 104, 26, 14, 20, -3.0, -2), (94, 72, 29, 15, 18, -2.4, -1)],
            [(48, 108, 23, 13, 21, 0.9, 0), (70, 114, 20, 12, 19, 0.8, -1), (58, 82, 22, 13, 17, 1.4, 1)],
            [(140, 108, 23, 13, 21, 0.6, -1), (118, 114, 20, 12, 19, 0.5, -1), (130, 84, 22, 13, 17, 1.1, 0)],
            [(84, 98, 24, 14, 20, 1.8, 0), (110, 100, 24, 14, 20, 1.6, -1), (94, 70, 25, 14, 17, 1.5, 1)],
            [(76, 46, 25, 14, 17, 2.5, 1), (114, 52, 24, 13, 17, 2.1, 1), (94, 36, 23, 13, 16, 2.7, 1)],
        ]
    else:
        # s4_c: Wind-Arched Glade Birch sweeping gracefully rightward
        th_px, clr_px, ch_px, borken_h, fork_y = 7, 56, 60, 21, 126
        stems = [([(fx - 2, fy + 1), (fx, cut_y), (fx + 8, 146), (fx + 14, 116), (fx + 11, 82)], 6.8, 1.5)]
        boughs = [
            ([(fx + 10, 126), (fx - 4, 110), (fx - 14, 102)], 2.5, 1.0, True),
            ([(fx + 13, 120), (fx + 28, 106), (fx + 38, 100)], 2.6, 1.1, True),
        ]
        c_veils = [
            [(78, 100, 25, 14, 20, -3.0, -2), (124, 104, 26, 14, 21, -3.0, -2), (102, 72, 29, 15, 18, -2.4, -1)],
            [(56, 102, 22, 13, 20, 0.9, 0), (78, 108, 19, 12, 19, 0.8, -1), (68, 78, 22, 13, 17, 1.5, 1)],
            [(142, 108, 23, 13, 23, 0.7, -1), (120, 114, 20, 12, 21, 0.6, -1), (132, 86, 22, 13, 19, 1.1, 0)],
            [(104, 98, 26, 14, 20, 1.8, 0), (86, 72, 21, 13, 17, 1.5, 1), (120, 76, 21, 13, 17, 1.3, 0)],
            [(88, 48, 25, 14, 17, 2.5, 1), (116, 52, 24, 13, 17, 2.2, 1), (102, 38, 23, 13, 16, 2.7, 1)],
        ]

    skirt, tbase, tupper, spans = bb.build_birch_skeleton(fw, fh, fx, fy, cut_y, fork_y + 10, th_px, stems, boughs, borken_h, seed_base, n_roots=4, glow_root=tg, pad_x=12)
    bb.draw_birch_sap_only(harv, hg, spans, 152)
    bb.draw_birch_kerf(k1, fx, cut_y, th_px, deep=False)
    bb.draw_birch_kerf(k2, fx, cut_y, th_px, deep=True)

    cs, gs = [bb.blank(fw, fh) for _ in range(5)], [bb.blank(fw, fh) for _ in range(5)]
    for ci in range(5):
        ck_n = 4 if ci in (1, 2) else (3 if ci == 3 else 2)
        bb.render_weeping_birch_cluster(cs[ci], gs[ci], c_veils[ci], fx, 78, ch_px, seed_base + 21 + ci * 7, 12, catkins=ck_n, glows=3)
        bb.finish_birch_foliage(cs[ci], 12)

    t_frames, fg_chaga, traits = bb.build_birch_traits(fw, fh, fx, fy, cut_y, fork_y, th_px, spans, seed_base + 71, base_col=11, glow_col=7, pad_x=12)
    all_cols = [skirt, tbase, tupper, harv, k1, k2, *cs, *t_frames]
    all_glows = [tg, hg, *gs, fg_chaga]
    bb.write_png(OUT_DIR / f"{variant_key}.png", fw * len(all_cols), fh, pack_strip(all_cols, fw, fh))
    bb.write_png(OUT_DIR / f"{variant_key}_glow.png", fw * len(all_glows), fh, pack_strip(all_glows, fw, fh))
    return make_rig_entry(fw, fh, fx, fy, cut_y, 170, clr_px, th_px, ch_px, variant_key, f"{variant_key}_glow", len(all_cols), len(all_glows),
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": 2, "harvest_amber": 3, "kerf_1": 4, "kerf_2": 5, "overhang": -1},
        {"trunk_glow": 0, "harvest_glow": 1, "cluster_glow_start": 2},
        [{"col": 6, "role": "back_core", "side": 0.0, "anchor": [94, 98], "stiffness": 1.00, "flutter": 0.46, "phase": 0.0, "lobe": [0, 6, 42, 24]},
         {"col": 7, "role": "left_bough", "side": -1.0, "anchor": [68, 102], "stiffness": 0.76, "flutter": 0.58, "phase": 1.1, "lobe": [-26, 4, 32, 19]},
         {"col": 8, "role": "right_bough", "side": 1.0, "anchor": [120, 102], "stiffness": 0.76, "flutter": 0.58, "phase": 2.2, "lobe": [26, 4, 32, 19]},
         {"col": 9, "role": "mid_heart", "side": 0.0, "anchor": [94, 90], "stiffness": 0.86, "flutter": 0.52, "phase": 3.3, "lobe": [0, 2, 34, 20]},
         {"col": 10, "role": "sun_crest", "side": 0.0, "anchor": [94, 58], "stiffness": 0.72, "flutter": 0.62, "phase": 4.4, "lobe": [-2, -6, 36, 20]}],
        perches=[[-28, 96, 1], [28, 92, 2], [-4, 148, 4]], traits=traits)


def build_s5():
    fw, fh, fx, fy, cut_y = 240, 244, 120, 220, 205
    tg, hg, harv, k1, k2, over = bb.blank(fw, fh), bb.blank(fw, fh), bb.blank(fw, fh), bb.blank(fw, fh), bb.blank(fw, fh), bb.blank(fw, fh)
    # Ancient Silver-Crowned Grove Mother: tall 34 px diamond-fissured Borkenfuß + twin monumental chalk-white trunks!
    fork_y = 148
    stems = [
        ([(fx - 2, fy + 1), (fx - 3, cut_y), (fx - 7, 170), (fx - 10, 136), (fx - 7, 94)], 8.4, 1.6),
        ([(fx + 4, fy + 1), (fx + 5, cut_y), (fx + 11, 172), (fx + 15, 140), (fx + 11, 98)], 6.6, 1.5),
    ]
    boughs = [
        ([(fx - 9, 148), (fx - 28, 130), (fx - 40, 122)], 3.4, 1.2, True),
        ([(fx + 13, 146), (fx + 30, 128), (fx + 42, 120)], 3.2, 1.2, True),
    ]
    skirt, tbase, tupper, spans = bb.build_birch_skeleton(fw, fh, fx, fy, cut_y, 160, 12, stems, boughs, 34, 501, n_roots=5, sorrel=(24, 4), glow_root=tg, pad_x=12)
    bb.draw_birch_sap_only(harv, hg, spans, 178)
    bb.draw_birch_kerf(k1, fx, cut_y, 12, deep=False)
    bb.draw_birch_kerf(k2, fx, cut_y, 12, deep=True)

    cs, gs = [bb.blank(fw, fh) for _ in range(6)], [bb.blank(fw, fh) for _ in range(6)]
    bb.render_weeping_birch_cluster(cs[0], gs[0], [(84, 118, 32, 17, 23, -3.2, -2), (156, 120, 32, 17, 23, -3.2, -2), (120, 126, 30, 16, 22, -3.6, -2), (120, 82, 38, 19, 20, -2.6, -1)], fx, 94, 80, 521, 12, catkins=3, glows=2)
    bb.render_weeping_birch_cluster(cs[1], gs[1], [(56, 128, 27, 15, 25, 0.9, 0), (86, 134, 24, 14, 23, 0.8, -1), (68, 100, 27, 15, 21, 1.5, 1)], fx, 94, 80, 527, 12, catkins=5, glows=3)
    bb.render_weeping_birch_cluster(cs[2], gs[2], [(184, 130, 27, 15, 25, 0.6, -1), (154, 134, 24, 14, 23, 0.5, -1), (172, 102, 27, 15, 21, 1.1, 0)], fx, 94, 80, 533, 12, catkins=5, glows=3)
    bb.render_weeping_birch_cluster(cs[3], gs[3], [(84, 72, 28, 15, 20, 1.9, 1), (62, 90, 23, 14, 19, 1.5, 1)], fx, 94, 80, 539, 12, catkins=3, glows=2)
    # Lush central mid_heart + sun_crest bolsters completely close the upper-center donut gap & drape softly over twin stems!
    bb.render_weeping_birch_cluster(cs[4], gs[4], [(120, 118, 34, 16, 24, 1.8, -1), (120, 86, 32, 16, 21, 1.9, 0), (94, 94, 25, 14, 20, 1.5, 1), (146, 96, 25, 14, 20, 1.3, 0)], fx, 94, 80, 543, 12, catkins=4, glows=3)
    bb.render_weeping_birch_cluster(cs[5], gs[5], [(104, 48, 29, 16, 19, 2.7, 1), (138, 52, 28, 15, 19, 2.3, 1), (122, 66, 30, 16, 20, 2.2, 1), (160, 76, 25, 14, 18, 1.8, 0)], fx, 94, 80, 549, 12, catkins=3, glows=3)
    for c in cs:
        bb.finish_birch_foliage(c, 12)
    bb.render_weeping_birch_cluster(over, None, [(68, 62, 20, 11, 15, 2.4, 1), (172, 64, 20, 11, 15, 2.0, 0)], fx, 94, 80, 555, 12, catkins=2, glows=0)
    bb.finish_birch_foliage(over, 12)

    t_frames, fg_chaga, traits = bb.build_birch_traits(fw, fh, fx, fy, cut_y, fork_y, 12, spans, 571, base_col=13, glow_col=8, hollow_at=(fx - 4, fy - 68), pad_x=12)
    all_cols = [skirt, tbase, tupper, harv, k1, k2, *cs, over, *t_frames]
    all_glows = [tg, hg, *gs, fg_chaga]
    bb.write_png(OUT_DIR / "s5.png", fw * len(all_cols), fh, pack_strip(all_cols, fw, fh))
    bb.write_png(OUT_DIR / "s5_glow.png", fw * len(all_glows), fh, pack_strip(all_glows, fw, fh))
    return make_rig_entry(fw, fh, fx, fy, cut_y, 202, 62, 12, 80, "s5", "s5_glow", len(all_cols), len(all_glows),
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": 2, "harvest_amber": 3, "kerf_1": 4, "kerf_2": 5, "overhang": 12},
        {"trunk_glow": 0, "harvest_glow": 1, "cluster_glow_start": 2},
        [{"col": 6, "role": "back_core", "side": 0.0, "anchor": [120, 118], "stiffness": 1.04, "flutter": 0.44, "phase": 0.0, "lobe": [0, 8, 54, 30]},
         {"col": 7, "role": "left_bough", "side": -1.0, "anchor": [86, 124], "stiffness": 0.74, "flutter": 0.58, "phase": 1.0, "lobe": [-38, 6, 38, 22]},
         {"col": 8, "role": "right_bough", "side": 1.0, "anchor": [154, 124], "stiffness": 0.74, "flutter": 0.58, "phase": 2.1, "lobe": [38, 6, 38, 22]},
         {"col": 9, "role": "left_upper", "side": -0.7, "anchor": [94, 86], "stiffness": 0.78, "flutter": 0.56, "phase": 3.2, "lobe": [-24, -4, 32, 19]},
         {"col": 10, "role": "mid_heart", "side": 0.0, "anchor": [120, 110], "stiffness": 0.88, "flutter": 0.50, "phase": 4.3, "lobe": [0, 4, 42, 24]},
         {"col": 11, "role": "sun_crest", "side": 0.2, "anchor": [126, 70], "stiffness": 0.70, "flutter": 0.62, "phase": 5.4, "lobe": [6, -8, 42, 24]}],
        perches=[[-42, 102, 1], [42, 98, 2], [-14, 162, 4], [20, 156, 5]],
        hollow=[-4, -68], rest=[24, 4], traits=traits)


def build_coppice():
    fw, fh, fx, fy, cut_y = 96, 92, 48, 76, 63
    stems = [([(fx, fy + 1), (fx, cut_y)], 10.0, 9.2)]
    skirt, tbase, _, _ = bb.build_birch_skeleton(fw, fh, fx, fy, cut_y, cut_y - 4, 10, stems, [], 18, 601, n_roots=4, pad_x=6)
    c0 = bb.blank(fw, fh)
    for sx, tx, ty, sd in ((fx - 9, fx - 18, 42, 611), (fx - 5, fx - 9, 36, 613), (fx, fx + 1, 34, 615), (fx + 5, fx + 10, 38, 617), (fx + 9, fx + 18, 44, 619)):
        bb.draw_birch_limb(c0, [(sx, cut_y - 1), ((sx + tx) // 2, (cut_y + ty) // 2), (tx, ty)], 1.4, 0.8, fy, 0, -999, sd, pad_x=12, juvenile=True)
    bb.render_weeping_birch_cluster(c0, None, [(fx - 15, 42, 9, 6, 9, 0.8, 1), (fx, 36, 12, 7, 10, 1.4, 1), (fx + 15, 43, 9, 6, 9, 0.8, 0)], fx, 40, 24, 621, pad_x=12, catkins=1, glows=0)
    bb.finish_birch_foliage(c0, 12)
    bb.write_png(OUT_DIR / "coppice.png", fw * 3, fh, pack_strip([skirt, tbase, c0], fw, fh))
    return make_rig_entry(fw, fh, fx, fy, cut_y, 34, 4, 10, 24, "coppice", "", 3, 0,
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": -1, "harvest_amber": -1, "kerf_1": -1, "kerf_2": -1, "overhang": -1},
        {"trunk_glow": -1, "harvest_glow": -1, "cluster_glow_start": -1},
        [{"col": 2, "role": "coppice_shoots", "side": 0.0, "anchor": [48, 63], "stiffness": 0.92, "flutter": 0.64, "phase": 0.0, "lobe": [0, 0, 24, 14]}])


def build_s6_log():
    fw, fh, fx, fy, cut_y = 152, 64, 76, 48, 42
    skirt, tbase, c0, tg = bb.blank(fw, fh), bb.blank(fw, fh), bb.blank(fw, fh), bb.blank(fw, fh)
    for y in range(fy - 7, fy + 11):
        for x in range(18, fw - 16):
            d = math.hypot((x - fx - 3) / 52.0, (y - fy - 2) / 8.5) + (bb.vnoise(x * 0.2, y * 0.25, 701) - 0.5) * 0.2
            if d < 1.0:
                bb.put_contact_shadow(skirt, x, y, int(112 * ((1.0 - d) ** 1.4)))
    # Fallen chalk-white peeling paper-bark birch trunk with dark horizontal lenticels, Birkenporling & glowing Chaga!
    sp = bb.sample_spline([(28, 44), (62, 41), (96, 42), (124, 45)], 80)
    for cx_f, cy_f in sp:
        cx_i, cy_i = int(round(cx_f)), int(round(cy_f))
        rad = 8.4 - (cx_f - 28.0) * 0.018
        ir = int(math.ceil(rad))
        for dy in range(-ir, ir + 1):
            if abs(dy) <= rad:
                u = dy / rad
                lit = -0.65 * u + 0.45 * math.sqrt(max(0.05, 1.0 - u * u))
                if bb.vnoise(cx_f * 0.22, (cy_i + dy) * 0.22, 705) > 0.68 and u < -0.15:
                    col = bb.MOSS[bb.clampi(int((lit + 0.3) * 3.8), 1, 4)]
                elif bb.hsh(cx_i, 0, 717) > 0.74 and abs(u - (bb.hsh(cx_i, 1, 719) - 0.45)) < 0.22:
                    col = bb.BORKEN[1]
                else:
                    col = bb.WHITE_BARK[bb.clampi(int((lit + 0.42) * 5.0), 0, 5)]
                bb.put(tbase, cx_i, cy_i + dy, col)
    bb.selout_bark(tbase, pad_x=10, stop_y=fy + 2)
    bb.draw_birch_cut_rings(tbase, 124, 45, 5, 7)
    for dy in range(-5, 6):
        for dx in range(-4, 5):
            if math.hypot(dx / 4.0, dy / 5.5) <= 1.0:
                bb.put(tbase, 28 + dx, 44 + dy, bb.OUT_BARK if abs(dx) < 2 and abs(dy) < 3 else bb.BORKEN[1])
    # Creamy Birkenporling shelves & glowing Funken-Chaga fissure
    for bx, by in ((58, 42), (102, 43)):
        for rx_o in range(-3, 4):
            bb.put(tbase, bx + rx_o, by - 1, bb.BIRCH_WOOD[3])
            bb.put(tbase, bx + rx_o, by, bb.BIRCH_WOOD[2])
            if abs(rx_o) < 3:
                bb.put(tbase, bx + rx_o, by + 1, bb.BIRCH_WOOD[0])
    for ox, oy, c_d, c_g in ((0, 0, bb.BORKEN[0], None), (1, 0, bb.CHAGA_FIRE[2], bb.CHAGA_FIRE[2]), (2, 0, bb.CHAGA_FIRE[3], bb.CHAGA_FIRE[3]), (1, 1, bb.GLOW[2], bb.GLOW[2]), (-1, 1, bb.BORKEN[1], None)):
        bb.put(tbase, 80 + ox, 43 + oy, c_d)
        if c_g is not None:
            bb.put(tg, 80 + ox, 43 + oy, c_g)
    for gx in (44, 68, 94, 114):
        bb.put(tg, gx, 45, bb.GLOW[2])
        bb.put(skirt, gx, 49, bb.CATKIN[2])
    for sx, sy in ((48, 30), (76, 28), (106, 31)):
        for y in range(sy, sy + 6):
            bb.put(c0, sx, y, bb.COPPER[2] if y > sy + 3 else bb.LEAF[4])
        bb.draw_diamond_leaf(c0, sx - 2, sy, None, bb.LEAF[3], bb.LEAF[5], bb.LEAF[6], 12)
        bb.draw_diamond_leaf(c0, sx + 2, sy + 1, None, bb.LEAF[2], bb.LEAF[4], None, 12)
    bb.finish_birch_foliage(c0, 12)
    bb.write_png(OUT_DIR / "s6_log.png", fw * 3, fh, pack_strip([skirt, tbase, c0], fw, fh))
    bb.write_png(OUT_DIR / "s6_log_glow.png", fw, fh, tg)
    return make_rig_entry(fw, fh, fx, fy, cut_y, 30, 4, 12, 48, "s6_log", "s6_log_glow", 3, 1,
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": -1, "harvest_amber": -1, "kerf_1": -1, "kerf_2": -1, "overhang": -1},
        {"trunk_glow": 0, "harvest_glow": -1, "cluster_glow_start": -1},
        [{"col": 2, "role": "nurse_sprouts", "side": 0.0, "anchor": [76, 35], "stiffness": 1.05, "flutter": 0.64, "phase": 0.0, "lobe": [0, 0, 44, 12]}])


def composite_onto(dst, ox: int, oy: int, frames: list, glows: list, r: dict, night: bool = False, trait_cols=None, show_sap: bool = False, glow_trait_cols=None) -> None:
    lay, gl = r["layers"], r["glow_layers"]
    sap_c = lay["harvest_amber"] if show_sap else -1
    order = [lay["root_skirt"], lay["trunk_base"], lay["trunk_upper"]] + (trait_cols or []) + [sap_c] + [c["col"] for c in r["clusters"]] + [lay["overhang"]]
    for ci in order:
        if 0 <= ci < len(frames):
            fr = frames[ci]
            if night:
                tinted = [[(max(12, int(p[0] * 0.36)), max(16, int(p[1] * 0.42)), max(28, int(p[2] * 0.56)), p[3]) if p[3] > 0 else bb.CLEAR for p in row] for row in fr]
                bb.blit(dst, tinted, ox, oy)
            else:
                bb.blit(dst, fr, ox, oy)
    if night and glows:
        g_order = [gl["trunk_glow"]] + ([gl["harvest_glow"]] if show_sap else []) + (glow_trait_cols or [])
        if gl["cluster_glow_start"] >= 0:
            g_order.extend(range(gl["cluster_glow_start"], gl["cluster_glow_start"] + len(r["clusters"])))
        for gi in g_order:
            if 0 <= gi < len(glows):
                bb.blit(dst, glows[gi], ox, oy)


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
    frames = [bb.blank(fw, fh) for _ in range(ncols)]
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
    icon_paths = bb.build_birch_icons()
    for ip in icon_paths:
        read_frames_from_disk(ip, 16, 16, 1)
    rig = {
        "s0": build_s0(), "s1": build_s1(), "s2": build_s2(), "s3": build_s3(),
        "s4": build_s4_variant("s4", 401), "s4_b": build_s4_variant("s4_b", 451), "s4_c": build_s4_variant("s4_c", 481),
        "s5": build_s5(), "coppice": build_coppice(), "s6_log": build_s6_log(),
    }
    RIG_JSON.write_text(json.dumps(rig, indent=1) + "\n", encoding="utf-8")

    sw, sh = 1220, 540
    qa = bb.blank(sw, sh)
    meadow_tones = [bb.hexc("264a3b"), bb.hexc("2e5944"), bb.hexc("386a4d"), bb.hexc("447a55")]
    night_tones = [bb.hexc("111828"), bb.hexc("141d2e"), bb.hexc("182334")]
    for y in range(sh):
        for x in range(sw):
            v = bb.vnoise(x * 0.08, y * 0.12, 999)
            qa[y][x] = meadow_tones[bb.clampi(int(v * 4.0), 0, 3)] if y < 280 else night_tones[bb.clampi(int(v * 3.0), 0, 2)]

    lineup = [
        ("s0", [], False, []),
        ("s1", [], False, []),
        ("s2", [], False, []),
        ("s3", [rig["s3"]["traits"]["ivy"][0], rig["s3"]["traits"]["sprig"][1]], False, []),
        ("s4", [rig["s4"]["traits"]["ivy"][0], rig["s4"]["traits"]["sprig"][0]], True, []),
        ("s4_b", [rig["s4_b"]["traits"]["moss"][0], rig["s4_b"]["traits"]["fungi"][0], rig["s4_b"]["traits"]["hollow"][2]], False, []),
        ("s4_c", [rig["s4_c"]["traits"]["ivy"][1], rig["s4_c"]["traits"]["hollow"][0], rig["s4_c"]["traits"]["fungi"][1]], False, [rig["s4_c"]["traits"]["fungi_glow"][1]]),
        ("s5", [rig["s5"]["traits"]["moss"][0], rig["s5"]["traits"]["ivy"][0], rig["s5"]["traits"]["hollow"][0], rig["s5"]["traits"]["fungi"][1]], True, [rig["s5"]["traits"]["fungi_glow"][1]]),
    ]
    x_cur, x_pos = 8, {}
    for key, tcols, sap, gtcols in lineup:
        r = rig[key]
        x_pos[key] = x_cur
        frs = read_frames_from_disk(OUT_DIR / f"{key}.png", r["frame_w"], r["frame_h"], r["num_cols"])
        gfs = read_frames_from_disk(OUT_DIR / f"{key}_glow.png", r["frame_w"], r["frame_h"], r["glow_cols"]) if r["glow_cols"] > 0 else []
        composite_onto(qa, x_cur, 270 - r["feet_y"], frs, gfs, r, night=False, trait_cols=tcols, show_sap=sap, glow_trait_cols=gtcols)
        if key in ("s3", "s4", "s4_b", "s4_c", "s5"):
            composite_onto(qa, x_cur, 526 - r["feet_y"], frs, gfs, r, night=True, trait_cols=tcols, show_sap=sap, glow_trait_cols=gtcols)
        x_cur += r["frame_w"] + 2

    for key, ox, oy, is_n in (("coppice", 12, 58, False), ("s6_log", 112, 58, False), ("coppice", 12, 315, True), ("s6_log", 12, 445, True)):
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
                            bb.put(qa, 18 + idx * 38 + x * 2 + dx, 14 + y * 2 + dy, ic[y][x])
    bb.write_png(QA_SHEET, sw, sh, qa)
    read_frames_from_disk(QA_SHEET, sw, sh, 1)

    # 3x close-up zoom sheet of s4, s4_b, s4_c, s5 side-by-side!
    zw, zh, pw = 920, 510, 72
    zimg = bb.blank(zw, zh)
    for pi, key in enumerate(("s4", "s4_b", "s4_c", "s5")):
        r = rig[key]
        x0 = x_pos[key] + r["feet_x"] - pw // 2
        ox = 6 + pi * (pw * 3 + 10)
        for y in range(166):
            for x in range(pw):
                c = qa[110 + y][x0 + x]
                for dy in range(3):
                    for dx in range(3):
                        if ox + x * 3 + dx < zw:
                            zimg[6 + y * 3 + dy][ox + x * 3 + dx] = c
    bb.write_png(ZOOM_SHEET, zw, zh, zimg)
    read_frames_from_disk(ZOOM_SHEET, zw, zh, 1)
    print("Generated 2.0 Glimmtal-Hängebirke assets, icons, rig JSON, and 1x/3x QA sheets (0 #000000 verified).")


if __name__ == "__main__":
    main()
