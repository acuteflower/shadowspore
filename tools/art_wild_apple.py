#!/usr/bin/env python3
"""Procedural 2.0 botanical pixel-art generator for Glimmtal-Wildapfel (Malus sylvestris glimmensis):
  assets/items/{apple_wood,wild_apple_fruit,apple_blossom,wild_mistletoe,apple_seed}.png
  assets/props/wild_apple/{s0..s5,s4_b,s4_c,coppice,s6_log}.png + *_glow.png
  data/wild_apple_rig.json
  docs/img/wild_apple_sheet.png + docs/img/wild_apple_zoom_3x.png
Zero #000000 pixels anywhere; stdlib + apple_botany.py only.
"""
import json
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import apple_botany as ab  # noqa: E402

OUT_DIR = ab.ROOT / "props" / "wild_apple"
RIG_JSON = ab.ROOT.parent / "data" / "wild_apple_rig.json"
QA_SHEET = ab.ROOT.parent / "docs" / "img" / "wild_apple_sheet.png"
ZOOM_SHEET = ab.ROOT.parent / "docs" / "img" / "wild_apple_zoom_3x.png"


def pack_strip(frames: list, fw: int, fh: int):
    strip = ab.blank(fw * len(frames), fh)
    for idx, fr in enumerate(frames):
        for y in range(fh):
            strip[y][idx * fw:(idx + 1) * fw] = fr[y][:]
    return strip


def make_rig_entry(fw, fh, fx, fy, cut_y, h_px, clr_px, th_px, ch_px, s_name, g_name, n_cols, g_cols, layers, g_layers, clusters, perches=None, hollow=None, rest=None, pheno=None, traits=None):
    d = {
        "frame_w": fw, "frame_h": fh, "feet_x": fx, "feet_y": fy, "cut_y": cut_y,
        "height_px": h_px, "clear_px": clr_px, "trunk_half_px": th_px, "crown_half_px": ch_px,
        "sheet": f"res://assets/props/wild_apple/{s_name}.png",
        "glow_sheet": f"res://assets/props/wild_apple/{g_name}.png" if g_name else "",
        "num_cols": n_cols, "glow_cols": g_cols,
        "layers": layers, "glow_layers": g_layers, "clusters": clusters,
        "perches": perches or [], "hollow": hollow or [], "rest_seat": rest or [],
    }
    if pheno is not None:
        d["phenology"] = pheno
    if traits is not None:
        d["traits"] = traits
    return d


def build_s0():
    fw, fh, fx, fy = 24, 24, 12, 20
    skirt, c0 = ab.blank(fw, fh), ab.blank(fw, fh)
    for dy in range(-2, 3):
        for dx in range(-5, 6):
            d = math.hypot(dx / 5.5, dy / 2.2)
            if d < 1.0:
                ab.put_contact_shadow(skirt, fx + dx + 1, fy + dy, int(92 * (1.0 - d)))
    for dx in (-2, -1, 0, 1, 2):
        ab.put(skirt, fx + dx, fy, ab.MOSS[2 if dx <= 0 else 1])
    # Half crimson/cream apple-core & dark pip beside sprout
    ab.put(skirt, fx + 2, fy - 1, ab.FRUIT[2])
    ab.put(skirt, fx + 1, fy - 1, ab.HEARTWOOD[3])
    ab.put(skirt, fx, fy - 1, ab.BARK[0])
    for y in range(13, 19):
        ab.put(c0, fx, y, ab.THORN_BARK[2] if y > 16 else ab.LEAF[3])
    for dx, dy, col in ((-3, 13, ab.LEAF[5]), (-2, 13, ab.LEAF[4]), (-2, 14, ab.LEAF[3]), (-1, 14, ab.LEAF[3]), (1, 14, ab.LEAF[4]), (2, 14, ab.LEAF[3]), (2, 13, ab.LEAF[4])):
        ab.put(c0, fx + dx, dy, col)
    ab.finish_apple_foliage(c0, pad_x=4)
    ab.write_png(OUT_DIR / "s0.png", fw * 2, fh, pack_strip([skirt, c0], fw, fh))
    return make_rig_entry(fw, fh, fx, fy, 18, 9, 2, 2, 5, "s0", "", 2, 0,
        {"root_skirt": 0, "trunk_base": -1, "trunk_upper": -1, "harvest_amber": -1, "kerf_1": -1, "kerf_2": -1, "overhang": -1},
        {"trunk_glow": -1, "harvest_glow": -1, "cluster_glow_start": -1},
        [{"col": 1, "role": "sprout", "side": 0.0, "anchor": [12, 19], "stiffness": 1.35, "flutter": 0.52, "phase": 0.0, "lobe": [0, 0, 5, 4]}])


