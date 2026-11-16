"""程序化像素贴图（numpy），规则与 Godot 端 pw_textures.gd 相同：
1. 只用调色板颜色及其两两混合；
2. 大面积用成片色块，细节用成簇的小笔触；
3. 结构线 1 像素，旁边 1 像素高光；
4. 32 texel / 米：一张 64px 贴图对应 2 米。
返回 HxWx3 的 float 数组（sRGB，0..1），行 0 是贴图顶端。
"""
import numpy as np

from . import style as S


def _rng(seed):
    return np.random.default_rng(seed)


def tile_noise(size, cells, rng):
    """可平铺的值噪声（双线性 + smoothstep）"""
    g = rng.random((cells, cells))
    x = np.arange(size) / (size / cells)
    i0 = np.floor(x).astype(int) % cells
    i1 = (i0 + 1) % cells
    t = x - np.floor(x)
    t = t * t * (3 - 2 * t)
    top = g[i0][:, i0] * (1 - t)[None, :] + g[i0][:, i1] * t[None, :]
    bot = g[i1][:, i0] * (1 - t)[None, :] + g[i1][:, i1] * t[None, :]
    return top * (1 - t)[:, None] + bot * t[:, None]


def _lerp(a, b, t):
    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    t = np.asarray(t, dtype=float)[..., None] if np.ndim(t) else t
    return a + (b - a) * t


def planks(cols, seed, size=64, plank_w=8):
    """竖向木板：cols = [亮, 主色, 暗, 缝]"""
    rng = _rng(seed)
    hi, base, dark, seam = (S.c(c) if isinstance(c, str) else c for c in cols)
    img = np.zeros((size, size, 3))
    mot = tile_noise(size, 4, rng)
    for px in range(0, size, plank_w):
        shade = _lerp(hi, base, rng.uniform(0.35, 1.0))
        joint = rng.integers(0, size) if rng.random() < 0.65 else -100
        for lx in range(plank_w):
            x = px + lx
            if x >= size:
                break
            col = _lerp(shade, dark, (mot[:, x] - 0.5) * 0.35)
            grain = rng.random(size) < 0.06
            col[grain] = _lerp(col[grain], dark, 0.35)
            if lx == 0:
                col[:] = seam
            elif lx == 1:
                col = _lerp(col, hi, 0.5)
            elif lx == plank_w - 1:
                col = _lerp(col, dark, 0.4)
            if joint >= 0 and lx > 0:
                col[joint % size] = seam
                col[(joint + 1) % size] = _lerp(col[(joint + 1) % size], hi, 0.4)
            img[:, x] = col
    return img


