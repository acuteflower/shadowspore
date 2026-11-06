"""Shared loaders for the world bake tools: the frozen map, the baked coast and a PNG codec (stdlib + numpy)."""
import json, struct, zlib
import numpy as np

W = 1100
CELL = 4


def load_png(path):
    """8-bit grey or RGBA PNG -> numpy array (h, w) or (h, w, 4)."""
    data = open(path, "rb").read()
    pos, idat, info = 8, b"", None
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            info = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    w, h, depth, ctype = info[0], info[1], info[2], info[3]
    assert depth == 8 and ctype in (0, 6), "only 8-bit grey or RGBA"
    bpp = 1 if ctype == 0 else 4
    raw = zlib.decompress(idat)
    stride = w * bpp
    out = np.zeros((h, stride), dtype=np.uint8)
    prev = np.zeros(stride, dtype=np.int32)
    p = 0
    for y in range(h):
        f = raw[p]
        line = np.frombuffer(raw, dtype=np.uint8, count=stride, offset=p + 1).astype(np.int32)
        p += 1 + stride
        if f == 0:
            cur = line
        elif f == 1:
            cur = line.copy()
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i - bpp]) & 255
        elif f == 2:
            cur = (line + prev) & 255
        elif f == 3:
            cur = line.copy()
            for i in range(stride):
                left = cur[i - bpp] if i >= bpp else 0
                cur[i] = (cur[i] + ((left + prev[i]) >> 1)) & 255
        else:
            cur = line.copy()
            for i in range(stride):
                a = cur[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 255
        out[y] = cur
        prev = cur
    return out.reshape(h, w) if bpp == 1 else out.reshape(h, w, 4)


def save_png(path, arr):
    """numpy uint8 array (h, w) grey, (h, w, 3) RGB or (h, w, 4) RGBA -> PNG."""
    arr = np.ascontiguousarray(arr, dtype=np.uint8)
    h, w = arr.shape[:2]
    ctype = {2: 0, 3: 2}.get(arr.ndim) if arr.ndim == 2 else {3: 2, 4: 6}[arr.shape[2]]
    rows = b"".join(b"\x00" + arr[y].tobytes() for y in range(h))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def load_map(path):
    """-> (map dict, region grid at CELL resolution as int array, start region id)."""
    d = json.load(open(path))
    g = W // CELL
    runs, flat = d["grid"], []
    for i in range(0, len(runs), 2):
        flat.extend([int(runs[i])] * int(runs[i + 1]))
    return d, np.array(flat, dtype=np.int32).reshape(g, g), int(d["start_region"])


def start_tile(d, grid):
    """Where the players spawn: the map's explicit "start", else the start region's anchor."""
    if "start" in d:
        return int(d["start"][0]), int(d["start"][1])
    return anchor(d, grid, int(d["start_region"]))


def anchor(d, grid, region):
    """The same tile RegionMap.anchor picks: the region's cell nearest to its centre."""
    cx, cy = d["regions"][region]["center"]
    ys, xs = np.nonzero(grid == region)
    px, py = (xs + 0.5) * CELL, (ys + 0.5) * CELL
    i = int(np.argmin((px - cx) ** 2 + (py - cy) ** 2))
    return int(px[i]), int(py[i])
