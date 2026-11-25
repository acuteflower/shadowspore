"""Builds Step 2: High-Res `assets/characters/player.png` (3168x3456, 22x16 cells of 144x216, 3x scale = 186px Ellie)
+ `player_blood.png` + modular `outfits/default/player.png` & `hair/default/player.png` (`_back.png`).

Combines:
- Authentic Google Flow East Walk (Image 5), East Sprint (Image 7), 720p SE Walk (`walk_all`), and Sneak (Image 10)
- Exact 8-direction 186px Masters (`E, SE, S, SW, W, NW, N, NE`) with smooth multi-zone limb/coat/hair gait animation
  so all 8 directions have true non-mirrored asymmetries, zero face flicker, and grounded foot contacts at cols 0 & 3!
"""
from __future__ import annotations
import math
import sys
from pathlib import Path
import numpy as np
from PIL import Image

sys.path.insert(0, r"c:\Users\levin\OneDrive\Dokumente\GitHub\shadowspore\tools")
import ellie_hires_core as ehc

ROOT = Path(r"c:\Users\levin\OneDrive\Dokumente\GitHub\shadowspore")
CHAR_DIR = ROOT / "assets" / "characters"
UP_DIR = Path(r"C:\Users\levin\.gemini\antigravity\brain\84023b20-37a1-43d7-afb3-2439c9b015a4\.user_uploaded")
MP4_WALK_DIR = Path(r"C:\Users\levin\.gemini\antigravity\brain\84023b20-37a1-43d7-afb3-2439c9b015a4\scratch\mp4_frames\walk_all")
MASTER_DIR = Path(r"C:\Users\levin\.gemini\antigravity\brain\84023b20-37a1-43d7-afb3-2439c9b015a4\scratch\hires_master")

CW, CH = ehc.CELL_W, ehc.CELL_H  # 144 x 216
FX, FY = ehc.FOOT_X, ehc.FOOT_Y  # 72, 198
COLS, ROWS = 22, 16
SECTORS = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

# Direction vectors on screen (dx_forward, dy_forward) for lean & stride projection per sector:
SECTOR_FWD: list[tuple[float, float]] = [
    (1.0, 0.0),    # 0 E
    (0.72, 0.35),  # 1 SE
    (0.0, 0.45),   # 2 S
    (-0.72, 0.35), # 3 SW
    (-1.0, 0.0),   # 4 W
    (-0.72, -0.35),# 5 NW
    (0.0, -0.45),  # 6 N
    (0.72, -0.35), # 7 NE
]


def load_rgb(p: Path) -> np.ndarray:
    return np.asarray(Image.open(p).convert("RGB"))


