"""Clean pixel eyes for Ellie's sheets (and no painted mouth).

The ellipsoid renderer paints her eyes as decals on the 3D head. At 48 x 56 px they came out as smeared, uneven violet blobs that
changed shape from frame to frame (a dark bar on the head's edge in the three-quarter views, one eye bigger than the other, a
crooked lid, the eyes drifting apart and together). This pass removes the blobs and the painted mouth (skin where they were; the
decal's violet outline becomes skin outline) and draws one fixed, slim pixel eye per visible eye (approved look "A", 2026-11-12):

    D    D = lash/lid (darkest eye colour)
    I    I = iris

WHERE comes from the model (`stamp`): art_hero3d puts both eye centres and their looking directions on the head (`Model.eyes`,
`face_eyes`). An eye is drawn when it looks at the camera (facing > FACING_MIN): front and three-quarter views show two, profiles
one, back views none. Both share the row of the nearer eye (a turned head's far eye may sit one row higher, as the perspective puts it) and stand a
fixed distance apart: 2 skin pixels between them from the
front, 1 when the head is turned (SEP_FRONT decides). In a profile the eye is moved off the head's edge. The iris is drawn only on
face (the fringe still covers it); its lash may lie under the fringe's tip (it reads as the fringe's shadow). The silhouette never
changes (the blood and jewellery maps stay valid).

art_hero3d.frame() runs it on every frame it renders (only while the eye ramp is Ellie's). For finished sheets:
    py -3 tools/hero_face.py            (all assets/characters/player*.png colour sheets, in place: the sheets of
                                         art_hero_jewelry.sheets(), combo, cast, drink and feed by the model, the others by `tidy`, a guess from the image)
    py -3 tools/hero_face.py a.png ...  (just these)
Run it on freshly rendered (or the original) sheets.
"""
import sys
from collections import Counter
from pathlib import Path

import numpy as np

EYE = [(0x2a, 0x1c, 0x52), (0x5f, 0x3b, 0xc9), (0xa7, 0x7b, 0xff), (0xef, 0xe6, 0xff)]  # = art_hero3d RAMPS[EYE]
SKIN = [(0xd2, 0xa2, 0x9c), (0xef, 0xc3, 0xb6), (0xfa, 0xdf, 0xd2), (0xff, 0xf2, 0xe8),  # current porcelain-rose skin
        (0xd7, 0x9a, 0x88), (0xef, 0xc0, 0xa8), (0xf9, 0xdc, 0xc6), (0xff, 0xf1, 0xe4),  # legacy skin (for standalone re-runs)
        (0xd5, 0x8a, 0x86), (0xe5, 0xa3, 0x9b), (0xf2, 0xba, 0xb0), (0xf8, 0xcf, 0xc6)]  # blush
HAIR = [(0x8f, 0x84, 0xc2), (0xbd, 0xb3, 0xe4), (0xe9, 0xe3, 0xf7), (0xff, 0xfa, 0xf0)]  # = art_hero3d RAMPS[HAIR]
MOUTH = [(0x84, 0x40, 0x5a), (0xb2, 0x58, 0x73), (0xd9, 0x8a, 0xa0), (0xf0, 0xb2, 0xc2)]  # = art_hero3d RAMPS[MOUTH]
LASH, IRIS = EYE[0], EYE[1]
STAMP = [LASH, IRIS]  # one column, top to bottom
GAP = 2  # skin pixels between the two eyes of a face seen from the front
GAP_TURNED = 1  # ... of a face turned three-quarters (the far eye near the head's edge): foreshortened
FACING_MIN = 0.12  # an eye is drawn when it looks at the camera at least this much (profile far eye about -0.4, three-quarter far eye 0.28)
SEP_FRONT = 2.45  # projected distance (px) between the eye centres from which the face counts as seen from the front


def _ink(c, k=0.55):  # = art_hero3d.ink_color
    return (int(c[0] * k), int(c[1] * k * 0.95), int(c[2] * k))


SKIN_INK = (0x10, 0x07, 0x16)
FACE_INK = [_ink(EYE[0]), _ink(MOUTH[0]), _ink(SKIN[4], 0.5), _ink(SKIN[8]), (0x52, 0x36, 0x44)]  # outline pixels of eye, mouth and blush decals -> crisp silhouette ink


