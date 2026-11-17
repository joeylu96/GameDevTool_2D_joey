"""南方山村的老木屋（穿斗木构架）：粗石垒的台基 + 台阶，深色木柱木梁之间是发旧的白灰墙板，暗红色木板门、木格窗，
正面一道深檐廊（圆木檐柱立在石柱础上），厚重的深灰小瓦双坡顶（屋脊中间略微下垂），前坡一直盖到檐廊外。
有的变体在一侧带一间单坡的灶房偏屋。墙上挂着辣椒串、草帽、竹篮，檐廊上摆着腌菜坛，墙边靠一把扫帚。
正面（檐廊）朝 -Y（导出后 Godot +Z），原点在占地（含檐廊、偏屋）中心地面。info.params：width / depth（都含檐廊和偏屋）。
变体：0 无偏屋（宽 10）、1 左侧偏屋（宽 13）、2 无偏屋（宽 12）、3 右侧偏屋（宽 14）。"""
import math
import random

from ..builder import MeshBuilder
from ._medieval import V, Wall, box

NAME = "老木屋"
CATEGORY = "buildings"
DESC = "Blender 生成的山村老木屋：粗石台基、深色木构架夹白灰墙板、暗红木板门、木格窗、带圆木檐柱的深檐廊、厚重的深灰小瓦顶，墙上挂着辣椒串和草帽。"
VARY = "宽 10~14 米、深 6~7.5 米（含檐廊），有无单坡灶房偏屋及在哪一侧、开间数、墙上挂的东西随变体变化。"
TAGS = ["cn_village", "town", "yard"]
VARIANTS = 4

BASE = 0.45
WALL_H = 3.3
PITCH = 22.0
WING_W = 3.2


def params(seed):
    k = (seed - 1) % 4
    r = random.Random(seed * 131 + 7)
    return {
        "width": [10.0, 13.0, 12.0, 14.0][k],
        "depth": [6.5, 6.5, 7.0, 7.5][k],
        "veranda": [1.7, 1.7, 1.9, 2.0][k],
        "wing": [0, -1, 0, 1][k],
        "bays": [4, 4, 5, 5][k],
        "hang": r.randrange(3),
    }


def _roof(mb, x0, x1, y_fe, y_r, y_be, z_r, key="tile_cn_dark", t=0.14, sag=0.1, segs=4):
    """前后坡不等长的双坡瓦顶：屋脊沿 X 在 y_r，高 z_r（中间下垂 sag）；前檐 y_fe、后檐 y_be。返回 (前檐高, 后檐高)"""
    tan = math.tan(math.radians(PITCH))
    zf = z_r - (y_r - y_fe) * tan
    zb = z_r - (y_be - y_r) * tan
    dt = V(0, 0, t)
    xs = [x0 + (x1 - x0) * i / segs for i in range(segs + 1)]
    zr = [z_r - sag * math.sin(math.pi * i / segs) for i in range(segs + 1)]
    for ye, ze, s in ((y_fe, zf, -1), (y_be, zb, 1)):
        n = V(0, s * math.sin(math.radians(PITCH)), math.cos(math.radians(PITCH)))
        for i in range(segs):
            tl, tr = V(xs[i], y_r, zr[i]), V(xs[i + 1], y_r, zr[i + 1])
            br, bl = V(xs[i + 1], ye, ze), V(xs[i], ye, ze)
            mb.face(key, [tl, tr, br, bl], n)
            mb.face("roof_under", [q - dt for q in (tl, tr, br, bl)], -n)
        mb.face(key, [V(x0, ye, ze), V(x1, ye, ze), V(x1, ye, ze - t), V(x0, ye, ze - t)], V(0, s, 0))
        for xe, sa in ((x0, -1), (x1, 1)):
            p, q = V(xe, y_r, z_r), V(xe, ye, ze)
            mb.face(key, [p, q, q - dt, p - dt], V(sa, 0, 0))
        box(mb, "roof_cap", x0, min(ye, ye - s * 0.07), ze - 0.07, x1, max(ye, ye - s * 0.07), ze + 0.03)  # 檐口瓦当
    for i in range(segs):  # 屋脊：一段段砌起来，跟着下垂
        za = min(zr[i], zr[i + 1])
        box(mb, "roof_cap", xs[i] + (0.05 if i == 0 else 0), y_r - 0.17, za - 0.05, xs[i + 1] - (0.05 if i == segs - 1 else 0), y_r + 0.17, za + 0.22)
    for xe, sx in ((x0 + 0.05, 1), (x1 - 0.05, -1)):
        mb.tube("roof_cap", (xe + sx * 0.4, y_r, z_r + 0.12), (xe - sx * 0.05, y_r, z_r + 0.45), 0.11, 0.06, 6, math.pi / 6)
    return zf, zb