def animate_from_master(
    master_cell: np.ndarray,
    sector: int,
    phase_rad: float,
    mode: str,
) -> np.ndarray:
    """Articulates a 144x216 186px master cell smoothly with split-leg stride, arm swing, coat flow,
    hair S-wave sway, and breathing/crouch compression — zero blur (pure integer nearest-pixel warps!)."""
    out = np.zeros_like(master_cell)
    fx_d, fy_d = SECTOR_FWD[sector]
    s = math.sin(phase_rad)
    c = math.cos(phase_rad)
    s2 = math.sin(2.0 * phase_rad)  # 2 peaks per stride (contacts at phase 0 and pi!)

    if mode == "idle":
        # Gentle 4-frame breathing & breeze sway (legs 100% rock-steady planted!)
        bob_y = int(round(-1.2 * max(0.0, s)))
        crouch_k = 1.0
        lean_x = 0.0
        stride_amp = 0.0
        lift_amp = 0.0
        coat_sway = 1.6 * s
        hair_sway = 1.4 * math.sin(phase_rad - 0.7)
    elif mode == "walk":
        bob_y = int(round(-2.2 * abs(s)))  # down on contact (0, pi), up on passing (pi/2, 3pi/2)
        crouch_k = 1.0
        lean_x = fx_d * 1.5
        stride_amp = 8.5
        lift_amp = 5.0
        coat_sway = -fx_d * 2.5 + 2.2 * s
        hair_sway = -fx_d * 2.0 + 1.8 * math.sin(phase_rad - 0.6)
    elif mode == "jog":
        bob_y = int(round(-3.2 * abs(s) + 1.0))
        crouch_k = 0.97
        lean_x = fx_d * 4.0
        stride_amp = 12.5
        lift_amp = 8.0
        coat_sway = -fx_d * 4.8 + 3.0 * s
        hair_sway = -fx_d * 3.8 + 2.4 * math.sin(phase_rad - 0.6)
    elif mode == "sprint":
        bob_y = int(round(-4.5 * abs(s) + 1.5))
        crouch_k = 0.93
        lean_x = fx_d * 7.5
        stride_amp = 17.0
        lift_amp = 11.5
        coat_sway = -fx_d * 8.0 + 3.8 * s
        hair_sway = -fx_d * 6.5 + 3.0 * math.sin(phase_rad - 0.5)
    elif mode == "sneak":
        bob_y = int(round(9.0 - 1.5 * abs(s)))
        crouch_k = 0.88  # genuine low stealth crouch!
        lean_x = fx_d * 4.2
        stride_amp = 6.5
        lift_amp = 3.5
        coat_sway = -fx_d * 2.2 + 1.4 * s
        hair_sway = -fx_d * 1.8 + 1.2 * s
    else:
        return master_cell.copy()

    # Split lower body (y >= 112: thighs, stockings, boots) into left/right legs and render back-leg then front-leg!
    hip_y = 112
    # Upper body + coat + hair (y < 142 for coat/arms, y < 116 for skirt/hips)
    ys, xs = np.mgrid[0:CH, 0:CW]

    # First: transform upper body & skirt/coat (excluding legs below y=118 unless pixel is royal-purple coat!)
    r_ch = master_cell[..., 0].astype(np.int32)
    g_ch = master_cell[..., 1].astype(np.int32)
    b_ch = master_cell[..., 2].astype(np.int32)
    a_ch = master_cell[..., 3]
    is_coat = (a_ch > 0) & (b_ch > g_ch + 18) & (r_ch > g_ch + 6) & (ys >= 95) & (ys <= 162)
    is_hair = (a_ch > 0) & (b_ch >= r_ch - 6) & ((0.299 * r_ch + 0.587 * g_ch + 0.114 * b_ch) > 95) & (ys <= 105)

    # Render legs in two passes (far/back phase leg first, near/ lifted leg second) when stride_amp > 0
    if stride_amp > 0.0:
        for leg_sign in (-1, 1):
            # In side views (E=0, W=4), duplicate central leg column into alternating front/back strides!
            if sector in (0, 4):
                leg_src_mask = (a_ch > 0) & (~is_coat) & (ys >= 114)
            else:
                if leg_sign < 0:
                    leg_src_mask = (a_ch > 0) & (~is_coat) & (ys >= 114) & (xs <= FX)
                else:
                    leg_src_mask = (a_ch > 0) & (~is_coat) & (ys >= 114) & (xs >= FX)

            leg_phase = s * leg_sign  # +1 forward, -1 backward
            leg_lift = max(0.0, c * leg_sign) * lift_amp
            ly_s, lx_s = np.nonzero(leg_src_mask)
            if len(ly_s) == 0:
                continue
            t_leg = np.clip((ly_s - 114.0) / (FY - 114.0), 0.0, 1.0)
            if sector in (2, 6):  # S, N: legs step primarily vertically + slight perspective scale
                dx_l = np.rint(leg_Sign_x := (leg_sign * 0.8 * t_leg)).astype(np.int32)
                dy_l = np.rint(bob_y + (1.0 - crouch_k) * (FY - ly_s) - leg_lift * t_leg + leg_phase * 3.5 * t_leg).astype(np.int32)
            else:
                dx_l = np.rint(lean_x * (1.0 - 0.7 * t_leg) + fx_d * leg_phase * stride_amp * t_leg).astype(np.int32)
                dy_l = np.rint(bob_y + (1.0 - crouch_k) * (FY - ly_s) - leg_lift * (t_leg ** 1.1) + fy_d * leg_phase * 3.0 * t_leg).astype(np.int32)

            nx = lx_s + dx_l
            ny = ly_s + dy_l
            valid = (nx >= 0) & (nx < CW) & (ny >= 0) & (ny < CH)
            # Darken back leg in side views slightly by 1 step for crisp front/back leg readability!
            cols = master_cell[ly_s[valid], lx_s[valid]].copy()
            if sector in (0, 4) and leg_sign < 0:
                cols[:, :3] = (cols[:, :3].astype(np.float32) * 0.82).astype(np.uint8)
            out[ny[valid], nx[valid]] = cols
    else:
        # Idle: copy legs untouched at exact ground line!
        leg_mask = (a_ch > 0) & (~is_coat) & (ys >= 114)
        out[leg_mask] = master_cell[leg_mask]

    # Upper body + skirt + flowing coat + swaying hair tips
    upper_mask = (a_ch > 0) & ((ys < 116) | is_coat)
    uy, ux = np.nonzero(upper_mask)
    h_frac = np.clip((FY - uy) / float(ehc.TARGET_BODY_H), 0.0, 1.0)  # 0 at feet .. 1 at crown
    dx_u = lean_x * np.clip((h_frac - 0.35) / 0.65, 0.0, 1.0)
    dy_u = bob_y + (1.0 - crouch_k) * (FY - uy) * 0.85

    # Add billowing coat sway on lower coat tails
    coat_at = is_coat[uy, ux]
    coat_t = np.clip((uy - 102.0) / 56.0, 0.0, 1.0)
    dx_u = np.where(coat_at, dx_u + coat_sway * (coat_t ** 1.25), dx_u)
    dy_u = np.where(coat_at, dy_u - abs(coat_sway) * 0.28 * coat_t, dy_u)

    # Add silky hair tip sway on lower hair locks (y = 42..102)
    hair_at = is_hair[uy, ux] & (uy >= 40)
    hair_t = np.clip((uy - 40.0) / 55.0, 0.0, 1.0)
    dx_u = np.where(hair_at, dx_u + hair_sway * (hair_t ** 1.2), dx_u)

    # Subtle opposite arm swing on outer arm pixels (y = 70..124, |x - FX| >= 16)
    if stride_amp > 0.0:
        arm_at = (~coat_at) & (~hair_at) & (uy >= 68) & (uy <= 122) & (np.abs(ux - FX) >= (8 if sector in (0, 4) else 15))
        arm_t = np.clip((uy - 68.0) / 50.0, 0.0, 1.0)
        arm_side = np.where(ux < FX, -1.0, 1.0) if sector not in (0, 4) else 1.0
        dx_u = np.where(arm_at, dx_u - s * arm_side * (stride_amp * 0.42) * arm_t, dx_u)
        dy_u = np.where(arm_at, dy_u - abs(s) * 1.5 * arm_t, dy_u)

    nux = np.rint(ux + dx_u).astype(np.int32)
    nuy = np.rint(uy + dy_u).astype(np.int32)
    valid_u = (nux >= 0) & (nux < CW) & (nuy >= 0) & (nuy < CH)
    out[nuy[valid_u], nux[valid_u]] = master_cell[uy[valid_u], ux[valid_u]]

    # Fill 1-pixel internal gaps created by integer displacement so zero pinholes appear!
    op = out[..., 3] > 0
    hole = (~op) & (
        (ehc._shift2d(op, 1, 0) & ehc._shift2d(op, -1, 0))
        | (ehc._shift2d(op, 0, 1) & ehc._shift2d(op, 0, -1))
    )
    if np.any(hole):
        shifted_up = np.roll(out, 1, axis=0)
        shifted_lt = np.roll(out, 1, axis=1)
        fill_src = np.where(shifted_up[..., 3:4] > 0, shifted_up, shifted_lt)
        out[hole] = fill_src[hole]

    return out


