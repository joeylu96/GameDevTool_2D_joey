"""小镇房屋：木板墙 + 有厚度的双坡屋顶（白封檐、屋脊盖板）+ 白色转角 + 门窗部件 + 台阶 + 雨棚 + 烟囱 + 老虎窗。
对照 Godot 端 pw_house_builder.random_params / build。正门朝 -Y（导出后 Godot +Z），门底边中点在 (0, -depth/2, 0.35)，
台阶伸到 y = -(depth/2 + 0.95)。info.footprint = [宽 + 0.9, 深 + 0.9]（含屋檐）。
代码按 Godot 坐标写，G() 换算：Godot (x, y, z) → Blender (x, -z, y)。"""
import math
import random

from ..builder import MeshBuilder
from ._common import door, window

NAME = "小镇房屋"
CATEGORY = "buildings"
DESC = "Blender 生成的小镇房屋：彩色木板墙、灰 / 红双坡屋顶、白色窗框和转角，带百叶窗、花箱、门廊雨棚、老虎窗和烟囱。"
VARY = "宽 6~10 米、深 5~6.5 米、一层或两层、墙色（红 / 赭黄 / 青 / 原木）、屋顶坡度和颜色、门色、百叶窗、花箱、雨棚、老虎窗、烟囱随变体变化。"
TAGS = ["town"]
VARIANTS = 14

WALLS = ["wall_red", "wall_ochre", "wall_teal", "wall_wood", "wall_red"]
FLOOR_H = 2.8
BASE_H = 0.35
OVERHANG = 0.45
ROOF_T = 0.18
WIN_HW = 0.5
WIN_H = 1.25
DOOR_FOR_WALL = {
    "wall_red": ["door_teal", "door_green", "door_wood"],
    "wall_ochre": ["door_red", "door_teal", "door_green"],
    "wall_teal": ["door_red", "door_wood", "door_green"],
    "wall_wood": ["door_red", "door_teal", "door_green"],
}


def G(x, y, z):
    return (x, -z, y)


def _b(mb, key, a, b, top=True):
    """Godot 坐标的两个角点 → Blender 盒子"""
    (x0, y0, z0), (x1, y1, z1) = a, b
    mb.box(key, (min(x0, x1), -max(z0, z1), min(y0, y1)), (max(x0, x1), -min(z0, z1), max(y0, y1)), top=top)


def _f(mb, key, pts, out):
    mb.face(key, [G(*p) for p in pts], G(*out))


def _add(p, q):
    return (p[0] + q[0], p[1] + q[1], p[2] + q[2])


def _sub(p, q):
    return (p[0] - q[0], p[1] - q[1], p[2] - q[2])


def params(seed):
    r = random.Random(seed * 7919 + 13)
    k = seed - 1
    p = {
        "width": round(r.uniform(6.0, 10.0) * 2) / 2,
        "depth": round(r.uniform(5.0, 6.5) * 2) / 2,
        "floors": 2 if k % 3 == 2 else 1,           # 14 个里 4 个两层（Godot 端约 35%）
        "wall": WALLS[k % 5],
        "pitch": r.uniform(34.0, 42.0),
        "chimney": r.random() < 0.65,
        "chimney_x": r.uniform(-0.6, 0.6),
    }
    p["dormers"] = (r.randint(1, 2) if p["width"] >= 7.5 else 1) if r.random() < 0.55 else 0
    p["flowers"] = r.random() < 0.55
    p["canopy"] = r.random() < 0.6
    p["roof"] = "roof_red" if p["wall"] != "wall_red" and r.random() < 0.3 else "roof_grey"
    doors = DOOR_FOR_WALL[p["wall"]]
    p["door"] = doors[r.randrange(len(doors))]
    p["shutters"] = p["door"] if r.random() < 0.35 else ""
    p["panes_y"] = 3 if r.random() < 0.4 else 2
    return p