def build_s1():
    fw, fh, fx, fy, cut_y = 48, 52, 24, 44, 40
    # Thorny Wild-Apple Whip (Sprossdornen)
    stems = [([(fx, fy + 1), (fx, cut_y), (fx - 2, 30), (fx + 1, 21)], 2.6, 1.2)]
    boughs = [([(fx - 1, 31), (fx - 5, 26)], 1.4, 0.9), ([(fx, 28), (fx + 5, 23)], 1.4, 0.9)]
    skirt, tbase, tupper, _ = ab.build_apple_skeleton(fw, fh, fx, fy, cut_y, 26, 3, stems, boughs, 101, n_roots=2, pad_x=12, thorny=True)
    ab.put(tupper, fx + 2, 34, ab.THORN_BARK[1])
    ab.put(tupper, fx - 3, 36, ab.THORN_BARK[1])
    c0, _, _, _, _ = ab.render_apple_cluster_and_phenology(fw, fh, [(21, 27, 8, 6, -1.0, 0)], fx, 24, 11, 111, pad_x=12, make_pheno=False, glows=0)
    c1, _, _, _, _ = ab.render_apple_cluster_and_phenology(fw, fh, [(26, 20, 9, 7, 1.2, 1)], fx, 24, 11, 113, pad_x=12, make_pheno=False, glows=0)
    ab.write_png(OUT_DIR / "s1.png", fw * 5, fh, pack_strip([skirt, tbase, tupper, c0, c1], fw, fh))
    return make_rig_entry(fw, fh, fx, fy, cut_y, 32, 10, 3, 11, "s1", "", 5, 0,
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": 2, "harvest_amber": -1, "kerf_1": -1, "kerf_2": -1, "overhang": -1},
        {"trunk_glow": -1, "harvest_glow": -1, "cluster_glow_start": -1},
        [{"col": 3, "role": "back_core", "side": -0.5, "anchor": [22, 30], "stiffness": 1.15, "flutter": 0.44, "phase": 0.0, "lobe": [-3, 2, 9, 6]},
         {"col": 4, "role": "sun_crest", "side": 0.5, "anchor": [25, 22], "stiffness": 1.05, "flutter": 0.48, "phase": 1.3, "lobe": [2, -2, 10, 6]}])


def build_s2():
    fw, fh, fx, fy, cut_y = 88, 96, 44, 84, 75
    stems = [([(fx, fy + 1), (fx, cut_y), (fx - 2, 60), (fx + 1, 46)], 4.8, 2.0)]
    boughs = [([(fx - 1, 56), (fx - 13, 48)], 2.5, 1.2), ([(fx + 1, 54), (fx + 13, 47)], 2.4, 1.2)]
    skirt, tbase, tupper, _ = ab.build_apple_skeleton(fw, fh, fx, fy, cut_y, 58, 5, stems, boughs, 201, n_roots=3, pad_x=12)
    k1 = ab.blank(fw, fh)
    ab.draw_apple_kerf(k1, fx, cut_y, 5, deep=False)
    bols = [
        [(44, 48, 20, 12, -2.0, -1)],
        [(31, 50, 16, 11, 0.8, 0), (57, 51, 16, 11, 0.5, -1)],
        [(43, 35, 20, 12, 1.8, 1)],
    ]
    cs, bs, bgs, fs = [], [], [], []
    for ci, b_list in enumerate(bols):
        lp, _, bp, bg, fp = ab.render_apple_cluster_and_phenology(fw, fh, b_list, fx, 44, 28, 211 + ci * 7, pad_x=12, make_pheno=True, glows=0)
        cs.append(lp); bs.append(bp); bgs.append(bg); fs.append(fp)
    all_cols = [skirt, tbase, tupper, k1, *cs, *bs, *fs]
    ab.write_png(OUT_DIR / "s2.png", fw * len(all_cols), fh, pack_strip(all_cols, fw, fh))
    ab.write_png(OUT_DIR / "s2_glow.png", fw * len(bgs), fh, pack_strip(bgs, fw, fh))
    pheno = {"blossom_cols": [7, 8, 9], "fruit_cols": [10, 11, 12], "blossom_glow_start": 0}
    return make_rig_entry(fw, fh, fx, fy, cut_y, 64, 22, 5, 28, "s2", "s2_glow", len(all_cols), len(bgs),
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": 2, "harvest_amber": -1, "kerf_1": 3, "kerf_2": -1, "overhang": -1},
        {"trunk_glow": -1, "harvest_glow": -1, "cluster_glow_start": -1},
        [{"col": 4, "role": "back_core", "side": 0.0, "anchor": [44, 52], "stiffness": 1.15, "flutter": 0.38, "phase": 0.0, "lobe": [0, 3, 22, 13]},
         {"col": 5, "role": "left_bough", "side": -0.8, "anchor": [38, 52], "stiffness": 0.96, "flutter": 0.44, "phase": 1.2, "lobe": [-9, 2, 24, 14]},
         {"col": 6, "role": "sun_crest", "side": 0.4, "anchor": [44, 40], "stiffness": 0.92, "flutter": 0.48, "phase": 2.4, "lobe": [-1, -3, 21, 13]}],
        pheno=pheno)