def extract_flow_walk_E() -> list[np.ndarray]:
    """Extracts 6 walk frames from Flow Image 5 (5957bcdd.jpg, 2 rows of 4 East walk poses)."""
    rgb = load_rgb(UP_DIR / "media_1795631134524_5957bcdd.jpg")
    bg = ehc.estimate_bg(rgb)
    #Standing height in Img5 is ~248px -> px_step = 248 / 186.0 = 1.3333
    px_step = 248.0 / float(ehc.TARGET_BODY_H)
    r1 = ehc.clean_crop_rgba(rgb[:288], bg)
    r2 = ehc.clean_crop_rgba(rgb[288:], bg)
    x_spans = [(55, 220), (315, 440), (570, 695), (815, 985)]
    frames8: list[np.ndarray] = []
    for row_rgba in (r1, r2):
        for x0, x1 in x_spans:
            pix = ehc.pixelize_rgba(row_rgba[:, x0:x1], px_step=px_step)
            frames8.append(ehc.place_in_cell(pix, center_mode="bbox"))
    # Select 6-frame stride (contacts at 0 and 3: indices 0, 1, 2, 4, 5, 6)
    return [frames8[i] for i in (0, 1, 2, 4, 5, 6)]


def extract_flow_sprint_E() -> list[np.ndarray]:
    """Extracts 6 dynamic sprint frames from Flow Image 7 (f7e899b4.jpg, 8 East sprint poses)."""
    rgb = load_rgb(UP_DIR / "media_1795631268616_f7e899b4.jpg")
    bg = ehc.estimate_bg(rgb)
    cl = ehc.clean_crop_rgba(rgb, bg)
    px_step = 206.0 / float(ehc.TARGET_BODY_H)  # leaning sprint height 182 = 0.88 * 206 standing
    x_spans = [(12, 146), (147, 258), (262, 384), (385, 513), (514, 645), (646, 755), (760, 882), (883, 1012)]
    frames8 = []
    for i, (x0, x1) in enumerate(x_spans):
        pix = ehc.pixelize_rgba(cl[:, x0:x1], px_step=px_step)
        lift_dy = -4 if i in (0, 4) else 0  # subtle airborne flight lift on extended stride!
        frames8.append(ehc.place_in_cell(pix, dy=lift_dy, center_mode="bbox"))
    return [frames8[i] for i in (0, 1, 2, 4, 5, 6)]


