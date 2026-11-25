"""Build High-Res (206x306 per cell -> 1030x1224 sheet) Ellie Dialogue Portrait & Expressions
(`assets/ui/ellie_dialogue_v4.png`) from Google Flow Image 13, with exact chin-to-crown face
registration AND crisp, contrast-preserved pixel-art mouths on EVERY expression and blink row!
"""
from __future__ import annotations
import sys
from pathlib import Path
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ellie_hires_core as ehc

ROOT = Path(__file__).resolve().parent.parent
UI_DIR = ROOT / "assets" / "ui"
UP_DIR = Path(r"C:\Users\levin\.gemini\antigravity\brain\84023b20-37a1-43d7-afb3-2439c9b015a4\.user_uploaded")
PREVIEW_DIR = Path(r"C:\Users\levin\.gemini\antigravity\brain\84023b20-37a1-43d7-afb3-2439c9b015a4\scratch\hires_master")

PW, PH = 206, 306


def pixelize_face_crisp(src_rgba: np.ndarray, px_step: float) -> np.ndarray:
    """Detail-preserving nearest/contrast sampler for small facial features (eyes, brows, mouths, teeth!)
    so thin 1-2px mouth lines NEVER get averaged away by a 3x3 median filter!"""
    ys, xs = np.nonzero(src_rgba[..., 3] > 128)
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    crop = src_rgba[y0:y1, x0:x1]
    sh, sw, _ = crop.shape
    tw = max(1, int(round(sw / px_step)))
    th = max(1, int(round(sh / px_step)))

    # Sample 3x3 subpixels, but preserve darkest/high-contrast line features (lashes, mouth line, teeth)!
    offs = (-0.28, 0.0, 0.28)
    samples = []
    for oy in offs:
        sy = np.clip(((np.arange(th) + 0.5 + oy) * px_step).astype(np.int32), 0, sh - 1)
        for ox in offs:
            sx = np.clip(((np.arange(tw) + 0.5 + ox) * px_step).astype(np.int32), 0, sw - 1)
            samples.append(crop[sy[:, None], sx[None, :]])
    stack = np.stack(samples, axis=2)  # [th, tw, 9, 4]
    op = stack[..., 3] > 128
    solid = op.sum(axis=2) >= 4

    # Center pixel by default, but if a dark feature (lash/mouth outline) or bright white (teeth/eye glint) hits >=2 subpixels, keep it!
    center_rgb = stack[:, :, 4, :3]
    lum_s = 0.299 * stack[..., 0] + 0.587 * stack[..., 1] + 0.114 * stack[..., 2]
    lum_s_op = np.where(op, lum_s, 180.0)
    min_k = np.argmin(lum_s_op, axis=2)
    min_rgb = np.take_along_axis(stack[..., :3], min_k[:, :, None, None], axis=2)[:, :, 0, :]
    min_lum = np.min(lum_s_op, axis=2)
    cen_lum = lum_s[:, :, 4]

    # Preserve crisp dark mouth/brow/lash lines when noticeably darker than surrounding skin!
    use_dark = (cen_lum - min_lum) > 26.0
    chosen_rgb = np.where(use_dark[..., None], min_rgb, center_rgb)

    # Quantize to 44-color Master Palette with lip/rose boost so subtle rose lips map to #b86472 / #9c5c5e / #462c3e instead of flat skin!
    lab = ehc._srgb_to_oklab(chosen_rgb)
    d2 = np.sum((lab[:, :, None, :] - ehc.PAL_LAB[None, None, :, :]) ** 2, axis=-1)
    r_c = chosen_rgb[..., 0].astype(np.int32)
    g_c = chosen_rgb[..., 1].astype(np.int32)
    b_c = chosen_rgb[..., 2].astype(np.int32)

    is_gold = (r_c > b_c + 34) & (g_c > b_c + 16) & (r_c > 115)
    d2 = np.where(is_gold[..., None] & (ehc.PAL_MAT == 7)[None, None, :], d2 * 0.55, d2)

    # Boost rose-lip / mouth-line sensitivity
    is_lip_like = (r_c > g_c + 36) & (r_c < 225) & (g_c < 165) & (b_c < 160)
    lip_mask = np.isin(ehc.PAL_MAT, [8])[None, None, :] | (np.arange(len(ehc.PAL_MAT)) == 15)[None, None, :]
    d2 = np.where(is_lip_like[..., None] & lip_mask, d2 * 0.65, d2)

    lum = 0.299 * r_c + 0.587 * g_c + 0.114 * b_c
    is_cool_silver = (b_c >= r_c - 6) & (lum > 78) & ((b_c - g_c) < 38)
    d2 = np.where(is_cool_silver[..., None] & np.isin(ehc.PAL_MAT, [2, 6, 7, 8])[None, None, :], d2 + 10.0, d2)

    best_idx = np.argmin(d2, axis=-1)
    res = np.zeros((th, tw, 4), dtype=np.uint8)
    res[solid, :3] = ehc.PAL_RGB[best_idx][solid]
    res[solid, 3] = 255
    return res