def build_s3():
    fw, fh, fx, fy, cut_y = 128, 132, 64, 118, 107
    tg, k1, k2 = ab.blank(fw, fh), ab.blank(fw, fh), ab.blank(fw, fh)
    stems = [([(fx, fy + 1), (fx, cut_y), (fx - 3, 88), (fx + 1, 66)], 6.8, 2.0)]
    boughs = [
        ([(fx - 2, 82), (fx - 18, 74), (fx - 28, 70)], 3.6, 1.4),
        ([(fx + 1, 78), (fx + 18, 71), (fx + 27, 68)], 3.4, 1.4),
    ]
    skirt, tbase, tupper, smask = ab.build_apple_skeleton(fw, fh, fx, fy, cut_y, 84, 7, stems, boughs, 301, n_roots=4, glow_root=tg, pad_x=12)
    ab.draw_apple_kerf(k1, fx, cut_y, 7, deep=False)
    ab.draw_apple_kerf(k2, fx, cut_y, 7, deep=True)
    bols = [
        [(50, 68, 22, 14, -2.5, -2), (78, 70, 22, 14, -2.5, -2), (64, 52, 25, 14, -2.0, -1)],
        [(36, 72, 20, 14, 0.9, 0), (50, 58, 18, 12, 1.3, 1)],
        [(92, 73, 20, 14, 0.7, -1), (78, 60, 18, 12, 1.0, 0)],
        [(62, 38, 24, 14, 2.2, 1), (76, 44, 19, 12, 1.8, 1)],
    ]
    cs, cgs, bs, bgs, fs = [], [], [], [], []
    for ci, b_list in enumerate(bols):
        lp, lg, bp, bg, fp = ab.render_apple_cluster_and_phenology(fw, fh, b_list, fx, 58, 44, 311 + ci * 7, pad_x=12, make_pheno=True, glows=2)
        cs.append(lp); cgs.append(lg); bs.append(bp); bgs.append(bg); fs.append(fp)
    t_frames, ig_m, fg_n, traits = ab.build_apple_traits(fw, fh, fx, fy, cut_y, 82, 7, smask, 341, base_col=17, mistle_glow_col=9, fungi_glow_col=10, pad_x=12)
    all_cols = [skirt, tbase, tupper, k1, k2, *cs, *bs, *fs, *t_frames]
    all_glows = [tg, *cgs, *bgs, ig_m, fg_n]
    ab.write_png(OUT_DIR / "s3.png", fw * len(all_cols), fh, pack_strip(all_cols, fw, fh))
    ab.write_png(OUT_DIR / "s3_glow.png", fw * len(all_glows), fh, pack_strip(all_glows, fw, fh))
    pheno = {"blossom_cols": [9, 10, 11, 12], "fruit_cols": [13, 14, 15, 16], "blossom_glow_start": 5}
    return make_rig_entry(fw, fh, fx, fy, cut_y, 98, 32, 7, 44, "s3", "s3_glow", len(all_cols), len(all_glows),
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": 2, "harvest_amber": -1, "kerf_1": 3, "kerf_2": 4, "overhang": -1},
        {"trunk_glow": 0, "harvest_glow": -1, "cluster_glow_start": 1},
        [{"col": 5, "role": "back_core", "side": 0.0, "anchor": [64, 68], "stiffness": 1.15, "flutter": 0.36, "phase": 0.0, "lobe": [0, 4, 30, 17]},
         {"col": 6, "role": "left_bough", "side": -1.0, "anchor": [50, 70], "stiffness": 0.94, "flutter": 0.42, "phase": 1.1, "lobe": [-18, 2, 24, 14]},
         {"col": 7, "role": "right_bough", "side": 1.0, "anchor": [78, 70], "stiffness": 0.94, "flutter": 0.42, "phase": 2.3, "lobe": [18, 2, 24, 14]},
         {"col": 8, "role": "sun_crest", "side": 0.0, "anchor": [64, 46], "stiffness": 0.88, "flutter": 0.46, "phase": 3.5, "lobe": [-2, -5, 26, 15]}],
        perches=[[-22, 58, 1], [22, 56, 2]], pheno=pheno, traits=traits)