def extract_flow_walk_SE() -> list[np.ndarray]:
    """Extracts 6 ultra-smooth 720p SE walk frames from walk_all (frames 5, 10, 15, 20, 25, 30)."""
    sample_idxs = [5, 10, 15, 20, 25, 30]
    f0 = load_rgb(MP4_WALK_DIR / "f_0005.png")
    bg = ehc.estimate_bg(f0)
    # Standing height in 720p walk_all is ~624px -> px_step = 624 / 186.0 = 3.355
    px_step = 624.0 / float(ehc.TARGET_BODY_H)
    out = []
    for idx in sample_idxs:
        rgb = load_rgb(MP4_WALK_DIR / f"f_{idx:04d}.png")[25:705, 460:820]
        cl = ehc.clean_crop_rgba(rgb, bg)
        pix = ehc.pixelize_rgba(cl, px_step=px_step)
        out.append(ehc.place_in_cell(pix))
    return out


def extract_flow_sneak_bases() -> dict[int, np.ndarray]:
    """Extracts genuine crouched stealth poses for SE (pose 0) and E (pose 1) from Flow Image 10."""
    rgb = load_rgb(UP_DIR / "media_1795631488833_410c9158.jpg")
    bg = ehc.estimate_bg(rgb)
    cl = ehc.clean_crop_rgba(rgb, bg)
    px_step = 264.0 / float(ehc.TARGET_BODY_H)
    se_pix = ehc.pixelize_rgba(cl[:, 24:185], px_step=px_step)
    e_pix = ehc.pixelize_rgba(cl[:, 188:338], px_step=px_step)
    return {
        1: ehc.place_in_cell(se_pix),
        0: ehc.place_in_cell(e_pix),
    }