def find_choker_top_and_face_cx(rgba: np.ndarray) -> tuple[int, int, int]:
    """Finds crown_top_y, choker_top_y (dark horizontal band under chin!), and face_cx for exact registration!"""
    ys, _ = np.nonzero(rgba[..., 3] > 0)
    crown_y = int(ys.min())
    # Scan y = crown_y + 25 .. crown_y + 110 for the dark black choker band (low lum < 45 across >=6 cols near center)
    H, W, _ = rgba.shape
    probe_y = min(H - 1, crown_y + int(0.20 * (ys.max() - crown_y)))
    pxs = np.nonzero(rgba[probe_y, :, 3] > 0)[0]
    cx_rough = int(round(0.5 * (pxs.min() + pxs.max()))) if len(pxs) > 0 else W // 2

    choker_y = crown_y + 78
    for y in range(crown_y + 45, min(H, crown_y + 105)):
        band = rgba[y, max(0, cx_rough - 12) : min(W, cx_rough + 16)]
        op = band[..., 3] > 0
        lum = 0.299 * band[..., 0] + 0.587 * band[..., 1] + 0.114 * band[..., 2]
        if int((op & (lum < 48)).sum()) >= 7:
            choker_y = y
            break

    # Measure warm skin horizontal center halfway between crown and choker
    mid_y = (crown_y + choker_y) // 2 + 6
    row = rgba[mid_y]
    skin = (row[:, 3] > 0) & (row[:, 0].astype(int) > row[:, 2].astype(int) + 12)
    sxs = np.nonzero(skin)[0]
    face_cx = int(round(0.5 * (sxs.min() + sxs.max()))) if len(sxs) >= 4 else cx_rough
    return crown_y, choker_y, face_cx


def stamp_clean_mouth(cell: np.ndarray, cx: int, chin_y: int, kind: str) -> None:
    """Ensures every single expression has a crystal-clear, natural pixel-art mouth right above the chin!"""
    # Mouth sits ~8px above choker_y (chin sits ~3px above choker_y)
    my = chin_y - 8
    mx = cx + 2  # 3/4 view faces slightly right, so mouth centerline is +2px right of head center!
    DARK_LIP = (0x62, 0x41, 0x54, 255)
    ROSE_LIP = (0x9C, 0x5C, 0x5E, 255)
    SOFT_LIP = (0xB8, 0x64, 0x72, 255)
    SHAD_LIP = (0xC9, 0x86, 0x7A, 255)
    TEETH    = (0xFF, 0xF0, 0xE4, 255)
    MOUTH_IN = (0x46, 0x2C, 0x3E, 255)

    if kind == "calm":
        # Gentle natural closed rose lips with subtle upturned corners
        for dx, col in [(-3, SHAD_LIP), (-2, ROSE_LIP), (-1, ROSE_LIP), (0, ROSE_LIP), (1, ROSE_LIP), (2, SHAD_LIP)]:
            cell[my, mx + dx] = col
        cell[my - 1, mx - 3] = SHAD_LIP
        cell[my - 1, mx + 2] = SHAD_LIP
        cell[my + 1, mx - 1] = SHAD_LIP
        cell[my + 1, mx]     = SHAD_LIP
    elif kind == "smile":
        # Warm happy curved smile
        for dx in (-2, -1, 0, 1):
            cell[my, mx + dx] = ROSE_LIP
        cell[my - 1, mx - 3] = ROSE_LIP
        cell[my - 1, mx - 2] = SHAD_LIP
        cell[my - 1, mx + 2] = ROSE_LIP
        cell[my - 2, mx - 4] = SHAD_LIP
        cell[my - 2, mx + 3] = SHAD_LIP
        cell[my + 1, mx - 1] = SOFT_LIP
        cell[my + 1, mx]     = SOFT_LIP
    elif kind == "combat":
        # Fierce clenched/grit teeth expression matching Image 13 COMBAT!
        for dx in range(-3, 3):
            cell[my - 2, mx + dx] = DARK_LIP
            cell[my + 1, mx + dx] = DARK_LIP
        for dx in range(-2, 2):
            cell[my - 1, mx + dx] = TEETH
            cell[my, mx + dx]     = TEETH
        cell[my - 1, mx - 3] = DARK_LIP
        cell[my, mx - 3]     = DARK_LIP
        cell[my - 1, mx + 2] = DARK_LIP
        cell[my, mx + 2]     = DARK_LIP
    elif kind == "surprised":
        # Cute surprised parted 'o' mouth matching Image 13 SURPRISED!
        for dx in (-1, 0, 1):
            cell[my - 2, mx + dx] = DARK_LIP
            cell[my + 1, mx + dx] = ROSE_LIP
        for dy in (-1, 0):
            cell[my + dy, mx - 2] = DARK_LIP
            cell[my + dy, mx - 1] = MOUTH_IN
            cell[my + dy, mx]     = SOFT_LIP if dy == 0 else MOUTH_IN
            cell[my + dy, mx + 1] = MOUTH_IN
            cell[my + dy, mx + 2] = DARK_LIP
    elif kind == "worried":
        # Empathetic worried slight frown matching Image 13 WORRIED!
        for dx in (-2, -1, 0, 1):
            cell[my - 1, mx + dx] = ROSE_LIP
        cell[my, mx - 3] = ROSE_LIP
        cell[my, mx + 2] = ROSE_LIP
        cell[my, mx - 2] = SHAD_LIP
        cell[my, mx + 1] = SHAD_LIP
    elif kind == "serene":
        # Peaceful serene soft closed lips matching Image 13 SERENE!
        for dx, col in [(-2, SHAD_LIP), (-1, ROSE_LIP), (0, ROSE_LIP), (1, ROSE_LIP), (2, SHAD_LIP)]:
            cell[my, mx + dx] = col
        cell[my - 1, mx - 3] = SHAD_LIP
        cell[my + 1, mx]     = SHAD_LIP