def _lattice(mb, wall, s, z, w=1.3, h=1.1):
    hw = w * 0.5
    wall.quad(mb, "glass_lattice", s - hw, z, s + hw, z + h, 0.02)
    f = 0.09
    for a in ((s - hw - f, z - f, s + hw + f, z), (s - hw - f, z + h, s + hw + f, z + h + f),
              (s - hw - f, z, s - hw, z + h), (s + hw, z, s + hw + f, z + h)):
        wall.box(mb, "timber", a[0], a[1], a[2], a[3], 0.0, 0.08)
    wall.box(mb, "timber", s - 0.035, z, s + 0.035, z + h, 0.02, 0.06)


def _plank_door(mb, wall, s, w=1.5, h=2.15, key="door_oldred"):
    hw = w * 0.5
    wall.box(mb, key, s - hw, 0.0, s + hw, h, 0.0, 0.05)
    wall.box(mb, "timber", s - 0.03, 0.0, s + 0.03, h, 0.05, 0.07)
    for sx in (-1, 1):
        wall.box(mb, "timber", s + sx * hw - 0.07, 0.0, s + sx * hw + 0.07, h + 0.1, 0.0, 0.1)
        wall.box(mb, "iron", s + sx * 0.16 - 0.04, 1.05, s + sx * 0.16 + 0.04, 1.13, 0.05, 0.09)
    wall.box(mb, "timber", s - hw - 0.15, h, s + hw + 0.15, h + 0.16, 0.0, 0.12)
    wall.box(mb, "stone", s - hw - 0.1, 0.0, s + hw + 0.1, 0.12, 0.0, 0.16)  # 门槛


def _chillies(mb, x, y, z, n=3):
    """挂在墙上的几串红辣椒"""
    for i in range(n):
        xx = x + (i - (n - 1) * 0.5) * 0.13
        mb.tube("trunk", (xx, y, z + 0.08), (xx, y, z), 0.012, 0.012, 4)
        mb.tube("fruit_red", (xx, y, z), (xx, y, z - 0.55 - 0.08 * (i % 2)), 0.055, 0.03, 8)