def split_cosmetic_layers(sheet: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Splits a full High-Res sheet into (base_body, outfit_default, hair_front, hair_back)
    so `AppearanceComponent` + `hit_flash.gdshader` support salon hair & outfit dye-tinting cleanly!"""
    H, W, _ = sheet.shape
    r = sheet[..., 0].astype(np.int32)
    g = sheet[..., 1].astype(np.int32)
    b = sheet[..., 2].astype(np.int32)
    a = sheet[..., 3]
    op = a > 0

    ys_local = np.arange(H)[:, None] % CH
    lum = 0.299 * r + 0.587 * g + 0.114 * b

    # Hair pixels: pure cool silver-lavender palette (#ffffff..#463c68) OR golden hairpin (y < 60, gold color)!
    is_gold = op & (r > b + 34) & (g > b + 14) & (r > 105)
    is_hair_pin = is_gold & (ys_local < 58)
    is_silver = op & (b >= r - 4) & ((b - g) < 34) & (lum > 76.0) & (ys_local < 118)
    is_hair = is_silver | is_hair_pin

    # Split hair into front (crown/bangs/sidelocks y_local < 54) and back (lower cascading waves y_local >= 54)
    hair_front_mask = is_hair & (ys_local < 54)
    hair_back_mask = is_hair & (ys_local >= 54)

    # Skin & eyes stay on base_body (so outfit dye NEVER tints her face, cleavage, arms, hands, or thighs!)
    is_skin = op & (~is_gold) & (r > g + 12) & (g >= b - 8) & (lum > 88.0)
    is_eye = op & (ys_local >= 24) & (ys_local <= 50) & (b > g + 18)

    outfit_mask = op & (~is_hair) & (~is_skin) & (~is_eye)

    # Base sheet keeps full body/skin/eyes + neutral dark silhouette under outfit so standalone TEXTURE also renders whole!
    base = sheet.copy()
    outfit = np.zeros_like(sheet)
    outfit[outfit_mask] = sheet[outfit_mask]

    hf = np.zeros_like(sheet)
    hf[hair_front_mask] = sheet[hair_front_mask]

    hb = np.zeros_like(sheet)
    hb[hair_back_mask] = sheet[hair_back_mask]

    # Where hair_back sits, clear base alpha only if not covered by outfit/skin so hair_back_tex shows + dyes!
    only_hb = hair_back_mask & (~outfit_mask) & (~is_skin)
    base[only_hb] = (0, 0, 0, 0)

    return base, outfit, hf, hb


if __name__ == "__main__":
    masters = [
        np.asarray(Image.open(MASTER_DIR / f"master_{s}.png").convert("RGBA"))
        for s in SECTORS
    ]

    walk_E = extract_flow_walk_E()
    sprint_E = extract_flow_sprint_E()
    walk_SE = extract_flow_walk_SE()
    sneak_bases = extract_flow_sneak_bases()

    sheet = np.zeros((ROWS * CH, COLS * CW, 4), dtype=np.uint8)

    def put_cell(row: int, col: int, cell: np.ndarray) -> None:
        sheet[row * CH:(row + 1) * CH, col * CW:(col + 1) * CW] = cell

    for s in range(8):
        m = masters[s]
        # 1. Walk cycle: cols 0..5 (6 frames, contacts at 0 and 3)
        for k in range(6):
            if s == 0:
                c_walk = walk_E[k]
            elif s == 1:
                c_walk = walk_SE[k]
            else:
                c_walk = animate_from_master(m, s, k * (2.0 * math.pi / 6.0), "walk")
            put_cell(s, k, c_walk)

        # 2. Sprint cycle: cols 6..11 (6 frames)
        for k in range(6):
            if s == 0:
                c_spr = sprint_E[k]
            else:
                c_spr = animate_from_master(m, s, k * (2.0 * math.pi / 6.0), "sprint")
            put_cell(s, 6 + k, c_spr)

        # 3. Idle breathing loop: cols 12..15 (4 frames)
        for k in range(4):
            c_idle = m.copy() if k == 0 else animate_from_master(m, s, k * (2.0 * math.pi / 4.0), "idle")
            put_cell(s, 12 + k, c_idle)

        # 4. Jog cycle: cols 16..21 (6 frames)
        for k in range(6):
            c_jog = animate_from_master(m, s, k * (2.0 * math.pi / 6.0), "jog")
            put_cell(s, 16 + k, c_jog)

        # 5. Crouched / Sneak rows (row = 8 + s):
        sn_base = sneak_bases.get(s, None)
        for k in range(6):
            ph = k * (2.0 * math.pi / 6.0)
            c_sn = animate_from_master(sn_base, s, ph, "walk") if sn_base is not None else animate_from_master(m, s, ph, "sneak")
            put_cell(8 + s, k, c_sn)
            put_cell(8 + s, 6 + k, c_sn)
            put_cell(8 + s, 16 + k, c_sn)
        for k in range(4):
            ph = k * (2.0 * math.pi / 4.0)
            c_sn_idle = animate_from_master(sn_base, s, ph, "idle") if sn_base is not None else animate_from_master(m, s, 0.0, "sneak")
            put_cell(8 + s, 12 + k, c_sn_idle)

    base_s, outfit_s, hf_s, hb_s = split_cosmetic_layers(sheet)
    blood_s = ehc.make_blood_map(sheet, CW, CH, FY)

    Image.fromarray(base_s, "RGBA").save(CHAR_DIR / "player.png")
    Image.fromarray(blood_s, "RGBA").save(CHAR_DIR / "player_blood.png")
    (CHAR_DIR / "outfits" / "default").mkdir(parents=True, exist_ok=True)
    (CHAR_DIR / "hair" / "default").mkdir(parents=True, exist_ok=True)
    Image.fromarray(outfit_s, "RGBA").save(CHAR_DIR / "outfits" / "default" / "player.png")
    Image.fromarray(hf_s, "RGBA").save(CHAR_DIR / "hair" / "default" / "player.png")
    Image.fromarray(hb_s, "RGBA").save(CHAR_DIR / "hair" / "default" / "player_back.png")

    # Save a quick diagnostic preview of E Walk, E Sprint, SE Walk, S Idle, SE Sneak!
    diag = Image.new("RGBA", (CW * 6, CH * 4), (38, 34, 54, 255))
    for k in range(6):
        diag.alpha_composite(Image.fromarray(sheet[0:CH, k*CW:(k+1)*CW], "RGBA"), (k * CW, 0))
        diag.alpha_composite(Image.fromarray(sheet[0:CH, (6+k)*CW:(7+k)*CW], "RGBA"), (k * CW, CH))
        diag.alpha_composite(Image.fromarray(sheet[CH:2*CH, k*CW:(k+1)*CW], "RGBA"), (k * CW, 2 * CH))
        diag.alpha_composite(Image.fromarray(sheet[9*CH:10*CH, k*CW:(k+1)*CW], "RGBA"), (k * CW, 3 * CH))
    diag.save(MASTER_DIR / "locomotion_preview.png")
    print("Built High-Res player.png (3168x3456) + blood + default cosmetic layers!")
