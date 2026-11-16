"""小石头教堂：正面（-Y）是方形钟楼，塔顶钟室四面开拱形窗洞，上面一个陡尖的四棱 / 八棱尖顶和铁十字；
钟楼后面是长条的中殿（陡坡青石板屋顶），两侧墙上是尖拱形的铅条长窗，窗间有阶梯形扶壁；最后面一个更窄更矮的圣坛。
正门（圆拱双开木门）在钟楼正面，门底边中点见 info.door；整体按外廓居中（原点 = 占地中心）。"""
import math
import random

from ..builder import MeshBuilder
from ._medieval import Wall, box, door_m, gable_roof, recenter_y, walls_box, window_m

NAME = "小教堂"
CATEGORY = "landmarks"
DESC = "Blender 生成的中世纪小石头教堂：正面方形钟楼和尖顶，长条中殿配陡坡石板屋顶、尖拱铅条窗和阶梯扶壁，后面一个小圣坛。"
VARY = "石材（灰石 / 暖色石）、尖顶（四棱 / 八棱，青石板 / 红瓦）、中殿长度、窗户数量随变体变化。"
TAGS = ["town", "medieval", "plaza"]
VARIANTS = 3


def _lancet(mb, wall, s, z, hw, h):
    """尖拱窗：两段圆弧交成尖顶"""
    pts = [(s + hw, z), (s + hw, z + h - hw * 1.6)]
    base = z + h - hw * 1.6
    for i in range(1, 6):
        t = i / 6
        pts.append((s + hw - hw * (1 - math.cos(t * math.pi / 2)) * 1.0, base + hw * 1.6 * math.sin(t * math.pi / 2)))
    pts.append((s, z + h))
    for i in range(5, 0, -1):
        t = i / 6
        pts.append((s - hw + hw * (1 - math.cos(t * math.pi / 2)) * 1.0, base + hw * 1.6 * math.sin(t * math.pi / 2)))
    pts += [(s - hw, base), (s - hw, z)]
    wall.poly(mb, "glass_lead", pts, 0.012)
    # 石窗框：沿轮廓一圈短石条
    ring = pts[:-1]
    for a, b in zip(ring[:-1], ring[1:]):
        if abs(a[1] - z) < 1e-6 and abs(b[1] - z) < 1e-6:
            continue
        wall.beam(mb, "cobble_wall", a[0] + (0.08 if a[0] > s else -0.08), a[1], b[0] + (0.08 if b[0] > s else -0.08), b[1], 0.16, 0.07)
    wall.box(mb, "cobble_wall", s - hw - 0.15, z - 0.14, s + hw + 0.15, z, 0.0, 0.14)