def build_s4_variant(variant_key: str, seed_base: int):
    fw, fh, fx, fy, cut_y = 184, 168, 92, 150, 138
    tg, k1, k2 = ab.blank(fw, fh), ab.blank(fw, fh), ab.blank(fw, fh)
    if variant_key == "s4":
        # Twisted Solitary Meadow Apple: muscular S-twisted Drehwuchs bole + broad vaulted umbrella crown
        th_px, clr_px, ch_px, fork_y = 9, 38, 68, 102
        stems = [([(fx + 1, fy + 1), (fx, cut_y), (fx - 4, 120), (fx + 2, 98), (fx - 2, 74)], 8.8, 1.8)]
        boughs = [
            ([(fx - 2, 108), (fx - 22, 98), (fx - 38, 92)], 4.4, 1.4),
            ([(fx + 2, 104), (fx + 22, 95), (fx + 38, 90)], 4.2, 1.4),
        ]
        bols = [
            [(64, 86, 28, 16, -3.0, -2), (120, 88, 28, 16, -3.0, -2), (92, 92, 26, 15, -3.4, -2), (92, 62, 34, 16, -2.5, -1)],
            [(42, 94, 24, 15, 0.9, 0), (66, 98, 21, 14, 0.8, -1), (56, 72, 24, 14, 1.5, 1)],
            [(142, 94, 24, 15, 0.6, -1), (118, 98, 21, 14, 0.5, -1), (128, 74, 23, 14, 1.1, 0)],
            [(92, 82, 28, 15, 1.8, 0), (72, 64, 23, 14, 1.5, 1), (112, 66, 23, 14, 1.3, 0)],
            [(76, 42, 27, 15, 2.5, 1), (110, 46, 26, 14, 2.1, 1), (92, 34, 25, 14, 2.7, 1)],
        ]
    elif variant_key == "s4_b":
        # Low-Forked Twin Orchard Veteran (Streuobst-Zwiesel): splits right above cut_y into 2 crooked orchard limbs!
        th_px, clr_px, ch_px, fork_y = 11, 34, 70, 110
        stems = [
            ([(fx - 1, fy + 1), (fx - 2, cut_y), (fx - 12, 120), (fx - 20, 98), (fx - 16, 78)], 7.2, 1.8),
            ([(fx + 2, fy + 1), (fx + 3, cut_y), (fx + 14, 122), (fx + 22, 100), (fx + 18, 80)], 6.6, 1.8),
        ]
        boughs = [
            ([(fx - 16, 108), (fx - 36, 96)], 3.4, 1.3),
            ([(fx + 18, 110), (fx + 38, 98)], 3.2, 1.3),
        ]
        bols = [
            [(62, 88, 28, 16, -3.0, -2), (122, 90, 28, 16, -3.0, -2), (92, 90, 26, 15, -3.2, -2), (92, 62, 34, 16, -2.5, -1)],
            [(40, 96, 24, 15, 0.9, 0), (66, 100, 22, 14, 0.8, 0), (54, 74, 24, 14, 1.5, 1)],
            [(144, 98, 24, 15, 0.6, -1), (118, 102, 22, 14, 0.5, -1), (130, 76, 23, 14, 1.1, 0)],
            [(80, 82, 25, 15, 1.8, 0), (106, 84, 25, 15, 1.6, 0), (92, 64, 26, 14, 1.5, 1)],
            [(72, 42, 27, 15, 2.6, 1), (114, 48, 26, 14, 2.1, 1), (92, 35, 24, 14, 2.5, 1)],
        ]
    else:
        # s4_c: Leaning Stone-Wall / Lane Apple sweeping gracefully rightward over a path!
        th_px, clr_px, ch_px, fork_y = 9, 36, 70, 104
        stems = [([(fx - 3, fy + 1), (fx, cut_y), (fx + 10, 120), (fx + 18, 98), (fx + 14, 76)], 8.6, 1.8)]
        boughs = [
            ([(fx + 12, 110), (fx - 8, 98), (fx - 22, 92)], 3.6, 1.3),
            ([(fx + 16, 106), (fx + 36, 98), (fx + 48, 96)], 4.0, 1.4),
        ]
        bols = [
            [(72, 86, 27, 16, -3.0, -2), (126, 92, 28, 16, -3.0, -2), (102, 94, 26, 15, -3.4, -2), (100, 62, 34, 16, -2.5, -1)],
            [(48, 90, 23, 15, 0.9, 0), (72, 96, 21, 14, 0.8, 0), (62, 70, 24, 14, 1.5, 1)],
            [(144, 100, 24, 15, 0.7, -1), (122, 104, 22, 14, 0.6, -1), (134, 78, 24, 14, 1.1, 0)],
            [(102, 84, 27, 15, 1.8, 0), (82, 66, 23, 14, 1.5, 1), (120, 70, 23, 14, 1.3, 0)],
            [(84, 44, 27, 15, 2.5, 1), (116, 48, 26, 14, 2.2, 1), (100, 36, 25, 14, 2.7, 1)],
        ]

    skirt, tbase, tupper, smask = ab.build_apple_skeleton(fw, fh, fx, fy, cut_y, fork_y + 10, th_px, stems, boughs, seed_base, n_roots=4, glow_root=tg, pad_x=12)
    ab.draw_apple_kerf(k1, fx, cut_y, th_px, deep=False)
    ab.draw_apple_kerf(k2, fx, cut_y, th_px, deep=True)

    cs, cgs, bs, bgs, fs = [], [], [], [], []
    for ci in range(5):
        lp, lg, bp, bg, fp = ab.render_apple_cluster_and_phenology(fw, fh, bols[ci], fx, 68, ch_px, seed_base + 21 + ci * 7, pad_x=12, make_pheno=True, glows=2)
        cs.append(lp); cgs.append(lg); bs.append(bp); bgs.append(bg); fs.append(fp)

    t_frames, ig_m, fg_n, traits = ab.build_apple_traits(fw, fh, fx, fy, cut_y, fork_y, th_px, smask, seed_base + 71, base_col=20, mistle_glow_col=11, fungi_glow_col=12, pad_x=12)
    all_cols = [skirt, tbase, tupper, k1, k2, *cs, *bs, *fs, *t_frames]
    all_glows = [tg, *cgs, *bgs, ig_m, fg_n]
    ab.write_png(OUT_DIR / f"{variant_key}.png", fw * len(all_cols), fh, pack_strip(all_cols, fw, fh))
    ab.write_png(OUT_DIR / f"{variant_key}_glow.png", fw * len(all_glows), fh, pack_strip(all_glows, fw, fh))
    pheno = {"blossom_cols": [10, 11, 12, 13, 14], "fruit_cols": [15, 16, 17, 18, 19], "blossom_glow_start": 6}
    return make_rig_entry(fw, fh, fx, fy, cut_y, 128, clr_px, th_px, ch_px, variant_key, f"{variant_key}_glow", len(all_cols), len(all_glows),
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": 2, "harvest_amber": -1, "kerf_1": 3, "kerf_2": 4, "overhang": -1},
        {"trunk_glow": 0, "harvest_glow": -1, "cluster_glow_start": 1},
        [{"col": 5, "role": "back_core", "side": 0.0, "anchor": [92, 86], "stiffness": 1.18, "flutter": 0.34, "phase": 0.0, "lobe": [0, 6, 46, 26]},
         {"col": 6, "role": "left_bough", "side": -1.0, "anchor": [64, 90], "stiffness": 0.90, "flutter": 0.42, "phase": 1.1, "lobe": [-30, 4, 36, 21]},
         {"col": 7, "role": "right_bough", "side": 1.0, "anchor": [120, 90], "stiffness": 0.90, "flutter": 0.42, "phase": 2.2, "lobe": [30, 4, 36, 21]},
         {"col": 8, "role": "mid_heart", "side": 0.0, "anchor": [92, 80], "stiffness": 1.02, "flutter": 0.38, "phase": 3.3, "lobe": [0, 2, 38, 22]},
         {"col": 9, "role": "sun_crest", "side": 0.0, "anchor": [92, 52], "stiffness": 0.86, "flutter": 0.46, "phase": 4.4, "lobe": [-3, -6, 40, 22]}],
        perches=[[-32, 74, 1], [32, 72, 2], [-4, 114, 4]], pheno=pheno, traits=traits)