def _mask(rgb: np.ndarray, colors) -> np.ndarray:
    m = np.zeros(rgb.shape[:2], bool)
    for c in colors:
        m |= np.all(rgb == np.array(c, np.uint8), axis=-1)
    return m


def _clusters(mask: np.ndarray) -> list[list[tuple[int, int]]]:
    """4-connected groups of eye pixels."""
    seen = np.zeros_like(mask)
    out = []
    h, w = mask.shape
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]:
            continue
        stack, group = [(y, x)], []
        seen[y, x] = True
        while stack:
            cy, cx = stack.pop()
            group.append((cy, cx))
            for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        out.append(group)
    return out


def _skin_fill(rgb, skin, pts, h, w):
    around = Counter()
    for y, x in pts:
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (2, 0), (-2, 0)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and skin[ny, nx]:
                around[tuple(int(v) for v in rgb[ny, nx])] += 1
    return around.most_common(1)[0][0] if around else SKIN[2]


def _near_skin(skin, pts, h, w):
    return any(0 <= y + dy < h and 0 <= x + dx < w and skin[y + dy, x + dx]
               for y, x in pts for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)))


def _clean(arr: np.ndarray):
    """Removes the mouth and the eye blobs (skin where they were), turns their outlines into skin outline.
    Returns (arr, face): face = pixels that are face (skin or old eye) and may carry an eye."""
    arr = arr.copy()
    rgb = arr[..., :3].copy()
    alpha = arr[..., 3]
    h, w = alpha.shape
    solid = alpha == 255
    skin = _mask(rgb, SKIN) & solid
    eye = _mask(rgb, EYE) & solid
    face = skin | eye
    for colors, limit in ((MOUTH, 8), (EYE, 12)):
        m = _mask(rgb, colors) & solid
        for g in _clusters(m):
            if len(g) <= limit and _near_skin(skin, g, h, w):
                fill = _skin_fill(rgb, skin, g, h, w)
                for y, x in g:
                    arr[y, x, :3] = fill
    arr[_mask(rgb, FACE_INK), :3] = SKIN_INK
    return arr, face


def stamp(arr: np.ndarray, eyes) -> np.ndarray:
    """Faceless stylized heroine: clean any stray decal pixels and leave smooth shaded porcelain skin (no eyes, no mouth)."""
    out, _face = _clean(arr)
    return out


def tidy(arr: np.ndarray, sector=None) -> np.ndarray:
    """Faceless stylized heroine: clean any stray eye/mouth pixels and leave smooth shaded porcelain skin."""
    out, _face = _clean(arr)
    return out


def tidy_rows(rows, eyes=None):
    """For art_hero3d.to_pixels: a list of rows of RGBA tuples in, the same out (eyes from art_hero3d.face_eyes, else a guess)."""
    arr = np.asarray(rows, dtype=np.uint8)
    out = stamp(arr, eyes) if eyes is not None else tidy(arr)
    return [[tuple(int(v) for v in out[y, x]) for x in range(out.shape[1])] for y in range(out.shape[0])]


# sheets whose rows are the eight facings (E SE S SW W NW N NE), repeated (the main sheet has 16 rows: standing, crouched)
SECTOR_ROWS = {"player": 16, "player_attack": 8, "player_cast": 8, "player_climb": 8, "player_combo": 8, "player_drink": 8,
               "player_eat": 8, "player_feed": 8, "player_fish": 8, "player_heavy": 8, "player_pick": 8, "player_pull": 8,
               "player_rest": 8, "player_sit": 8, "player_standby": 8, "player_step": 8, "player_stumble": 8, "player_swim": 8,
               "player_swim_under": 8, "player_touch": 8}


FRAME_W = {"player_swim": 64, "player_swim_under": 64, "player_climb": None, "player_rest": None, "player_sit": None, "player_stumble": None}


def _borrow(strip: np.ndarray, fw: int, sector: int) -> None:
    return


# animation cycles (column ranges) of a sheet: one facing shows the same number of eyes through a whole cycle
CYCLES = {"player": [(0, 6), (6, 12), (12, 16), (16, 22)]}


