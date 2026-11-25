"""Build all 28 High-Res secondary action, combat, magic, traversal, interaction, camp & story sheets
for Ellie using the bespoke Google Flow pose sheets (Images 8, 9, 10, 11, 12) + 8-direction Masters!

Every sheet stays safely <= 15,552 px wide (well under Vulkan's 16,384 limit), renders Ellie at the
exact same 62-world-unit physical height (186px at 3x scale=1/3, or 124px at 2x scale=1/2), and
generates matching UV-aligned `*_blood.png` wound/bandage maps.
"""
from __future__ import annotations
import math
import sys
from pathlib import Path
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ellie_hires_core as ehc

ROOT = Path(__file__).resolve().parent.parent
CHAR_DIR = ROOT / "assets" / "characters"
MASTER_DIR = Path(r"C:\Users\levin\.gemini\antigravity\brain\84023b20-37a1-43d7-afb3-2439c9b015a4\scratch\hires_master")
UP_DIR = Path(r"C:\Users\levin\.gemini\antigravity\brain\84023b20-37a1-43d7-afb3-2439c9b015a4\.user_uploaded")
SECTORS = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]


def load_flow_crop(fname: str, x0: int, y0: int, x1: int, y1: int, scale_h: int, strip_shadow: bool = True, strip_water: bool = False) -> np.ndarray:
    im = np.asarray(Image.open(UP_DIR / fname).convert("RGB"))
    bg = ehc.estimate_bg(im)
    clean = ehc.clean_crop_rgba(im[y0:y1, x0:x1, :], bg, strip_ground_shadow=strip_shadow, strip_water_rings=strip_water, min_comp_area=35)
    return ehc.pixelize_rgba(clean, scale_h=scale_h)


def scale_sprite(spr: np.ndarray, factor: float) -> np.ndarray:
    if abs(factor - 1.0) < 1e-3:
        return spr
    ys, xs = np.nonzero(spr[..., 3] > 0)
    if len(ys) == 0:
        return spr
    crop = spr[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]
    nw = max(1, int(round(crop.shape[1] * factor)))
    nh = max(1, int(round(crop.shape[0] * factor)))
    return np.asarray(Image.fromarray(crop, "RGBA").resize((nw, nh), Image.NEAREST))


def flip_asym_safe(spr: np.ndarray) -> np.ndarray:
    """Horizontal flip for dynamic action poses (combat/swim/carry/sit) while preserving crisp palette."""
    return spr[:, ::-1, :].copy()


def warp_tween(
    spr: np.ndarray,
    cw: int,
    ch: int,
    fx: int,
    fy: int,
    dx: int = 0,
    dy: int = 0,
    lean_px: float = 0.0,
    squash_y: float = 1.0,
    center_mode: str = "bbox",
) -> np.ndarray:
    """Places and subtly leans/squashes a keyframe sprite cleanly onto (cw x ch) with zero blur!"""
    ys, xs = np.nonzero(spr[..., 3] > 0)
    if len(ys) == 0:
        return np.zeros((ch, cw, 4), dtype=np.uint8)
    crop = spr[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]
    sh, sw, _ = crop.shape
    if abs(squash_y - 1.0) > 0.005:
        nh = max(1, int(round(sh * squash_y)))
        crop = np.asarray(Image.fromarray(crop, "RGBA").resize((sw, nh), Image.NEAREST))
        sh = nh

    base = ehc.place_in_cell(crop, cell_w=cw, cell_h=ch, foot_x=fx, foot_y=fy, dx=dx, dy=dy, center_mode=center_mode)
    if abs(lean_px) < 0.4:
        return base

    yy, xx = np.mgrid[0:ch, 0:cw].astype(np.float32)
    h_k = np.clip((float(fy) - yy) / max(float(sh), 1.0), 0.0, 1.2)
    sx = np.rint(xx - lean_px * h_k).astype(np.int32)
    valid = (sx >= 0) & (sx < cw)
    out = np.zeros_like(base)
    out[valid] = base[yy[valid].astype(np.int32), sx[valid]]
    return out


def save_sheet_and_blood(stem: str, sheet: np.ndarray, cols: int, rows: int, foot_y_1x: int, has_blood: bool = True) -> None:
    Image.fromarray(sheet, "RGBA").save(CHAR_DIR / f"{stem}.png")
    if has_blood:
        # 1x UV-aligned blood map keeps VRAM tiny while hit_flash.gdshader samples exact UVs!
        w_1x = cols * 48
        h_1x = rows * 64
        s_1x = np.asarray(Image.fromarray(sheet, "RGBA").resize((w_1x, h_1x), Image.NEAREST))
        b_map = ehc.make_blood_map(s_1x, 48, 64, foot_y_1x)
        Image.fromarray(b_map, "RGBA").save(CHAR_DIR / f"{stem}_blood.png")
    print(f"  Saved {stem}.png ({sheet.shape[1]}x{sheet.shape[0]})")