def build_s5():
    fw, fh, fx, fy, cut_y = 228, 196, 114, 174, 160
    tg, k1, k2 = ab.blank(fw, fh), ab.blank(fw, fh), ab.blank(fw, fh)
    fork_y = 116
    stems = [
        ([(fx - 2, fy + 1), (fx - 2, cut_y), (fx - 8, 138), (fx - 10, 112), (fx - 6, 86)], 11.8, 2.2),
        ([(fx + 4, fy + 1), (fx + 4, cut_y), (fx + 10, 140), (fx + 13, 114), (fx + 8, 88)], 9.6, 2.0),
    ]
    boughs = [
        ([(fx - 9, 124), (fx - 34, 112), (fx - 52, 106)], 5.2, 1.5),
        ([(fx + 11, 122), (fx + 36, 110), (fx + 54, 104)], 5.0, 1.5),
    ]
    skirt, tbase, tupper, smask = ab.build_apple_skeleton(fw, fh, fx, fy, cut_y, 134, 14, stems, boughs, 501, n_roots=5, sorrel=(26, 4), glow_root=tg, pad_x=12, split_hollow=True, petals=True)
    ab.draw_apple_kerf(k1, fx, cut_y, 14, deep=False)
    ab.draw_apple_kerf(k2, fx, cut_y, 14, deep=True)

    bols = [
        [(80, 98, 34, 18, -3.2, -2), (148, 100, 34, 18, -3.2, -2), (114, 106, 32, 17, -3.6, -2), (114, 72, 40, 19, -2.6, -1)],
        [(50, 108, 28, 16, 0.9, 0), (80, 112, 24, 15, 0.8, -1), (64, 84, 28, 16, 1.5, 1)],
        [(178, 110, 28, 16, 0.6, -1), (148, 112, 24, 15, 0.5, -1), (164, 86, 28, 16, 1.1, 0)],
        [(78, 62, 28, 16, 1.9, 1), (56, 78, 23, 14, 1.5, 1)],
        [(114, 96, 34, 17, 1.9, 0), (114, 72, 32, 16, 1.9, 0), (88, 78, 25, 15, 1.5, 1), (140, 80, 25, 15, 1.3, 0)],
        [(100, 42, 30, 16, 2.7, 1), (132, 46, 29, 15, 2.3, 1), (116, 56, 30, 16, 2.2, 1), (156, 66, 25, 15, 1.8, 0)],
    ]
    cs, cgs, bs, bgs, fs = [], [], [], [], []
    for ci in range(6):
        lp, lg, bp, bg, fp = ab.render_apple_cluster_and_phenology(fw, fh, bols[ci], fx, 80, 86, 521 + ci * 7, pad_x=12, make_pheno=True, glows=3)
        cs.append(lp); cgs.append(lg); bs.append(bp); bgs.append(bg); fs.append(fp)
    over, _, _, _, _ = ab.render_apple_cluster_and_phenology(fw, fh, [(64, 54, 21, 12, 2.4, 1), (164, 56, 21, 12, 2.0, 0)], fx, 80, 86, 565, pad_x=12, make_pheno=False, glows=0)

    t_frames, ig_m, fg_n, traits = ab.build_apple_traits(fw, fh, fx, fy, cut_y, fork_y, 14, smask, 571, base_col=24, mistle_glow_col=13, fungi_glow_col=14, pad_x=12)
    all_cols = [skirt, tbase, tupper, k1, k2, *cs, over, *bs, *fs, *t_frames]
    all_glows = [tg, *cgs, *bgs, ig_m, fg_n]
    ab.write_png(OUT_DIR / "s5.png", fw * len(all_cols), fh, pack_strip(all_cols, fw, fh))
    ab.write_png(OUT_DIR / "s5_glow.png", fw * len(all_glows), fh, pack_strip(all_glows, fw, fh))
    pheno = {"blossom_cols": [12, 13, 14, 15, 16, 17], "fruit_cols": [18, 19, 20, 21, 22, 23], "blossom_glow_start": 7}
    return make_rig_entry(fw, fh, fx, fy, cut_y, 152, 42, 14, 86, "s5", "s5_glow", len(all_cols), len(all_glows),
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": 2, "harvest_amber": -1, "kerf_1": 3, "kerf_2": 4, "overhang": 11},
        {"trunk_glow": 0, "harvest_glow": -1, "cluster_glow_start": 1},
        [{"col": 5, "role": "back_core", "side": 0.0, "anchor": [114, 98], "stiffness": 1.22, "flutter": 0.32, "phase": 0.0, "lobe": [0, 8, 58, 32]},
         {"col": 6, "role": "left_bough", "side": -1.0, "anchor": [78, 104], "stiffness": 0.88, "flutter": 0.40, "phase": 1.0, "lobe": [-42, 6, 42, 24]},
         {"col": 7, "role": "right_bough", "side": 1.0, "anchor": [150, 104], "stiffness": 0.88, "flutter": 0.40, "phase": 2.1, "lobe": [42, 6, 42, 24]},
         {"col": 8, "role": "left_upper", "side": -0.7, "anchor": [88, 72], "stiffness": 0.92, "flutter": 0.42, "phase": 3.2, "lobe": [-26, -4, 34, 20]},
         {"col": 9, "role": "mid_heart", "side": 0.0, "anchor": [114, 92], "stiffness": 1.05, "flutter": 0.36, "phase": 4.3, "lobe": [0, 4, 46, 26]},
         {"col": 10, "role": "sun_crest", "side": 0.2, "anchor": [120, 58], "stiffness": 0.84, "flutter": 0.44, "phase": 5.4, "lobe": [6, -8, 46, 26]}],
        perches=[[-46, 82, 1], [46, 80, 2], [-14, 128, 4], [20, 124, 5]],
        hollow=[-3, -46], rest=[26, 4], pheno=pheno, traits=traits)