def make_wounded_variant(cell_rgba: np.ndarray) -> np.ndarray:
    out = cell_rgba.copy()
    op = out[..., 3] > 0
    rgb = out[..., :3].astype(np.float32)
    lum = (0.30 * rgb[..., 0] + 0.59 * rgb[..., 1] + 0.11 * rgb[..., 2])[..., None]
    pale = np.concatenate([lum * 0.92, lum * 0.95, lum * 1.04], axis=-1)
    mixed = rgb * 0.68 + pale * 0.32
    out[op, :3] = np.clip(np.rint(mixed[op]), 0, 255).astype(np.uint8)
    return out


if __name__ == "__main__":
    im = np.asarray(Image.open(UP_DIR / "media_1795631556049_b26242e1.jpg").convert("RGB"))
    bg = ehc.estimate_bg(im)

    # 1. Main head-to-hip 3/4 portrait on left
    main_clean = ehc.clean_crop_rgba(im[34:576, 10:336, :], bg, strip_ground_shadow=False, min_comp_area=100)
    ys_m, _ = np.nonzero(main_clean[..., 3] > 128)
    px_step_main = (int(ys_m.max()) - int(ys_m.min()) + 1) / 298.0
    main_pix = pixelize_face_crisp(main_clean, px_step=px_step_main)

    base_cell = np.zeros((PH, PW, 4), dtype=np.uint8)
    mh, mw, _ = main_pix.shape
    ox = max(0, (PW - mw) // 2)
    oy = PH - mh
    w_fit, h_fit = min(PW - ox, mw), min(PH - oy, mh)
    base_cell[max(0, oy) : max(0, oy) + h_fit, ox : ox + w_fit] = main_pix[:h_fit, :w_fit]

    b_crown, b_choker, b_fcx = find_choker_top_and_face_cx(base_cell)
    b_head_span = b_choker - b_crown
    print(f"Base portrait: crown={b_crown}, choker={b_choker} (span={b_head_span}), face_cx={b_fcx}")

    # Ensure crisp calm mouth on base_cell too!
    calm_cell = base_cell.copy()
    stamp_clean_mouth(calm_cell, b_fcx, b_choker, "calm")

    # 2. Extract 5 expression busts on right (0=SMILE, 1=COMBAT, 2=SURPRISED, 3=WORRIED, 4=SERENE)
    expr_strip = ehc.clean_crop_rgba(im[176:336, 325:995, :], bg, strip_ground_shadow=False, min_comp_area=60)
    boxes = ehc.split_strip_bboxes(expr_strip, min_w=50)
    mouth_kinds = ["smile", "combat", "surprised", "worried", "serene"]

    expr_cells: list[np.ndarray] = []
    serene_eyes_patch: tuple[np.ndarray, int, int] | None = None

    for i, (bx0, by0, bx1, by1) in enumerate(boxes[:5]):
        sub = expr_strip[by0:by1, bx0:bx1]
        # First measure crown-to-choker in raw sub to compute exact scale matching b_head_span!
        r_crown, r_choker, _ = find_choker_top_and_face_cx(sub)
        # Fallback using sub height ratio if choker in raw is scaled ~1.82x
        step_e = max(1.2, (r_choker - r_crown) / float(b_head_span)) if (r_choker - r_crown) > 40 else (sub.shape[0] / 95.0)
        epix = pixelize_face_crisp(sub, px_step=step_e)
        e_crown, e_choker, e_fcx = find_choker_top_and_face_cx(epix)

        variant = base_cell.copy()
        gx = b_fcx - e_fcx
        gy = b_choker - e_choker  # Lock exact chin/choker height so mouth & eyes align to the pixel!!

        # Graft full inner face from forehead down to chin (b_crown + 18 .. b_choker - 2)!
        eh_p, ew_p, _ = epix.shape
        for fy in range(max(0, b_crown + 18), min(PH, b_choker - 1)):
            sy_e = fy - gy
            if not (0 <= sy_e < eh_p):
                continue
            for fx in range(max(0, b_fcx - 20), min(PW, b_fcx + 24)):
                sx_e = fx - gx
                if 0 <= sx_e < ew_p and epix[sy_e, sx_e, 3] > 0 and variant[fy, fx, 3] > 0:
                    # Only graft skin, eyes, brows, mouth (skip outer hair locks so hair stays 100% seamless!)
                    vr, vg, vb = int(variant[fy, fx, 0]), int(variant[fy, fx, 1]), int(variant[fy, fx, 2])
                    is_base_hair = (vb >= vr - 4) and (0.3 * vr + 0.59 * vg + 0.11 * vb > 135)
                    if not is_base_hair:
                        variant[fy, fx] = epix[sy_e, sx_e]

        # Stamp razor-sharp expression-matched pixel-art mouth!
        stamp_clean_mouth(variant, b_fcx, b_choker, mouth_kinds[i])
        expr_cells.append(variant)

    # For Row 1 (closed-eye blink row): close the eyes cleanly using SERENE's upper eye region while KEEPING each column's own mouth!
    blink_source = expr_cells[4]
    row0 = [calm_cell, expr_cells[0], expr_cells[1], expr_cells[2], expr_cells[3]]
    row1 = []
    for col_cell in row0:
        b_var = col_cell.copy()
        # Copy closed-eye band (b_crown + 28 .. b_choker - 13) from serene!
        y_eye0, y_eye1 = b_crown + 28, b_choker - 13
        x_eye0, x_eye1 = max(0, b_fcx - 20), min(PW, b_fcx + 24)
        b_var[y_eye0:y_eye1, x_eye0:x_eye1] = blink_source[y_eye0:y_eye1, x_eye0:x_eye1]
        row1.append(b_var)

    row2 = [make_wounded_variant(expr_cells[3]), make_wounded_variant(calm_cell), make_wounded_variant(expr_cells[1]), make_wounded_variant(expr_cells[2]), make_wounded_variant(expr_cells[3])]
    row3 = [make_wounded_variant(c) for c in row1]

    sheet = np.zeros((PH * 4, PW * 5, 4), dtype=np.uint8)
    for r_i, row_list in enumerate([row0, row1, row2, row3]):
        for c_i, cell in enumerate(row_list):
            sheet[r_i * PH : (r_i + 1) * PH, c_i * PW : (c_i + 1) * PW] = cell

    Image.fromarray(sheet, "RGBA").save(UI_DIR / "ellie_dialogue_v4.png")
    # Save zoomed face-and-mouth inspection strip so we verify every mouth at 2x!
    face_zoom = Image.new("RGBA", (110 * 2 * 5, 110 * 2 * 2), (24, 20, 34, 255))
    for r_i in range(2):
        for c_i in range(5):
            cell_im = Image.fromarray(sheet[r_i * PH : (r_i + 1) * PH, c_i * PW : (c_i + 1) * PW], "RGBA")
            crop_f = cell_im.crop((b_fcx - 55, b_crown, b_fcx + 55, b_crown + 110)).resize((220, 220), Image.NEAREST)
            face_zoom.alpha_composite(crop_f, (c_i * 220, r_i * 220))
    face_zoom.save(PREVIEW_DIR / "dialogue_mouths_zoom2x.png")
    print("Rebuilt ellie_dialogue_v4.png with crisp expression-matched mouths!")