def build(seed, **over):
    r = random.Random(seed * 401 + 9)
    k = seed - 1
    p = {
        "stone": ["castle_stone", "cobble_wall", "castle_stone"][k % 3],
        "spire": ["slate", "slate", "roof_red"][k % 3],
        "spire_sides": [4, 8, 8][k % 3],
        "nave_len": [11.0, 12.0, 10.0][k % 3],
        "nave_w": 7.0,
        "windows": [3, 4, 3][k % 3],
    }
    p.update(over)
    mb = MeshBuilder()
    st = p["stone"]
    L, W = p["nave_len"], p["nave_w"]
    hw = W * 0.5
    wall_h = 5.6
    ny0, ny1 = -L * 0.5, L * 0.5
    box(mb, "cobble_wall", -hw - 0.2, ny0 - 0.2, 0.0, hw + 0.2, ny1 + 0.2, 0.25)
    ws = walls_box(mb, st, -hw, ny0, 0.2, hw, ny1, 0.2 + wall_h)
    ridge, gables = gable_roof(mb, "slate", ny0, ny1, -hw, hw, 0.2 + wall_h, 56.0, axis="y", eave=0.5, gable=0.25)
    for sa, tri in gables:
        mb.face(st, tri, (0, sa, 0))
    # 侧窗 + 扶壁
    n = p["windows"]
    for side in ("left", "right"):
        wall = ws[side]
        for i in range(n):
            s = L * (i + 0.5) / n
            _lancet(mb, wall, s, 1.7, 0.42, 2.9)
        for i in range(n + 1):
            s = L * i / n
            s = min(max(s, 0.35), L - 0.35)
            wall.box(mb, st, s - 0.35, 0.2, s + 0.35, 2.6, 0.0, 0.9)
            wall.box(mb, st, s - 0.3, 2.6, s + 0.3, 4.1, 0.0, 0.55)
            wall.box(mb, "cobble_wall", s - 0.38, 2.45, s + 0.38, 2.62, 0.0, 0.95)
            wall.box(mb, "cobble_wall", s - 0.33, 4.0, s + 0.33, 4.15, 0.0, 0.6)
    # 后墙圆窗 + 圣坛（更窄更矮）
    cw, cl, ch = 4.6, 3.2, 4.2
    ws2 = walls_box(mb, st, -cw * 0.5, ny1, 0.2, cw * 0.5, ny1 + cl, 0.2 + ch)
    r2, g2 = gable_roof(mb, "slate", ny1 - 0.3, ny1 + cl, -cw * 0.5, cw * 0.5, 0.2 + ch, 56.0, axis="y", eave=0.4, gable=0.2)
    for sa, tri in g2:
        if sa > 0:
            mb.face(st, tri, (0, 1, 0))
    _lancet(mb, ws2["back"], cw * 0.5, 1.6, 0.36, 2.2)
    for side in ("left", "right"):
        _lancet(mb, ws2[side], cl * 0.55, 1.8, 0.3, 1.9)
    # 钟楼（正面中间，压在中殿前端）
    t = 3.4
    th = 11.5
    ty0 = ny0 - 1.2
    tws = walls_box(mb, st, -t * 0.5, ty0, 0.2, t * 0.5, ty0 + t, th)
    box(mb, "cobble_wall", -t * 0.5 - 0.15, ty0 - 0.15, 0.0, t * 0.5 + 0.15, ty0 + t + 0.15, 0.3)
    # 腰线 + 角部扶壁
    for zz in (4.6, 8.0):
        box(mb, "cobble_wall", -t * 0.5 - 0.08, ty0 - 0.08, zz, t * 0.5 + 0.08, ty0 + t + 0.08, zz + 0.18)
    for sx in (-1, 1):
        box(mb, st, sx * t * 0.5 - (0.0 if sx > 0 else 0.45), ty0 - 0.45, 0.2, sx * t * 0.5 + (0.45 if sx > 0 else 0.0), ty0 + 0.35, 3.4)
        box(mb, st, sx * t * 0.5 - (0.0 if sx > 0 else 0.3), ty0 - 0.3, 3.4, sx * t * 0.5 + (0.3 if sx > 0 else 0.0), ty0 + 0.25, 6.0)
    door_m(mb, tws["front"], t * 0.5, 0.1, 1.5, 2.9, mat="door_wood", frame="cobble_wall", arched=True, double=True)
    window_m(mb, tws["front"], t * 0.5, 5.4, 0.32, 1.6, shutters="", frame="cobble_wall", arched=True)
    # 钟室：四面拱形窗洞（深色洞口 + 石拱圈）+ 一口钟
    for side, wall in tws.items():
        L2 = t
        for s in (L2 * 0.5,):
            pts = [(s + 0.5, 8.6), (s + 0.5, 10.3)]
            for i in range(1, 8):
                a = math.pi * i / 8
                pts.append((s + math.cos(a) * 0.5, 10.3 + math.sin(a) * 0.5))
            pts += [(s - 0.5, 10.3), (s - 0.5, 8.6)]
            wall.poly(mb, "coal", pts, 0.012)
            for i in range(8):
                a0, a1 = math.pi * i / 8, math.pi * (i + 1) / 8
                wall.beam(mb, "cobble_wall", s + math.cos(a0) * 0.6, 10.3 + math.sin(a0) * 0.6,
                          s + math.cos(a1) * 0.6, 10.3 + math.sin(a1) * 0.6, 0.18, 0.08)
            wall.box(mb, "cobble_wall", s - 0.7, 8.45, s + 0.7, 8.62, 0.0, 0.16)
    cy = ty0 + t * 0.5
    mb.frustum("brass", 0.0, cy, 9.0, 9.9, 0.42, 0.22, 10, 0.0, top=True, bottom=True)
    # 塔顶：檐口 + 尖顶 + 铁十字
    box(mb, "cobble_wall", -t * 0.5 - 0.22, ty0 - 0.22, th, t * 0.5 + 0.22, ty0 + t + 0.22, th + 0.25)
    sides = p["spire_sides"]
    rad = (t * 0.5 + 0.1) * (math.sqrt(2) if sides == 4 else 1.08)
    rot = math.pi / 4 if sides == 4 else math.pi / 8
    spire_h = 5.6
    mb.frustum(p["spire"], 0.0, cy, th + 0.25, th + 0.25 + spire_h, rad, 0.0, sides, rot, top=False, bottom=True)
    tip = th + 0.25 + spire_h
    box(mb, "iron", -0.04, cy - 0.04, tip - 0.1, 0.04, cy + 0.04, tip + 1.0)
    box(mb, "iron", -0.3, cy - 0.04, tip + 0.55, 0.3, cy + 0.04, tip + 0.63)
    yf, yb = ty0 - 0.6, ny1 + cl + 0.5
    dy = recenter_y(mb, yf, yb)
    info = {
        "footprint": [round(W + 2.0, 2), round(yb - yf, 2)],
        "height": round(tip + 1.0, 2),
        "door": [0.0, round(ty0 + dy, 2), 0.1],
        "params": {k: (round(v, 3) if isinstance(v, float) else v) for k, v in p.items()},
    }
    return mb, info