def build_coppice():
    fw, fh, fx, fy, cut_y = 96, 88, 48, 72, 60
    stems = [([(fx, fy + 1), (fx, cut_y)], 10.2, 9.4)]
    skirt, tbase, _, _ = ab.build_apple_skeleton(fw, fh, fx, fy, cut_y, cut_y - 4, 10, stems, [], 601, n_roots=4, pad_x=6)
    c0, _, _, _, _ = ab.render_apple_cluster_and_phenology(fw, fh, [(fx - 16, 44, 10, 7, 0.8, 1), (fx, 38, 12, 8, 1.4, 1), (fx + 16, 45, 10, 7, 0.8, 0)], fx, 42, 24, 621, pad_x=12, make_pheno=False, glows=0)
    for sx, tx, ty, sd in ((fx - 9, fx - 17, 44, 611), (fx - 4, fx - 6, 38, 613), (fx + 4, fx + 7, 39, 615), (fx + 9, fx + 17, 45, 617)):
        ab.draw_apple_limb(c0, [(sx, cut_y - 1), ((sx + tx) // 2, (cut_y + ty) // 2), (tx, ty)], 1.5, 0.9, fy, -999, sd, pad_x=12, thorny=True)
    ab.finish_apple_foliage(c0, 12)
    ab.write_png(OUT_DIR / "coppice.png", fw * 3, fh, pack_strip([skirt, tbase, c0], fw, fh))
    return make_rig_entry(fw, fh, fx, fy, cut_y, 32, 4, 10, 24, "coppice", "", 3, 0,
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": -1, "harvest_amber": -1, "kerf_1": -1, "kerf_2": -1, "overhang": -1},
        {"trunk_glow": -1, "harvest_glow": -1, "cluster_glow_start": -1},
        [{"col": 2, "role": "coppice_shoots", "side": 0.0, "anchor": [48, 60], "stiffness": 1.10, "flutter": 0.54, "phase": 0.0, "lobe": [0, 0, 24, 14]}])


def build_s6_log():
    fw, fh, fx, fy, cut_y = 148, 60, 74, 46, 40
    skirt, tbase, c0, tg = ab.blank(fw, fh), ab.blank(fw, fh), ab.blank(fw, fh), ab.blank(fw, fh)
    for y in range(fy - 7, fy + 10):
        for x in range(16, fw - 16):
            d = math.hypot((x - fx - 3) / 50.0, (y - fy - 2) / 8.0) + (ab.vnoise(x * 0.2, y * 0.25, 701) - 0.5) * 0.2
            if d < 1.0:
                ab.put_contact_shadow(skirt, x, y, int(112 * ((1.0 - d) ** 1.4)))
    ab.draw_apple_limb(tbase, [(26, 42), (60, 39), (94, 40), (122, 43)], 9.2, 7.6, fy, -999, 705, pad_x=10)
    # Golden Xanthoria lichen & mossy spine on fallen twisted apple log
    for y in range(30, 49):
        for x in range(26, 124):
            if tbase[y][x][3] > 0:
                nv = ab.vnoise(x * 0.24, y * 0.24, 709)
                if y < 38 and nv > 0.62:
                    ab.put(tbase, x, y, ab.MOSS[3 if nv > 0.78 else 2])
                elif nv > 0.78:
                    ab.put(tbase, x, y, ab.XANTHORIA[2 if y < 40 else 1])
    ab.selout_bark(tbase, pad_x=10, stop_y=fy + 2)
    ab.draw_apple_cut_rings(tbase, 122, 43, 5, 6)
    for dy in range(-5, 6):
        for dx in range(-4, 5):
            if math.hypot(dx / 4.0, dy / 5.2) <= 1.0:
                ab.put(tbase, 26 + dx, 42 + dy, ab.OUT_BARK if abs(dx) < 2 and abs(dy) < 3 else ab.BARK[0])
    for gx in (44, 68, 92, 110):
        ab.put(tbase, gx, 42, ab.GLOW[2])
        ab.put(tg, gx, 42, ab.GLOW[3])
        ab.put(skirt, gx - 2, 47, ab.FRUIT[2 if gx % 8 == 0 else 3])
    for sx, sy in ((46, 29), (74, 27), (102, 30)):
        for y in range(sy, sy + 6):
            ab.put(c0, sx, y, ab.THORN_BARK[2] if y > sy + 3 else ab.LEAF[3])
        ab.draw_apple_rosette(c0, sx, sy, None, ab.LEAF[2], ab.LEAF[3], ab.LEAF[5], pad_x=12)
    ab.finish_apple_foliage(c0, 12)
    ab.write_png(OUT_DIR / "s6_log.png", fw * 3, fh, pack_strip([skirt, tbase, c0], fw, fh))
    ab.write_png(OUT_DIR / "s6_log_glow.png", fw, fh, tg)
    return make_rig_entry(fw, fh, fx, fy, cut_y, 28, 4, 12, 46, "s6_log", "s6_log_glow", 3, 1,
        {"root_skirt": 0, "trunk_base": 1, "trunk_upper": -1, "harvest_amber": -1, "kerf_1": -1, "kerf_2": -1, "overhang": -1},
        {"trunk_glow": 0, "harvest_glow": -1, "cluster_glow_start": -1},
        [{"col": 2, "role": "nurse_sprouts", "side": 0.0, "anchor": [74, 34], "stiffness": 1.15, "flutter": 0.54, "phase": 0.0, "lobe": [0, 0, 42, 12]}])


def composite_onto(dst, ox: int, oy: int, frames: list, glows: list, r: dict, night: bool = False, mode: str = "none", trait_cols=None, glow_trait_cols=None) -> None:
    lay, gl, ph = r["layers"], r["glow_layers"], r.get("phenology", {})
    order = [lay["root_skirt"], lay["trunk_base"], lay["trunk_upper"]] + (trait_cols or [])
    p_cols = ph.get("blossom_cols", []) if mode == "blossom" else (ph.get("fruit_cols", []) if mode == "fruit" else [])
    for idx, cl in enumerate(r["clusters"]):
        order.append(cl["col"])
        if idx < len(p_cols):
            order.append(p_cols[idx])
    order.append(lay["overhang"])
    for ci in order:
        if 0 <= ci < len(frames):
            fr = frames[ci]
            if night:
                tinted = [[(max(12, int(p[0] * 0.36)), max(16, int(p[1] * 0.40)), max(28, int(p[2] * 0.54)), p[3]) if p[3] > 0 else ab.CLEAR for p in row] for row in fr]
                ab.blit(dst, tinted, ox, oy)
            else:
                ab.blit(dst, fr, ox, oy)
    if night and glows:
        g_order = [gl["trunk_glow"]] + (glow_trait_cols or [])
        if gl["cluster_glow_start"] >= 0:
            g_order.extend(range(gl["cluster_glow_start"], gl["cluster_glow_start"] + len(r["clusters"])))
        if mode == "blossom" and ph.get("blossom_glow_start", -1) >= 0:
            bgs = ph["blossom_glow_start"]
            g_order.extend(range(bgs, bgs + len(r["clusters"])))
        for gi in g_order:
            if 0 <= gi < len(glows):
                ab.blit(dst, glows[gi], ox, oy)


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
    frames = [ab.blank(fw, fh) for _ in range(ncols)]
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
    icon_paths = ab.build_apple_icons()
    for ip in icon_paths:
        read_frames_from_disk(ip, 16, 16, 1)
    rig = {
        "s0": build_s0(), "s1": build_s1(), "s2": build_s2(), "s3": build_s3(),
        "s4": build_s4_variant("s4", 401), "s4_b": build_s4_variant("s4_b", 451), "s4_c": build_s4_variant("s4_c", 481),
        "s5": build_s5(), "coppice": build_coppice(), "s6_log": build_s6_log(),
    }
    RIG_JSON.write_text(json.dumps(rig, indent=1) + "\n", encoding="utf-8")

    sw, sh = 1200, 496
    qa = ab.blank(sw, sh)
    meadow_tones = [ab.hexc("264a3b"), ab.hexc("2e5944"), ab.hexc("386a4d"), ab.hexc("447a55")]
    night_tones = [ab.hexc("111828"), ab.hexc("141d2e"), ab.hexc("182334")]
    for y in range(sh):
        for x in range(sw):
            v = ab.vnoise(x * 0.08, y * 0.12, 999)
            qa[y][x] = meadow_tones[ab.clampi(int(v * 4.0), 0, 3)] if y < 254 else night_tones[ab.clampi(int(v * 3.0), 0, 2)]

    lineup = [
        ("s0", "none", [], []),
        ("s1", "none", [], []),
        ("s2", "blossom", [], []),
        ("s3", "fruit", [rig["s3"]["traits"]["moss"][0], rig["s3"]["traits"]["sprig"][0]], []),
        ("s4", "fruit", [rig["s4"]["traits"]["moss"][0], rig["s4"]["traits"]["hollow"][0], rig["s4"]["traits"]["sprig"][0]], []),
        ("s4_b", "blossom", [rig["s4_b"]["traits"]["moss"][1], rig["s4_b"]["traits"]["fungi"][0], rig["s4_b"]["traits"]["hollow"][2]], []),
        ("s4_c", "fruit", [rig["s4_c"]["traits"]["ivy"][1], rig["s4_c"]["traits"]["hollow"][1], rig["s4_c"]["traits"]["fungi"][1]], [rig["s4_c"]["traits"]["fungi_glow"][1]]),
        ("s5", "blossom", [rig["s5"]["traits"]["moss"][0], rig["s5"]["traits"]["ivy"][0], rig["s5"]["traits"]["fungi"][1]], [rig["s5"]["traits"]["ivy_glow"][0], rig["s5"]["traits"]["fungi_glow"][1]]),
    ]
    x_cur, x_pos = 8, {}
    for key, mode, tcols, gtcols in lineup:
        r = rig[key]
        x_pos[key] = x_cur
        frs = read_frames_from_disk(OUT_DIR / f"{key}.png", r["frame_w"], r["frame_h"], r["num_cols"])
        gfs = read_frames_from_disk(OUT_DIR / f"{key}_glow.png", r["frame_w"], r["frame_h"], r["glow_cols"]) if r["glow_cols"] > 0 else []
        composite_onto(qa, x_cur, 236 - r["feet_y"], frs, gfs, r, night=False, mode=mode, trait_cols=tcols, glow_trait_cols=gtcols)
        if key in ("s3", "s4", "s4_b", "s4_c", "s5"):
            composite_onto(qa, x_cur, 468 - r["feet_y"], frs, gfs, r, night=True, mode=mode, trait_cols=tcols, glow_trait_cols=gtcols)
        x_cur += r["frame_w"] + 2

    for key, ox, oy, is_n in (("coppice", 12, 54, False), ("s6_log", 112, 54, False), ("coppice", 12, 275, True), ("s6_log", 12, 400, True)):
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
                            ab.put(qa, 18 + idx * 38 + x * 2 + dx, 12 + y * 2 + dy, ic[y][x])
    ab.write_png(QA_SHEET, sw, sh, qa)
    read_frames_from_disk(QA_SHEET, sw, sh, 1)

    # 3x close-up zoom sheet of s4 Fruit, s4_b Blossom/Twin, s4_c Leaning Fruit, and s5 Hollow Blossom-Mother!
    zw, zh, pw = 960, 470, 76
    zimg = ab.blank(zw, zh)
    for pi, key in enumerate(("s4", "s4_b", "s4_c", "s5")):
        r = rig[key]
        x0 = x_pos[key] + r["feet_x"] - pw // 2
        ox = 6 + pi * (pw * 3 + 10)
        for y in range(152):
            for x in range(pw):
                c = qa[90 + y][x0 + x]
                for dy in range(3):
                    for dx in range(3):
                        if ox + x * 3 + dx < zw:
                            zimg[6 + y * 3 + dy][ox + x * 3 + dx] = c
    ab.write_png(ZOOM_SHEET, zw, zh, zimg)
    read_frames_from_disk(ZOOM_SHEET, zw, zh, 1)
    print("Generated 2.0 Glimmtal-Wildapfel assets, icons, rig JSON, and 1x/3x QA sheets (0 #000000 verified).")


if __name__ == "__main__":
    main()