def shingles(cols, seed, size=64, row_h=8, sw=16):
    """瓦片屋顶（行 0 = 屋脊方向）：cols = [瓦唇高光, 主色A, 主色B, 缝]"""
    rng = _rng(seed)
    lip, a, b, seam = (S.c(c) for c in cols)
    img = np.zeros((size, size, 3))
    for row in range(size // row_h):
        off = (row % 2) * (sw // 2) + int(rng.integers(-2, 3))
        tiles = [_lerp(a, b, rng.random() * 0.45 if rng.random() < 0.88 else rng.uniform(0.75, 1.0)) for _ in range(size // sw + 1)]
        for ly in range(row_h):
            y = row * row_h + ly
            for x in range(size):
                xi = (x + off) % size
                lx = xi % sw
                col = np.array(tiles[(xi // sw) % len(tiles)])
                if ly == 0 or (lx == 0 and ly < row_h - 1):
                    col = np.array(seam)
                elif ly == 1:
                    col = _lerp(col, seam, 0.4)
                elif ly == row_h - 1:
                    col = _lerp(col, lip, 0.45)
                img[y, x] = col
    return img


def bricks(cols, seed, size=64, brick_w=16, row_h=8):
    """砖 / 石块：cols = [亮, 主色, 暗, 灰缝]"""
    rng = _rng(seed)
    hi, base, dark, mortar = (S.c(c) for c in cols)
    img = np.zeros((size, size, 3))
    mot = tile_noise(size, 8, rng)
    for row in range(size // row_h):
        off = (row % 2) * (brick_w // 2)
        shades = [_lerp(hi, dark, rng.uniform(0.2, 0.9)) for _ in range(size // brick_w + 1)]
        for ly in range(row_h):
            y = row * row_h + ly
            for x in range(size):
                xi = x + off
                lx = xi % brick_w
                col = _lerp(shades[(xi // brick_w) % len(shades)], dark, (mot[y, x] - 0.5) * 0.3)
                if ly == 0 or lx == 0:
                    col = np.array(mortar)
                elif ly == 1:
                    col = _lerp(col, hi, 0.45)
                elif ly == row_h - 1:
                    col = _lerp(col, mortar, 0.35)
                img[y, x] = col
    return img


def foliage(cols, seed, size=64, droop=False):
    """针叶 / 阔叶：cols = [底, 亮, 暗]；一簇簇亮笔触，下方一点阴影"""
    rng = _rng(seed)
    base, hi, dark = (S.c(c) if isinstance(c, str) else c for c in cols)
    n = tile_noise(size, 6, rng)
    img = np.where((n < 0.3)[..., None], _lerp(dark, base, 0.5), np.array(base))
    for gy in range(0, size, 5):
        for gx in range(0, size, 6):
            x = gx + (gy // 5 % 2) * 3 + int(rng.integers(-1, 2))
            y = gy + int(rng.integers(0, 2))
            pts = [(0, 0, hi), (0, 1, hi), (0, 2, _lerp(hi, base, 0.5)), (0, 3, dark), (1, 1, _lerp(hi, base, 0.5))] if droop else \
                [(0, 0, hi), (-1, 1, hi), (1, 1, hi), (-2, 2, _lerp(hi, base, 0.5)), (2, 2, _lerp(hi, base, 0.5)), (0, 2, dark)]
            for dx, dy, col in pts:
                img[(y + dy) % size, (x + dx) % size] = col
    return img


def mottle(cols, seed, size=32, threshold=0.6):
    """低频斑驳：cols = [底色, 斑色]"""
    rng = _rng(seed)
    a, b = (S.c(c) if isinstance(c, str) else c for c in cols)
    n = tile_noise(size, max(2, size // 8), rng)
    img = np.where((n > threshold + 0.06)[..., None], np.array(b), np.array(a))
    mid = (n > threshold) & (n <= threshold + 0.06)
    img[mid] = _lerp(a, b, 0.5)
    return img


def stripes(cols, seed, size=64, width=8):
    """帆布条纹（集市摊位顶棚）：cols = [颜色1, 颜色2]，带一点布纹"""
    rng = _rng(seed)
    a, b = (S.c(c) for c in cols)
    img = np.zeros((size, size, 3))
    for x in range(size):
        img[:, x] = a if (x // width) % 2 == 0 else b
    weave = rng.random((size, size)) < 0.08
    img[weave] = img[weave] * 0.9
    return img


def window(size_w=16, size_h=20):
    """窗户：白框十字窗格 + 深色玻璃 + 一道斜高光"""
    img = np.zeros((size_h, size_w, 3))
    f0, f1, g0, g1 = S.c("frame_0"), S.c("frame_1"), S.c("window_0"), S.c("window_1")
    for y in range(size_h):
        for x in range(size_w):
            frame = x < 2 or x >= size_w - 2 or y < 2 or y >= size_h - 2 or x in (7, 8) or y in (9, 10)
            if frame:
                img[y, x] = f0 if y < size_h - 2 else f1
            else:
                img[y, x] = g1 if ((x + y) % 9 == 0 and x < 7 and y < 9) else g0
    return img


def flat(name, size=4):
    img = np.zeros((size, size, 3))
    img[:] = S.c(name)
    return img


def bark_marks(seed, size=32):
    """白桦树皮：白底低频斑驳 + 一道道横向的黑色短疤"""
    rng = _rng(seed)
    img = mottle(["snow_0", "snow_2"], seed, size=size, threshold=0.62)
    ink = np.array(S.mix("ink", "stone_3", 0.4))
    for _ in range(size // 3):
        y = int(rng.integers(0, size))
        x = int(rng.integers(0, size))
        ln = int(rng.integers(2, 6))
        for k in range(ln):
            img[y, (x + k) % size] = ink
        if rng.random() < 0.5:
            img[(y + 1) % size, (x + 1) % size] = ink
    return img


def flowers(seed, size=64):
    """花丛顶面：叶子底 + 成簇的彩色小花（红 / 黄 / 白 / 浅黄）"""
    rng = _rng(seed)
    img = foliage(["grass_1", "grass_0", "grass_2"], seed, size=size)
    heads = [S.c("red_0"), S.c("light_0"), S.c("frame_0"), S.c("cloth_yellow")]
    for _ in range(size * size // 40):
        x, y = int(rng.integers(0, size)), int(rng.integers(0, size))
        col = np.array(heads[int(rng.integers(0, len(heads)))])
        for dx, dy in ((0, 0), (1, 0), (0, 1)):
            img[(y + dy) % size, (x + dx) % size] = col
        img[(y + 1) % size, (x + 1) % size] = np.array(S.c("light_1"))
    return img


def gradient(top, bottom, h=16, w=4):
    """竖向渐变（行 0 = top）：草叶根部深、尖端浅"""
    a = np.array(S.c(top) if isinstance(top, str) else top, dtype=float)
    b = np.array(S.c(bottom) if isinstance(bottom, str) else bottom, dtype=float)
    t = np.linspace(0, 1, h)[:, None, None]
    return np.broadcast_to(a + (b - a) * t, (h, w, 3)).copy()


def thatch(seed, size=64, row_h=10):
    """茅草屋顶（行 0 = 屋脊方向）：一排排下垂的草束，排底边亮、上部暗，草秆竖向细纹"""
    rng = _rng(seed)
    hi, a, b, dark = S.c("cloth_yellow"), S.c("ochre_0"), S.c("ochre_1"), S.c("ochre_2")
    img = np.zeros((size, size, 3))
    for row in range(size // row_h):
        jag = rng.integers(-2, 3, size)
        for x in range(size):
            strand = _lerp(a, b, rng.random() * 0.8)
            for ly in range(row_h):
                y = row * row_h + ly
                t = ly / (row_h - 1)
                col = _lerp(dark, strand, min(1.0, 0.35 + t))
                if ly >= row_h - 2 + (jag[x] > 1):
                    col = _lerp(col, hi, 0.45)
                if (x + row * 3) % 4 == 0:
                    col = _lerp(col, dark, 0.25)
                img[y, x] = col
    return img


def glass_pane(size_w=16, size_h=24):
    """现代大玻璃（整张铺满一块玻璃，窗框是几何体）：上浅下深的玻璃 + 两道斜高光"""
    img = np.zeros((size_h, size_w, 3))
    g0, g1, hi = S.c("window_0"), S.c("window_1"), S.c("water_0")
    for y in range(size_h):
        for x in range(size_w):
            col = _lerp(g1, g0, 0.3 + 0.7 * y / (size_h - 1))
            if (x + y) % 11 in (0, 1) and x + y < size_w + 6:
                col = _lerp(col, hi, 0.45)
            img[y, x] = col
    return img


def cn_tiles(seed, size=64, col_w=8, row_h=8):
    """中式小青瓦（行 0 = 屋脊方向）：竖向一列列凸起的筒瓦（亮）和凹下的瓦沟（暗），每隔一段一道瓦片搭接的横缝"""
    rng = _rng(seed)
    hi, a, b, dark = S.c("stone_0"), S.c("roof_0"), S.c("roof_1"), S.c("roof_2")
    img = np.zeros((size, size, 3))
    for x in range(size):
        lx = x % col_w
        for y in range(size):
            ly = (y + (x // col_w) * 3) % row_h
            if lx < 3:  # 筒瓦（凸起）：中间一列高光
                col = _lerp(a, hi, 0.5) if lx == 1 else (np.array(a) if lx == 0 else _lerp(a, b, 0.4))
            else:  # 瓦沟
                col = _lerp(b, dark, 0.35 if lx in (3, col_w - 1) else 0.0)
            if ly == 0:
                col = _lerp(col, dark, 0.55)
            elif ly == 1:
                col = _lerp(col, hi, 0.25)
            img[y, x] = col
    speck = rng.random((size, size)) < 0.04
    img[speck] = img[speck] * 0.92
    return img


def leaded_glass(size_w=16, size_h=24):
    """中世纪铅条窗：深色玻璃 + 菱形铅条格 + 少量亮片（整张铺满一扇窗）"""
    img = np.zeros((size_h, size_w, 3))
    lead, g0, g1, hi = S.c("ink"), S.c("window_0"), S.c("window_1"), S.c("frame_1")
    for y in range(size_h):
        for x in range(size_w):
            d1 = (x + y) % 6 == 0
            d2 = (x - y) % 6 == 0
            if d1 or d2 or x == 0 or x == size_w - 1 or y == 0 or y == size_h - 1:
                img[y, x] = lead
            else:
                img[y, x] = g1 if (x * 7 + y * 3) % 11 == 0 else g0
                if x < size_w // 2 and y < size_h // 3 and (x + y) % 5 == 1:
                    img[y, x] = _lerp(g1, hi, 0.4)
    return img