def build(seed, **over):
    p = params(seed)
    p.update(over)
    mb = MeshBuilder()
    w, d, dv, ws = p["width"], p["depth"], p["veranda"], p["wing"]
    hw, hd = w * 0.5, d * 0.5
    # 主屋的 X 范围（偏屋占掉一侧 WING_W）
    bx0 = -hw + (WING_W if ws < 0 else 0.0)
    bx1 = hw - (WING_W if ws > 0 else 0.0)
    bw = bx1 - bx0
    yf = -hd + dv            # 正面墙
    yb = hd                  # 后墙
    db = yb - yf
    y_r = (yf + yb) * 0.5
    top = BASE + WALL_H
    # ---- 粗石台基 + 台阶（檐廊和主屋下面一整块）
    box(mb, "drystone", bx0 - 0.25, -hd - 0.05, 0.0, bx1 + 0.25, hd + 0.15, BASE - 0.06)
    box(mb, "stone", bx0 - 0.3, -hd - 0.1, BASE - 0.06, bx1 + 0.3, yf, BASE)      # 檐廊的石板面
    cxd = (bx0 + bx1) * 0.5
    box(mb, "stone", cxd - 1.3, -hd - 0.75, 0.0, cxd + 1.3, -hd - 0.05, 0.15)
    box(mb, "stone", cxd - 1.1, -hd - 0.42, 0.15, cxd + 1.1, -hd - 0.05, 0.3)
    # ---- 墙：白灰墙板 + 木构架
    box(mb, "whitewash_old", bx0, yf, BASE, bx1, yb, top, top=False)
    F = Wall((bx0, yf, BASE), (1, 0, 0), (0, -1, 0))
    Bk = Wall((bx1, yb, BASE), (-1, 0, 0), (0, 1, 0))
    Lf = Wall((bx0, yb, BASE), (0, -1, 0), (-1, 0, 0))
    Rt = Wall((bx1, yf, BASE), (0, 1, 0), (1, 0, 0))
    nb = p["bays"]
    for wl, ln, n in ((F, bw, nb), (Bk, bw, nb), (Lf, db, 3), (Rt, db, 3)):
        wl.beam(mb, "timber", 0, 0.1, ln, 0.1, 0.2, 0.07)
        wl.beam(mb, "timber", 0, WALL_H - 0.1, ln, WALL_H - 0.1, 0.2, 0.07)
        wl.beam(mb, "timber", 0, WALL_H * 0.72, ln, WALL_H * 0.72, 0.14, 0.06)
        for i in range(n + 1):
            x = min(max(ln * i / n, 0.1), ln - 0.1)
            wl.beam(mb, "timber", x, 0.0, x, WALL_H, 0.2, 0.08)
    # 正面：中间开间是双开门，两边木格窗，最边上一樘单扇暗红门
    bay = bw / nb
    mid = nb // 2
    for i in range(nb):
        s = bay * (i + 0.5)
        if i == mid:
            _plank_door(mb, F, s, min(1.6, bay - 0.5))
        elif i == nb - 1:
            _plank_door(mb, F, s, 0.95)
        else:
            _lattice(mb, F, s, 1.0, min(1.35, bay - 0.7))
            F.box(mb, "door_oldred", s - min(1.35, bay - 0.7) * 0.5, 0.2, s + min(1.35, bay - 0.7) * 0.5, 0.9, 0.0, 0.04)  # 窗下暗红裙板
    _lattice(mb, Bk, bw * 0.3, 1.3, 0.9, 0.8)
    _lattice(mb, Bk, bw * 0.7, 1.3, 0.9, 0.8)
    # ---- 屋顶：前坡盖到檐廊外
    z_r = top + (db * 0.5) * math.tan(math.radians(PITCH))
    y_fe, y_be = -hd - 0.15, hd + 0.5
    zf, zb = _roof(mb, bx0 - 0.45, bx1 + 0.45, y_fe, y_r, y_be, z_r)
    for xe, sa, wl in ((bx0, -1, Lf), (bx1, 1, Rt)):  # 山墙三角 + 中柱、斜梁
        mb.face("whitewash_old", [V(xe, yf, top), V(xe, yb, top), V(xe, y_r, z_r - 0.05)], (sa, 0, 0))
        wl.beam(mb, "timber", db * 0.5, WALL_H, db * 0.5, WALL_H + (z_r - top) - 0.15, 0.18, 0.07)
    # ---- 檐廊：圆木檐柱（石柱础）+ 檐枋，从山墙挑出的穿枋
    zb_beam = z_r - (y_r - (-hd + 0.25)) * math.tan(math.radians(PITCH)) - 0.2
    npost = nb + 1
    for i in range(npost):
        x = bx0 + 0.15 + (bw - 0.3) * i / (npost - 1)
        y = -hd + 0.25
        mb.frustum("stone", x, y, BASE, BASE + 0.18, 0.2, 0.15, 12)
        mb.tube("timber", (x, y, BASE + 0.18), (x, y, zb_beam), 0.11, 0.1, 12)
        mb.tube("timber", (x, y, zb_beam - 0.25), (x, yf, zb_beam + (yf - y) * math.tan(math.radians(PITCH)) - 0.25), 0.07, 0.07, 6)
    box(mb, "timber", bx0 - 0.2, -hd + 0.16, zb_beam - 0.1, bx1 + 0.2, -hd + 0.34, zb_beam + 0.1)
    # ---- 墙上和檐廊上的东西
    hz = BASE + 2.2
    yw = yf - 0.07
    sx_post = lambda i: bx0 + bay * i  # noqa: E731  开间分界柱的位置
    if p["hang"] != 1:
        _chillies(mb, sx_post(mid + 1) + 0.28, yw - 0.03, hz)
    if p["hang"] != 2:  # 草帽：挂在柱子旁的墙上
        hx = sx_post(nb - 1) - 0.35 if nb > 3 else sx_post(1) + 0.35
        mb.tube("thatch", (hx, yw + 0.02, hz - 0.3), (hx, yw - 0.03, hz - 0.3), 0.3, 0.27, 14)
        mb.tube("thatch", (hx, yw - 0.03, hz - 0.3), (hx, yw - 0.15, hz - 0.3), 0.13, 0.03, 12)
    if p["hang"] != 0:
        _chillies(mb, sx_post(1) - 0.3, yw - 0.03, hz, 2)
    # 竹篮（挂在最左的柱子上）
    bxk = bx0 + 0.45
    mb.frustum("bamboo", bxk, yw - 0.22, hz - 0.75, hz - 0.3, 0.14, 0.24, 12, bottom=True)
    mb.tube("trunk", (bxk, yw - 0.02, hz + 0.05), (bxk, yw - 0.22, hz - 0.3), 0.012, 0.012, 4)
    # 腌菜坛（门左边靠墙一排）
    jx = sx_post(mid) - 0.5
    for i, (r, h) in enumerate(((0.3, 0.75), (0.24, 0.6), (0.18, 0.45))):
        x = jx - i * 0.6
        if x - r < bx0 + 0.2:
            break
        y = yf - 0.4
        mb.frustum("glaze", x, y, BASE, BASE + h * 0.55, r * 0.7, r, 12, bottom=False)
        mb.frustum("glaze", x, y, BASE + h * 0.55, BASE + h, r, r * 0.55, 12)
        mb.frustum("timber", x, y, BASE + h, BASE + h + 0.05, r * 0.62, r * 0.6, 12)
    # 扫帚：斜靠在最右开间的墙上
    bxm = bx1 - 0.5
    mb.tube("bamboo", (bxm, yf - 0.5, BASE + 0.45), (bxm, yf - 0.1, BASE + 1.75), 0.018, 0.018, 6)
    mb.tube("hay", (bxm, yf - 0.62, BASE + 0.02), (bxm, yf - 0.5, BASE + 0.5), 0.2, 0.05, 10)
    # ---- 灶房偏屋：单坡瓦顶朝外侧低，正面一个敞开的门洞，墙边一堆柴、一个小炉子和水壶
    if ws != 0:
        wx0, wx1 = (-hw, bx0) if ws < 0 else (bx1, hw)
        wy0, wy1 = yf - 0.6, yf + 3.4
        wh_in, wh_out = 2.9, 2.2
        box(mb, "drystone", wx0 - 0.1, wy0 - 0.1, 0.0, wx1 + 0.1, wy1 + 0.1, 0.25)
        box(mb, "whitewash_old", wx0, wy0, 0.25, wx1, wy1, 0.25 + wh_out, top=False)
        xo, xi = (wx0, wx1) if ws < 0 else (wx1, wx0)   # 外侧 / 靠主屋一侧
        for yy, ny in ((wy0, -1), (wy1, 1)):             # 前后墙上面的梯形
            mb.face("whitewash_old", [V(xo, yy, 0.25 + wh_out), V(xi, yy, 0.25 + wh_out), V(xi, yy, 0.25 + wh_in)], (0, ny, 0))
        WF = Wall((wx0, wy0, 0.25), (1, 0, 0), (0, -1, 0))
        ww = wx1 - wx0
        WF.box(mb, "roof_under", ww * 0.5 - 0.5, 0.0, ww * 0.5 + 0.5, 1.95, 0.0, 0.02)   # 黑洞洞的门洞
        for sx in (-1, 1):
            WF.box(mb, "timber", ww * 0.5 + sx * 0.5 - 0.07, 0.0, ww * 0.5 + sx * 0.5 + 0.07, 2.05, 0.0, 0.1)
        WF.box(mb, "timber", ww * 0.5 - 0.65, 1.95, ww * 0.5 + 0.65, 2.1, 0.0, 0.12)
        for xx in (wx0 + 0.1, wx1 - 0.1):
            WF_s = xx - wx0
            WF.beam(mb, "timber", WF_s, 0.0, WF_s, wh_out, 0.18, 0.07)
        # 单坡顶
        ov = 0.4
        a = [V(xi, wy0 - ov, 0.25 + wh_in + 0.05), V(xi, wy1 + ov, 0.25 + wh_in + 0.05)]
        xo2 = xo + ws * ov
        zo = 0.25 + wh_out - ov * (wh_in - wh_out) / ww
        b = [V(xo2, wy1 + ov, zo), V(xo2, wy0 - ov, zo)]
        mb.face("tile_cn_dark", [a[0], a[1], b[0], b[1]], (ws * 0.3, 0, 1))
        dt = V(0, 0, 0.12)
        mb.face("roof_under", [q - dt for q in (a[0], a[1], b[0], b[1])], (-ws * 0.3, 0, -1))
        mb.face("tile_cn_dark", [b[0], b[1], b[1] - dt, b[0] - dt], (ws, 0, 0))
        for q0, q1, ny in ((a[0], b[1], -1), (a[1], b[0], 1)):
            mb.face("tile_cn_dark", [q0, q1, q1 - dt, q0 - dt], (0, ny, 0))
        # 柴堆（偏屋正面墙根）、小炉子 + 水壶
        fx = wx0 + 0.45 if ws < 0 else wx1 - 0.45
        for row in range(3):
            for j in range(4 - row):
                yy = wy0 - 0.35
                xx = fx + (j - (3 - row) * 0.5) * 0.2 * (1 if True else 1)
                mb.tube("trunk", (xx, yy - 0.35, 0.1 + row * 0.18), (xx, yy + 0.3, 0.1 + row * 0.18), 0.09, 0.09, 8)
        sx0 = (wx0 + wx1) * 0.5 + ws * -0.9
        mb.frustum("iron", sx0, wy0 - 0.45, 0.0, 0.5, 0.2, 0.17, 12)
        mb.frustum("iron", sx0, wy0 - 0.45, 0.5, 0.72, 0.15, 0.11, 12)
        mb.tube("iron", (sx0, wy0 - 0.45, 0.66), (sx0 + 0.22, wy0 - 0.45, 0.78), 0.025, 0.02, 6)
    info = {
        "footprint": [round(w + 0.9, 2), round(d + 1.7, 2)],
        "height": round(z_r + 0.5, 2),
        "door": [round(cxd, 2), round(yf, 2), BASE],
        "params": {k: (round(v, 3) if isinstance(v, float) else v) for k, v in p.items()},
    }
    return mb, info