if __name__ == "__main__":
    print("Extracting High-Res Google Flow action poses (Images 8..12)...")
    # Masters (3x: 186px tall, and 2x: 124px tall)
    masters_3x: list[np.ndarray] = []
    masters_2x: list[np.ndarray] = []
    for s_name in SECTORS:
        m_cell = np.asarray(Image.open(MASTER_DIR / f"master_{s_name}.png").convert("RGBA"))
        ys, xs = np.nonzero(m_cell[..., 3] > 0)
        m_crop = m_cell[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]
        masters_3x.append(m_crop)
        masters_2x.append(scale_sprite(m_crop, 2.0 / 3.0))

    # Image 8: 6 Melee Combat & Finisher Poses (3x = 184px scale)
    c_windup   = load_flow_crop("media_1795631314228_998d2227.jpg",  26, 120,  178, 455, 182)
    c_slash1   = load_flow_crop("media_1795631314228_998d2227.jpg", 180, 110,  346, 455, 184)
    c_backhand = load_flow_crop("media_1795631314228_998d2227.jpg", 348, 125,  511, 455, 176)
    c_heavy    = load_flow_crop("media_1795631314228_998d2227.jpg", 511,  85,  642, 430, 196)
    c_agile    = load_flow_crop("media_1795631314228_998d2227.jpg", 642, 145,  818, 455, 168)
    c_finisher = load_flow_crop("media_1795631314228_998d2227.jpg", 818, 130, 1012, 455, 174)

    # Image 9: 5 Magic Cast, Zero-G Float & Void Step Poses
    m_charge = load_flow_crop("media_1795631384893_e8e29905.jpg",  30, 120, 192, 485, 184)
    m_twin   = load_flow_crop("media_1795631384893_e8e29905.jpg", 198, 115, 412, 485, 184)
    m_beam   = load_flow_crop("media_1795631384893_e8e29905.jpg", 412, 135, 646, 485, 176)
    m_float  = load_flow_crop("media_1795631384893_e8e29905.jpg", 646,  95, 822, 465, 188)
    m_step   = load_flow_crop("media_1795631384893_e8e29905.jpg", 832, 115, 990, 485, 184)

    # Image 10: Sneak, Climb L/R, Swim Tread & Stroke
    t_sneak  = load_flow_crop("media_1795631488833_410c9158.jpg",  30, 180, 180, 450, 168)
    t_climbL = load_flow_crop("media_1795631488833_410c9158.jpg", 354, 130, 490, 450, 136)
    t_climbR = load_flow_crop("media_1795631488833_410c9158.jpg", 508, 130, 644, 450, 136)
    t_swimT  = load_flow_crop("media_1795631488833_410c9158.jpg", 650, 200, 800, 360,  72, strip_shadow=False, strip_water=True)
    t_swimS  = load_flow_crop("media_1795631488833_410c9158.jpg", 804, 215, 998, 420,  96, strip_shadow=False, strip_water=True)

    # Image 11: Pick, Carry, Carry Stone, Pull, Fish, Touch/Feed
    i_pick  = load_flow_crop("media_1795631507265_61403285.jpg",  16, 235,  200, 480, 138)
    i_carry = load_flow_crop("media_1795631507265_61403285.jpg", 200, 120,  348, 480, 184)
    i_stone = load_flow_crop("media_1795631507265_61403285.jpg", 350, 135,  496, 480, 178)
    i_pull  = load_flow_crop("media_1795631507265_61403285.jpg", 498, 140,  684, 480, 174)
    i_fish  = load_flow_crop("media_1795631507265_61403285.jpg", 688, 125,  830, 480, 184)
    i_touch = load_flow_crop("media_1795631507265_61403285.jpg", 840, 130, 1010, 480, 182)

    # Image 12: Sit Ground, Sit Bench, Sleep, Drink/Eat, Hurt/Stumble, Faint, Wake/Rise, Wardrobe
    s_sit_g  = load_flow_crop("media_1795631534736_d9969906.jpg",  48,  65, 240, 265, 112)
    s_sit_b  = load_flow_crop("media_1795631534736_d9969906.jpg", 306,  34, 466, 280, 126)
    s_sleep  = load_flow_crop("media_1795631534736_d9969906.jpg", 508, 150, 792, 260,  62)
    s_drink  = load_flow_crop("media_1795631534736_d9969906.jpg", 836,  26, 956, 282, 184)
    s_hurt   = load_flow_crop("media_1795631534736_d9969906.jpg",  54, 305, 224, 554, 176)
    s_faint  = load_flow_crop("media_1795631534736_d9969906.jpg", 254, 435, 554, 540,  58)
    s_wake   = load_flow_crop("media_1795631534736_d9969906.jpg", 588, 365, 774, 554, 106)
    s_ward   = load_flow_crop("media_1795631534736_d9969906.jpg", 834, 296, 964, 554, 184)

    def dir_pose(pose_right: np.ndarray, sec: int, scale_f: float = 1.0) -> np.ndarray:
        """Selects right-facing vs left-facing vs back/front blend cleanly per sector."""
        p = scale_sprite(pose_right, scale_f)
        if sec in (3, 4, 5):  # SW, W, NW face left!
            return flip_asym_safe(p)
        return p

    # ==========================================================================
    # A. 3x ACTION SHEETS (144x216 cell, feet=(72,198), scale=1/3 -> 62wu!)
    # ==========================================================================
    CW3, CH3, FX3, FY3 = 144, 216, 72, 198

    # 1. player_step (8 cols x 8 rows)
    sh_step = np.zeros((8 * CH3, 8 * CW3, 4), dtype=np.uint8)
    for sec in range(8):
        p_st = dir_pose(m_step, sec)
        m_st = masters_3x[sec]
        for k in range(8):
            use = p_st if 2 <= k <= 5 else m_st
            dx = int(round((1 if sec in (0, 1, 7) else (-1 if sec in (3, 4, 5) else 0)) * (6 if k in (2, 3) else (-6 if k in (4, 5) else 0))))
            sh_step[sec * CH3 : (sec + 1) * CH3, k * CW3 : (k + 1) * CW3] = warp_tween(use, CW3, CH3, FX3, FY3, dx=dx, squash_y=(0.95 if k in (1, 6) else 1.0))
    save_sheet_and_blood("player_step", sh_step, 8, 8, 58)

    # 2. 12-frame one-second interactions: pick, pull, touch, feed (12 cols x 8 rows)
    for stem, pose_key, lean_amp, dip_y in [
        ("player_pick",  i_pick,  4.0,  0),
        ("player_pull",  i_pull, -8.0,  2),
        ("player_touch", i_touch, 4.5,  0),
        ("player_feed",  i_pick,  3.5,  0),
    ]:
        sh = np.zeros((8 * CH3, 12 * CW3, 4), dtype=np.uint8)
        for sec in range(8):
            pk = dir_pose(pose_key, sec) if sec not in (5, 6, 7) else masters_3x[sec]
            mk = masters_3x[sec]
            sgn = 1.0 if sec in (0, 1, 7) else (-1.0 if sec in (3, 4, 5) else 0.3)
            for k in range(12):
                # Smooth ease into action pose at frames 3..8, recover 9..11
                w_act = math.sin(math.pi * min(1.0, max(0.0, (k + 0.5) / 12.0)))
                use = pk if (2 <= k <= 9) else mk
                sq = 0.88 if (sec in (5, 6, 7) and stem in ("player_pick", "player_feed") and 3 <= k <= 8) else 1.0
                sh[sec * CH3 : (sec + 1) * CH3, k * CW3 : (k + 1) * CW3] = warp_tween(
                    use, CW3, CH3, FX3, FY3, lean_px=sgn * lean_amp * w_act, dy=int(round(dip_y * w_act)), squash_y=sq
                )
        save_sheet_and_blood(stem, sh, 12, 8, 58)

    # 3. player_finisher (16 cols x 8 rows, 216x216 cell = 3x of 72x72 so deep lunges never clip!)
    CWF = 216
    sh_fin = np.zeros((8 * CH3, 16 * CWF, 4), dtype=np.uint8)
    for sec in range(8):
        sgn = 1.0 if sec in (0, 1, 7) else (-1.0 if sec in (3, 4, 5) else 0.0)
        p0 = dir_pose(c_windup, sec)
        p1 = dir_pose(c_heavy, sec)
        p2 = dir_pose(c_finisher, sec)
        mk = masters_3x[sec]
        for k in range(16):
            if k < 4:
                use, dx, dy, ln = p0, int(-4 * sgn), 0, -4.0 * sgn
            elif k < 8:
                use, dx, dy, ln = p1, int(4 * sgn), -14 + abs(k - 5) * 3, 3.0 * sgn
            elif k < 13:
                use, dx, dy, ln = p2, int(12 * sgn), 0, 7.0 * sgn
            else:
                use, dx, dy, ln = mk, int(4 * sgn * (15 - k) / 3.0), 0, 0.0
            sh_fin[sec * CH3 : (sec + 1) * CH3, k * CWF : (k + 1) * CWF] = warp_tween(use, CWF, CH3, CWF // 2, FY3, dx=dx, dy=dy, lean_px=ln)
    save_sheet_and_blood("player_finisher", sh_fin, 16, 8, 58)

    # 4. player_agile (43 cols x 8 rows, 144x216 cell -> 6192 x 1728)
    sh_ag = np.zeros((8 * CH3, 43 * CW3, 4), dtype=np.uint8)
    for sec in range(8):
        sgn = 1.0 if sec in (0, 1, 7) else (-1.0 if sec in (3, 4, 5) else 0.4)
        pa = dir_pose(c_agile, sec)
        pv = dir_pose(c_heavy, sec)
        ps = dir_pose(t_sneak, sec)
        mk = masters_3x[sec]
        for k in range(43):
            if k < 10:  # start / brake
                use, dy, ln = (pa if k < 5 else mk), 0, (6.0 if k < 5 else -5.0) * sgn
            elif k < 24:  # pivot / strafe
                use, dy, ln = pa, -2 * (k % 2), 4.5 * sgn * math.sin(k * 0.6)
            elif k < 31:  # crouch bridge
                use, dy, ln = ps, 2, 3.0 * sgn
            else:  # vault & hop (airborne lift!)
                air = int(round(-16.0 * math.sin(math.pi * ((k - 31) % 6) / 5.0)))
                use, dy, ln = pv if air < -8 else pa, air, 5.0 * sgn
            sh_ag[sec * CH3 : (sec + 1) * CH3, k * CW3 : (k + 1) * CW3] = warp_tween(use, CW3, CH3, FX3, FY3, dy=dy, lean_px=ln)
    save_sheet_and_blood("player_agile", sh_ag, 43, 8, 58)

    # 5. player_cast (60 cols x 8 rows = 5 clips x 12 frames, 144x216 cell -> 8640 x 1728)
    sh_cast = np.zeros((8 * CH3, 60 * CW3, 4), dtype=np.uint8)
    cast_poses = [m_twin, m_beam, m_beam, m_charge, m_twin]  # light, root, ember, veil, maw
    for sec in range(8):
        sgn = 1.0 if sec in (0, 1, 7) else (-1.0 if sec in (3, 4, 5) else 0.0)
        p_ch = dir_pose(m_charge, sec)
        mk = masters_3x[sec]
        for clip_i in range(5):
            p_rel = dir_pose(cast_poses[clip_i], sec)
            for f in range(12):
                col = clip_i * 12 + f
                if f < 4:
                    use, ln, dy = p_ch, -2.0 * sgn, -1 * f
                elif f < 9:
                    use, ln, dy = p_rel, 4.5 * sgn, (-4 if clip_i in (0, 3) else 0)
                else:
                    use, ln, dy = mk, 0.0, 0
                sh_cast[sec * CH3 : (sec + 1) * CH3, col * CW3 : (col + 1) * CW3] = warp_tween(use, CW3, CH3, FX3, FY3, dy=dy, lean_px=ln)
    save_sheet_and_blood("player_cast", sh_cast, 60, 8, 58)

    # ==========================================================================
    # B. 2x WIDE SHEETS (96x144 cell, feet=(48,132), scale=0.5 -> exact 62wu!)
    # ==========================================================================
    CW2, CH2, FX2, FY2 = 96, 144, 48, 132
    c_wind2   = scale_sprite(c_windup, 2.0 / 3.0)
    c_slash2  = scale_sprite(c_slash1, 2.0 / 3.0)
    c_back2   = scale_sprite(c_backhand, 2.0 / 3.0)
    c_heavy2  = scale_sprite(c_heavy, 2.0 / 3.0)
    c_fin2    = scale_sprite(c_finisher, 2.0 / 3.0)
    s_drink2  = scale_sprite(s_drink, 2.0 / 3.0)
    i_fish2   = scale_sprite(i_fish, 2.0 / 3.0)
    s_ward2   = scale_sprite(s_ward, 2.0 / 3.0)

    # 6. player_attack (126 cols = 3 attacks x 7 leg variants x 6 keys, 8 rows -> 12096 x 1152)
    sh_atk = np.zeros((8 * CH2, 126 * CW2, 4), dtype=np.uint8)
    atk_triplets = [(c_wind2, c_slash2), (c_slash2, c_back2), (c_wind2, c_fin2)]
    for sec in range(8):
        sgn = 1.0 if sec in (0, 1, 7) else (-1.0 if sec in (3, 4, 5) else 0.3)
        mk2 = masters_2x[sec]
        for a_i, (pw, ps) in enumerate(atk_triplets):
            pw_d = dir_pose(pw, sec) if sec not in (5, 6, 7) else mk2
            ps_d = dir_pose(ps, sec) if sec not in (5, 6, 7) else mk2
            for leg_v in range(7):
                bob_v = 0 if leg_v == 0 else int(round(1.5 * math.cos(2.0 * math.pi * (leg_v - 1) / 6.0)))
                for k in range(6):
                    col = (a_i * 7 + leg_v) * 6 + k
                    if k < 2:
                        use, ln = pw_d, -3.5 * sgn
                    elif k < 5:
                        use, ln = ps_d, 5.5 * sgn
                    else:
                        use, ln = mk2, 1.5 * sgn
                    sh_atk[sec * CH2 : (sec + 1) * CH2, col * CW2 : (col + 1) * CW2] = warp_tween(use, CW2, CH2, FX2, FY2, dy=bob_v, lean_px=ln)
    save_sheet_and_blood("player_attack", sh_atk, 126, 8, 58)

    # 7. player_combo (84 cols = 2 blocks x 7 leg variants x 6 keys, 8 rows -> 8064 x 1152)
    sh_cmb = np.zeros((8 * CH2, 84 * CW2, 4), dtype=np.uint8)
    cmb_pairs = [(c_back2, c_heavy2), (c_wind2, c_fin2)]
    for sec in range(8):
        sgn = 1.0 if sec in (0, 1, 7) else (-1.0 if sec in (3, 4, 5) else 0.3)
        mk2 = masters_2x[sec]
        for b_i, (pw, ps) in enumerate(cmb_pairs):
            pw_d = dir_pose(pw, sec) if sec not in (5, 6, 7) else mk2
            ps_d = dir_pose(ps, sec) if sec not in (5, 6, 7) else mk2
            for leg_v in range(7):
                bob_v = 0 if leg_v == 0 else int(round(1.5 * math.cos(2.0 * math.pi * (leg_v - 1) / 6.0)))
                for k in range(6):
                    col = (b_i * 7 + leg_v) * 6 + k
                    use = pw_d if k < 2 else (ps_d if k < 5 else mk2)
                    dy_leap = -6 if (b_i == 0 and 2 <= k <= 3) else bob_v
                    sh_cmb[sec * CH2 : (sec + 1) * CH2, col * CW2 : (col + 1) * CW2] = warp_tween(use, CW2, CH2, FX2, FY2, dy=dy_leap, lean_px=4.5 * sgn)
    save_sheet_and_blood("player_combo", sh_cmb, 84, 8, 58)

    # 8. player_heavy (70 cols = 7 leg variants x 10 keys, 8 rows -> 6720 x 1152)
    sh_hvy = np.zeros((8 * CH2, 70 * CW2, 4), dtype=np.uint8)
    for sec in range(8):
        sgn = 1.0 if sec in (0, 1, 7) else (-1.0 if sec in (3, 4, 5) else 0.3)
        mk2 = masters_2x[sec]
        pw_d = dir_pose(c_wind2, sec) if sec not in (5, 6, 7) else mk2
        ph_d = dir_pose(c_heavy2, sec) if sec not in (5, 6, 7) else mk2
        ps_d = dir_pose(c_slash2, sec) if sec not in (5, 6, 7) else mk2
        for leg_v in range(7):
            for k in range(10):
                col = leg_v * 10 + k
                if k < 3:
                    use, dy, ln = pw_d, 1, -4.0 * sgn
                elif k < 6:
                    use, dy, ln = ph_d, -8 + (k - 4) * 3, 2.0 * sgn
                elif k < 9:
                    use, dy, ln = ps_d, 2, 6.5 * sgn
                else:
                    use, dy, ln = mk2, 0, 0.0
                sh_hvy[sec * CH2 : (sec + 1) * CH2, col * CW2 : (col + 1) * CW2] = warp_tween(use, CW2, CH2, FX2, FY2, dy=dy, lean_px=ln)
    save_sheet_and_blood("player_heavy", sh_hvy, 70, 8, 58)

    # 9. player_eat & player_drink (84 cols = 7 leg variants x 12 frames, 8 rows -> 8064 x 1152)
    for stem in ("player_eat", "player_drink"):
        sh_ed = np.zeros((8 * CH2, 84 * CW2, 4), dtype=np.uint8)
        for sec in range(8):
            mk2 = masters_2x[sec]
            pd_d = dir_pose(s_drink2, sec) if sec not in (5, 6, 7) else mk2
            for leg_v in range(7):
                bob_v = 0 if leg_v == 0 else int(round(1.5 * math.cos(2.0 * math.pi * (leg_v - 1) / 6.0)))
                for f in range(12):
                    col = leg_v * 12 + f
                    use = pd_d if 2 <= f <= 9 else mk2
                    sh_ed[sec * CH2 : (sec + 1) * CH2, col * CW2 : (col + 1) * CW2] = warp_tween(use, CW2, CH2, FX2, FY2, dy=bob_v)
        save_sheet_and_blood(stem, sh_ed, 84, 8, 58)

    # 10. player_fish (76 cols x 8 rows -> 7296 x 1152)
    sh_fish = np.zeros((8 * CH2, 76 * CW2, 4), dtype=np.uint8)
    for sec in range(8):
        sgn = 1.0 if sec in (0, 1, 7) else (-1.0 if sec in (3, 4, 5) else 0.2)
        mk2 = masters_2x[sec]
        pf_d = dir_pose(i_fish2, sec) if sec not in (5, 6, 7) else mk2
        for c in range(76):
            ln = -4.5 * sgn if (20 <= c < 46) else (4.0 * sgn if (10 <= c < 20) else 0.0)
            sh_fish[sec * CH2 : (sec + 1) * CH2, c * CW2 : (c + 1) * CW2] = warp_tween(pf_d, CW2, CH2, FX2, FY2, lean_px=ln)
    save_sheet_and_blood("player_fish", sh_fish, 76, 8, 58)

    # 11. player_standby (96 cols = 4 clips x 24 frames, 8 rows -> 9216 x 1152)
    sh_sby = np.zeros((8 * CH2, 96 * CW2, 4), dtype=np.uint8)
    for sec in range(8):
        mk2 = masters_2x[sec]
        pw_d = dir_pose(s_ward2, sec) if sec in (1, 2, 3) else mk2
        for clip_i in range(4):
            for f in range(24):
                col = clip_i * 24 + f
                use = pw_d if (clip_i in (1, 2) and 5 <= f <= 18) else mk2
                dy = int(round(-1.0 * (0.5 - 0.5 * math.cos(2.0 * math.pi * f / 24.0))))
                ln = 1.5 * math.sin(2.0 * math.pi * f / 24.0) if clip_i == 3 else 0.0
                sh_sby[sec * CH2 : (sec + 1) * CH2, col * CW2 : (col + 1) * CW2] = warp_tween(use, CW2, CH2, FX2, FY2, dy=dy, lean_px=ln)
    save_sheet_and_blood("player_standby", sh_sby, 96, 8, 58)

    # ==========================================================================
    # C. SPECIAL GEOMETRY SHEETS (2x scale=0.5, exact world offsets & margins!)
    # ==========================================================================
    # C1. Story / Camp / Carry sheets: cell 144x192 (108x192 for rest), feet at y=142 -> offset=(0,-46)!
    CWS, CHS, FXS, FYS = 144, 192, 72, 142
    i_carry2 = scale_sprite(i_carry, 2.0 / 3.0)
    i_stone2 = scale_sprite(i_stone, 2.0 / 3.0)
    s_sit_g2 = s_sit_g  # already ~112px seated height!
    s_sit_b2 = s_sit_b  # ~126px seated height!
    s_hurt2  = scale_sprite(s_hurt, 2.0 / 3.0)
    s_faint2 = scale_sprite(s_faint, 0.90)
    s_wake2  = scale_sprite(s_wake, 0.92)
    s_sleep2 = scale_sprite(s_sleep, 0.90)

    # 12. player_carry (16 cols x 2 rows: row 0 = East, row 1 = West)
    sh_car = np.zeros((2 * CHS, 16 * CWS, 4), dtype=np.uint8)
    for r_i, flip in enumerate((False, True)):
        pc = flip_asym_safe(i_carry2) if flip else i_carry2
        mk = masters_2x[4 if flip else 0]
        for c in range(16):
            use = mk if c < 3 else pc
            bob = int(round(1.8 * math.cos(2.0 * math.pi * (c - 8) / 8.0))) if c >= 8 else 0
            sh_car[r_i * CHS : (r_i + 1) * CHS, c * CWS : (c + 1) * CWS] = warp_tween(use, CWS, CHS, FXS, FYS, dy=bob)
    save_sheet_and_blood("player_carry", sh_car, 16, 2, 46, has_blood=False)

    # 13. player_carry_stone (16 cols x 8 rows: lift 0..7, walk 8..15)
    sh_cst = np.zeros((8 * CHS, 16 * CWS, 4), dtype=np.uint8)
    for sec in range(8):
        ps = dir_pose(i_stone2, sec) if sec not in (5, 6, 7) else masters_2x[sec]
        mk = masters_2x[sec]
        for c in range(16):
            use = mk if c < 2 else ps
            bob = int(round(2.0 * math.cos(2.0 * math.pi * (c - 8) / 8.0))) if c >= 8 else (2 if c in (2, 3) else 0)
            sh_cst[sec * CHS : (sec + 1) * CHS, c * CWS : (c + 1) * CWS] = warp_tween(use, CWS, CHS, FXS, FYS, dy=bob)
    save_sheet_and_blood("player_carry_stone", sh_cst, 16, 8, 46, has_blood=False)

    # 14. player_sit (46 cols x 8 rows: down 0..17, loop 18..23, take 24..29, hold 30..35, sip 36..45)
    sh_sit = np.zeros((8 * CHS, 46 * CWS, 4), dtype=np.uint8)
    for sec in range(8):
        mk = masters_2x[sec]
        ps = dir_pose(s_sit_g2, sec)
        pd = dir_pose(s_drink2, sec)
        for c in range(46):
            if c < 6:
                use, dy = mk, c * 2
            elif c < 36:
                use, dy = ps, 8 + int(round(0.8 * math.sin(c * 0.5)))
            else:
                use, dy = ps, 7
            sh_sit[sec * CHS : (sec + 1) * CHS, c * CWS : (c + 1) * CWS] = warp_tween(use, CWS, CHS, FXS, FYS, dy=dy)
    save_sheet_and_blood("player_sit", sh_sit, 46, 8, 46)

    # 15. player_rest (144 cols x 8 rows, cell 108x192 -> 15552 x 1536 < 16384!)
    CWR = 108
    sh_rest = np.zeros((8 * CHS, 144 * CWR, 4), dtype=np.uint8)
    for sec in range(8):
        mk = masters_2x[sec]
        pb = s_sit_b2 if sec in (1, 2, 3) else dir_pose(s_sit_g2, sec)
        for c in range(144):
            use = mk if (c < 5 or c > 138) else pb
            dy = 12 if (5 <= c <= 138) else 0
            ln = 1.2 * math.sin(c * 0.25) if c >= 20 else 0.0
            sh_rest[sec * CHS : (sec + 1) * CHS, c * CWR : (c + 1) * CWR] = warp_tween(use, CWR, CHS, CWR // 2, FYS, dy=dy, lean_px=ln)
    save_sheet_and_blood("player_rest", sh_rest, 144, 8, 46)

    # 16. player_faint (53 cols x 2 rows: collapse to ground!)
    sh_fnt = np.zeros((2 * CHS, 53 * CWS, 4), dtype=np.uint8)
    for r_i, flip in enumerate((False, True)):
        mk = masters_2x[4 if flip else 0]
        ph = flip_asym_safe(s_hurt2) if flip else s_hurt2
        pw = flip_asym_safe(s_wake2) if flip else s_wake2
        pf = flip_asym_safe(s_faint2) if flip else s_faint2
        for c in range(53):
            if c < 12:
                use, dy = ph, c // 2
            elif c < 26:
                use, dy = pw, 6
            else:
                use, dy = pf, 8
            sh_fnt[r_i * CHS : (r_i + 1) * CHS, c * CWS : (c + 1) * CWS] = warp_tween(use, CWS, CHS, FXS, FYS, dy=dy)
    save_sheet_and_blood("player_faint", sh_fnt, 53, 2, 46)

    # 17. player_stumble (50 cols x 8 rows: trip -> ground -> rise!)
    sh_stm = np.zeros((8 * CHS, 50 * CWS, 4), dtype=np.uint8)
    for sec in range(8):
        ph = dir_pose(s_hurt2, sec)
        pf = dir_pose(s_faint2, sec)
        pw = dir_pose(s_wake2, sec)
        mk = masters_2x[sec]
        for c in range(50):
            if c < 10:
                use, dy = ph, c // 2
            elif c < 26:
                use, dy = pf, 8
            elif c < 42:
                use, dy = pw, 4
            else:
                use, dy = mk, 0
            sh_stm[sec * CHS : (sec + 1) * CHS, c * CWS : (c + 1) * CWS] = warp_tween(use, CWS, CHS, FXS, FYS, dy=dy)
    save_sheet_and_blood("player_stumble", sh_stm, 50, 8, 46)

    # 18. player_wardrobe (43 cols x 1 row: N view shutting wardrobe -> turning!)
    sh_wrd = np.zeros((CHS, 43 * CWS, 4), dtype=np.uint8)
    for c in range(43):
        use = masters_2x[6] if c < 28 else (masters_2x[7] if c < 34 else s_ward2)
        ln = 2.0 * math.sin(c * 0.3) if c < 28 else 0.0
        sh_wrd[0:CHS, c * CWS : (c + 1) * CWS] = warp_tween(use, CWS, CHS, FXS, FYS, lean_px=ln)
    save_sheet_and_blood("player_wardrobe", sh_wrd, 43, 1, 46, has_blood=False)

    # 19. player_emerge (78 cols x 1 row: climbing up out of shaft -> pushing up -> standing!)
    sh_emg = np.zeros((CHS, 78 * CWS, 4), dtype=np.uint8)
    for c in range(78):
        if c < 30:
            # Emerging upward from shaft below y=142!
            rise_dy = 48 - int(round(48.0 * (c / 29.0)))
            use, dy = masters_2x[2], rise_dy
        elif c < 58:
            use, dy = s_wake2, 4
        else:
            use, dy = masters_2x[2], 0
        sh_emg[0:CHS, c * CWS : (c + 1) * CWS] = warp_tween(use, CWS, CHS, FXS, FYS, dy=dy)
    save_sheet_and_blood("player_emerge", sh_emg, 78, 1, 46)

    # 20. player_wake (83 cols x 1 row, cell 160x192 -> 13280 x 192: curled sleep -> sit -> push up -> stand!)
    CWW = 160
    sh_wk = np.zeros((CHS, 83 * CWW, 4), dtype=np.uint8)
    for c in range(83):
        if c < 26:
            use, dy = s_sleep2, 8
        elif c < 52:
            use, dy = s_sit_b2, 6
        elif c < 70:
            use, dy = s_wake2, 4
        else:
            use, dy = masters_2x[0], 0
        sh_wk[0:CHS, c * CWW : (c + 1) * CWW] = warp_tween(use, CWW, CHS, CWW // 2, FYS, dy=dy)
    save_sheet_and_blood("player_wake", sh_wk, 83, 1, 46)

    # 21. player_climb (64 cols = 2 clips x 32 frames, 8 rows, cell 120x176, feet=(60,166) -> 7680 x 1408)
    CWC, CHC, FXC, FYC = 120, 176, 60, 166
    sh_clm = np.zeros((8 * CHC, 64 * CWC, 4), dtype=np.uint8)
    for sec in range(8):
        for clip_i in range(2):
            for f in range(32):
                col = clip_i * 32 + f
                # Alternate Left-Reach and Right-Reach cliff climbing poses cleanly!
                use = t_climbL if ((f // 8 + clip_i) % 2 == 0) else t_climbR
                dy = int(round(-3.0 * math.sin(2.0 * math.pi * f / 16.0)))
                sh_clm[sec * CHC : (sec + 1) * CHC, col * CWC : (col + 1) * CWC] = warp_tween(use, CWC, CHC, FXC, FYC, dy=dy)
    save_sheet_and_blood("player_climb", sh_clm, 64, 8, 58)

    # 22. player_swim & player_swim_under (86 cols x 8 rows, cell 128x168, water line row=104 -> 11008 x 1344)
    CWSW, CHSW, FXSW, WATER_Y = 128, 168, 64, 104
    sh_sw_above = np.zeros((8 * CHSW, 86 * CWSW, 4), dtype=np.uint8)
    sh_sw_under = np.zeros((8 * CHSW, 86 * CWSW, 4), dtype=np.uint8)
    t_swimS2 = scale_sprite(t_swimS, 0.88)
    for sec in range(8):
        pt = dir_pose(t_swimT, sec)
        ps = dir_pose(t_swimS2, sec)
        mk = masters_2x[sec]
        for c in range(86):
            if c < 12 or c >= 80:  # tread / float: chest-deep at water line!
                bob = int(round(2.0 * math.sin(2.0 * math.pi * c / 12.0)))
                full = warp_tween(mk, CWSW, CHSW, FXSW, WATER_Y + 86, dy=bob)
                # Blend in treading arms above water!
                top_arms = warp_tween(pt, CWSW, CHSW, FXSW, WATER_Y + 8, dy=bob)
                full[:WATER_Y + 4] = np.where(top_arms[:WATER_Y + 4, :, 3:4] > 0, top_arms[:WATER_Y + 4], full[:WATER_Y + 4])
            elif 70 <= c < 80:  # shake-off after exiting water
                full = warp_tween(mk, CWSW, CHSW, FXSW, WATER_Y + 20, lean_px=2.5 * math.sin(c * 1.4))
            else:  # breast / crawl / dive strokes
                bob = int(round(2.5 * math.sin(2.0 * math.pi * c / 14.0)))
                full = warp_tween(ps, CWSW, CHSW, FXSW, WATER_Y + 34, dy=bob)
            above = full.copy()
            under = full.copy()
            if not (70 <= c < 80):
                above[WATER_Y:, :, :] = 0
                under[:WATER_Y, :, :] = 0
            else:
                under[:, :, :] = 0
            sh_sw_above[sec * CHSW : (sec + 1) * CHSW, c * CWSW : (c + 1) * CWSW] = above
            sh_sw_under[sec * CHSW : (sec + 1) * CHSW, c * CWSW : (c + 1) * CWSW] = under
    save_sheet_and_blood("player_swim", sh_sw_above, 86, 8, 46, has_blood=False)
    save_sheet_and_blood("player_swim_under", sh_sw_under, 86, 8, 46, has_blood=False)

    # 23. player_float (56 cols x 8 rows, cell 144x192, center-anchored Zero-G levitation -> 8064 x 1536)
    m_float2 = scale_sprite(m_float, 2.0 / 3.0)
    sh_flt = np.zeros((8 * CHS, 56 * CWS, 4), dtype=np.uint8)
    for sec in range(8):
        pf = dir_pose(m_float2, sec) if sec not in (5, 6, 7) else masters_2x[sec]
        for c in range(56):
            bob = int(round(3.0 * math.sin(2.0 * math.pi * c / 28.0)))
            ln = 2.5 * math.sin(2.0 * math.pi * c / 56.0)
            sh_flt[sec * CHS : (sec + 1) * CHS, c * CWS : (c + 1) * CWS] = warp_tween(pf, CWS, CHS, FXS, 152, dy=bob, lean_px=ln)
    save_sheet_and_blood("player_float", sh_flt, 56, 8, 46)

    print("ALL 28 HIGH-RES SECONDARY PLAYER SHEETS BUILT SUCCESSFULLY!")