def build(seed, **over):
    p = params(seed)
    p.update(over)
    mb = MeshBuilder()
    w, d, floors, wall, roof = p["width"], p["depth"], p["floors"], p["wall"], p["roof"]
    hw, hd = w * 0.5, d * 0.5
    h = BASE_H + FLOOR_H * floors
    pitch = math.radians(p["pitch"])
    ridge = h + hd * math.tan(pitch)

    # 地基 + 墙 + 山墙三角
    _b(mb, "stone", (-hw - 0.1, 0.0, -hd - 0.1), (hw + 0.1, BASE_H, hd + 0.1))
    _b(mb, wall, (-hw, BASE_H, -hd), (hw, h, hd), top=False)
    _f(mb, wall, [(hw, h, -hd), (hw, h, hd), (hw, ridge, 0)], (1, 0, 0))
    _f(mb, wall, [(-hw, h, hd), (-hw, h, -hd), (-hw, ridge, 0)], (-1, 0, 0))
    for sx in (-1, 1):
        for sz in (-1, 1):
            cx, cz = sx * hw, sz * hd
            _b(mb, "trim", (cx - 0.1, BASE_H, cz - 0.1), (cx + 0.1, h, cz + 0.1), top=False)
    if floors > 1:
        yb = BASE_H + FLOOR_H - 0.06
        _b(mb, "trim", (-hw - 0.05, yb, -hd - 0.05), (hw + 0.05, yb + 0.14, hd + 0.05))

    # 屋顶
    eave_y = h - OVERHANG * math.tan(pitch)
    ze, xe = hd + OVERHANG, hw + OVERHANG
    t = (0, ROOF_T, 0)
    for s in (-1, 1):
        tl, tr = (-xe, ridge, 0), (xe, ridge, 0)
        br, bl = (xe, eave_y, s * ze), (-xe, eave_y, s * ze)
        _f(mb, roof, [tl, tr, br, bl], (0, 1, s))
        _f(mb, "roof_under", [_sub(q, t) for q in (tl, tr, br, bl)], (0, -1, -s))
        _f(mb, "trim", [bl, br, _sub(br, t), _sub(bl, t)], (0, 0, s))
        for sx in (-1, 1):
            a, b = (sx * xe, ridge, 0), (sx * xe, eave_y, s * ze)
            _f(mb, "trim", [a, b, _sub(b, t), _sub(a, t)], (sx, 0, 0))
    _b(mb, "roof_cap", (-xe - 0.03, ridge - 0.06, -0.14), (xe + 0.03, ridge + 0.1, 0.14))

    # 窗户（前后墙）
    n_win = max(1, int((w - 1.0) / 2.2))
    spacing = w / n_win
    for f in range(floors):
        y0 = BASE_H + f * FLOOR_H + 0.8
        for s in (-1, 1):
            for i in range(n_win):
                x = -hw + spacing * (i + 0.5)
                if f == 0 and s > 0 and abs(x) < 1.3:
                    continue
                window(mb, G(x, y0, s * hd), G(0, 0, s), WIN_HW, WIN_H, panes_y=p["panes_y"],
                       shutters=p["shutters"] if s > 0 else "", flowers=(f == 0 and s > 0 and p["flowers"]))
    if ridge - h > 1.9:
        for sx in (-1, 1):
            window(mb, G(sx * hw, h + 0.15, 0), (sx, 0, 0), 0.42, 1.0)

    # 门 + 台阶 + 雨棚
    door(mb, G(0, BASE_H, hd), (0, -1, 0), mat=p["door"])
    _b(mb, "stone", (-0.9, 0.0, hd), (0.9, 0.2, hd + 0.6))
    _b(mb, "stone", (-0.75, 0.0, hd + 0.6), (0.75, 0.1, hd + 0.95))
    if p["canopy"]:
        _canopy(mb, hd, BASE_H + 2.3, roof)

    # 烟囱（后坡）
    cx = p["chimney_x"] * hw
    cz = -hd * 0.4
    top = ridge
    if p["chimney"]:
        _b(mb, "brick", (cx - 0.35, h, cz - 0.35), (cx + 0.35, ridge + 0.9, cz + 0.35))
        _b(mb, "stone", (cx - 0.42, ridge + 0.9, cz - 0.42), (cx + 0.42, ridge + 1.05, cz + 0.42))
        top = ridge + 1.05

    # 老虎窗
    nd = p["dormers"]
    for i in range(nd):
        xd = -hw + w * (i + 1) / (nd + 1)
        for s in (-1, 1):
            if s < 0 and p["chimney"] and abs(xd - cx) < 1.4:
                continue
            _dormer(mb, xd, s, hd, ridge, pitch, wall, roof)

    info = {
        "footprint": [round(w + OVERHANG * 2, 3), round(d + OVERHANG * 2, 3)],
        "height": round(top, 3),
        "door": [0.0, -hd, BASE_H],            # Blender 坐标，门底边中点（Godot (0, 0.35, depth/2)）
        "steps_to": round(-(hd + 0.95), 3),
        "params": {k: (round(v, 3) if isinstance(v, float) else v) for k, v in p.items()},
    }
    return mb, info


def _canopy(mb, hd, cy, roof):
    ze, hw = hd + 0.85, 1.0
    a, b = (-hw, cy + 0.35, hd), (hw, cy + 0.35, hd)
    c, d = (hw, cy, ze), (-hw, cy, ze)
    t = (0, 0.1, 0)
    _f(mb, roof, [a, b, c, d], (0, 1, 1))
    _f(mb, "roof_under", [_sub(q, t) for q in (a, b, c, d)], (0, -1, 0))
    _f(mb, "trim", [d, c, _sub(c, t), _sub(d, t)], (0, 0, 1))
    for sx in (-1, 1):
        p0, p1 = (sx * hw, cy + 0.35, hd), (sx * hw, cy, ze)
        _f(mb, "trim", [p0, p1, _sub(p1, t), _sub(p0, t)], (sx, 0, 0))
        _b(mb, "trim", (sx * 0.85 - 0.05, cy - 0.45, hd), (sx * 0.85 + 0.05, cy + 0.25, hd + 0.12))


def _dormer(mb, xd, s, hd, ridge, pitch, wall, roof):
    zf = hd * 0.62
    yr = ridge - zf * math.tan(pitch)
    dh = min(1.05, zf * math.tan(pitch) - 0.3)
    if dh < 0.7:
        return
    dw = 0.75
    zb = max(zf - 1.6, 0.05)
    ye = yr + dh
    yt = ye + dw * 0.95
    _b(mb, wall, (xd - dw, yr - 0.6, s * zb), (xd + dw, ye, s * zf), top=False)
    _f(mb, wall, [(xd - dw, ye, s * zf), (xd + dw, ye, s * zf), (xd, yt - 0.02, s * zf)], (0, 0, s))
    zo, zbk = s * (zf + 0.2), s * zb
    dwr = dw + 0.14
    t = (0, 0.1, 0)
    for side in (-1, 1):
        a, b = (xd, yt, zbk), (xd, yt, zo)
        c, d = (xd + side * dwr, ye - 0.08, zo), (xd + side * dwr, ye - 0.08, zbk)
        _f(mb, roof, [a, b, c, d], (side, 1, 0))
        _f(mb, "trim", [b, c, _sub(c, t), _sub(b, t)], (0, 0, s))
    window(mb, G(xd, yr + 0.18, s * zf), G(0, 0, s), 0.3, 0.6, panes_y=1)