def _even_cycles(strip: np.ndarray, fw: int, sector: int, cycles) -> None:
    return


def tidy_sheet(arr: np.ndarray, name: str) -> np.ndarray:
    rows = SECTOR_ROWS.get(name)
    if not rows:
        return tidy(arr)
    fh = arr.shape[0] // rows
    fw = FRAME_W.get(name, 48)
    out = arr.copy()
    for r in range(rows):
        strip = tidy(arr[r * fh:(r + 1) * fh], r % 8)
        if fw:
            _borrow(strip, fw, r % 8)
            if name in CYCLES:
                _even_cycles(strip, fw, r % 8, CYCLES[name])
        out[r * fh:(r + 1) * fh] = strip
    return out


MODELS = {}


def model_sheets():
    """{sheet stem: (frame w, frame h, cols, [frame() args in sprite order])} of the sheets whose frames we can rebuild as models."""
    import art_hero3d as hero
    import art_hero_jewelry as jewel
    import art_hero_cast as cast
    import art_hero_combo as combo
    names = {"main": "player"}
    out = {names.get(name, "player_" + name): (hero.FW, hero.FH, cols, frames) for name, (cols, rows, frames) in jewel.sheets().items()}

    def legs(sector, pose, v):  # leg variant 0 planted, 1-6 the walk cycle's phases (as the attack sheets)
        return (sector, 0.0, "attack", False, pose) if v == 0 else (sector, (v - 1) / hero.WALK_FRAMES, "walk", False, dict(pose, pz=0.0))

    # same frame order as the generators (art_hero_combo.render_frames, art_hero_cast.render, art_hero3d.pick_sheet)
    frames = [legs(sector, pose, v) for sector in range(8) for block in range(combo.BLOCKS) for v in range(hero.ATTACK_LEGS) for pose in combo.COMBO_POSES[block]]
    out["player_combo"] = (hero.FW, hero.FH, len(frames) // 8, frames)
    frames = [(sector, 0.0, "attack", False, hero.timeline_pose(keys, (i + 0.5) / hero.PICK_FRAMES)) for sector in range(8) for _n, keys in cast.CLIPS for i in range(hero.PICK_FRAMES)]
    out["player_cast"] = (hero.FW, hero.FH, len(frames) // 8, frames)
    for name, keys, variants in (("player_drink", hero.DRINK_KEYS, hero.ATTACK_LEGS), ("player_feed", hero.FEED_KEYS, 1)):
        frames = [legs(sector, hero.timeline_pose(keys, (i + 0.5) / hero.PICK_FRAMES), v) for sector in range(8) for v in range(variants) for i in range(hero.PICK_FRAMES)]
        out[name] = (hero.FW, hero.FH, len(frames) // 8, frames)
    return out


def eyes_of(args):
    import math
    import art_hero3d as hero
    sector, t, mode, crouch, pose = args
    yaw = math.pi / 2 - sector * math.pi / 4
    return hero.face_eyes(hero.build(t, mode, crouch, pose), yaw)


def stamp_sheet(arr: np.ndarray, fw: int, fh: int, cols: int, frames) -> np.ndarray:
    out = arr.copy()
    for i, args in enumerate(frames):
        r, c = divmod(i, cols)
        tile = arr[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw]
        out[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw] = stamp(tile, eyes_of(args))
    return out


def main(paths):
    from PIL import Image
    root = Path(__file__).resolve().parent.parent / "assets" / "characters"
    if not paths:
        paths = [p for p in sorted(root.glob("player*.png")) if not p.stem.endswith("_blood")]
    if not MODELS:
        MODELS.update(model_sheets())
    for p in paths:
        p = Path(p)
        im = np.array(Image.open(p).convert("RGBA"))
        if p.stem in MODELS:
            fw, fh, cols, frames = MODELS[p.stem]
            out = stamp_sheet(im, fw, fh, cols, frames)
        else:
            out = tidy_sheet(im, p.stem)
        changed = int((out != im).any(-1).sum())
        Image.fromarray(out, "RGBA").save(p)
        print(f"{p.name}: {changed} px")


if __name__ == "__main__":
    main(sys.argv[1:])
