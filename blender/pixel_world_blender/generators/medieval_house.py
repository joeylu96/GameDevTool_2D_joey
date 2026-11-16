"""中世纪木构房屋（半木构 / Fachwerk）：石砌底层或石台基，上层白 / 赭色灰泥墙配深色木构架（柱、梁、斜撑都是独立几何体），
上层向前后挑出（每层 0.3~0.45 米，下面露出一排搁栅头），陡坡双坡屋顶（青石板 / 红瓦 / 茅草），铅条窗 + 木百叶窗，
木板门带铁合页，石烟囱。屋脊平行于正面，或山墙朝街（gable_front）。
正门朝 -Y（导出后 Godot +Z）；底层墙体占 x ∈ [-width/2, width/2]、y ∈ [-depth/2, depth/2]；门底边中点 (door_x, -depth/2, 0.25)。
info.footprint = 含挑出和屋檐的外廓；params 里有 width / depth / floors（catalog 的 variant_info 用）。"""
import math
import random

from ..builder import MeshBuilder
from ._medieval import Wall, box, chimney, door_m, gable_roof, timber_frame, walls_box, window_m

NAME = "中世纪木构房屋"
CATEGORY = "buildings"
DESC = "Blender 生成的中世纪半木构房屋：石砌底层或石台基，上层灰泥墙配深色木构架和斜撑，楼层向外挑出，陡坡青石板 / 红瓦 / 茅草屋顶，铅条窗、木百叶窗、铁合页木门和石烟囱。"
VARY = "宽 6~9 米、深 5~7 米、1~3 层、底层石砌或木构、灰泥颜色（白 / 赭）、屋顶（青石板 / 红瓦 / 茅草）、屋脊方向（平行正面 / 山墙朝街）、挑出距离、门的位置、烟囱随变体变化。"
TAGS = ["town", "medieval"]
VARIANTS = 8

GROUND_H = 2.8
UPPER_H = 2.5
PLINTH = 0.25


def params(seed):
    r = random.Random(seed * 1543 + 71)
    k = seed - 1
    floors = [2, 3, 2, 1, 2, 3, 1, 2][k % 8]
    p = {
        "width": round(r.uniform(6.0, 9.0) * 2) / 2,
        "depth": round(r.uniform(5.0, 7.0) * 2) / 2,
        "floors": floors,
        "ground": "stone" if (k % 3 != 1 and floors > 1) else "plaster",
        "plaster": "plaster_white" if k % 4 != 2 else "plaster_ochre",
        "roof": ["slate", "roof_red", "slate", "thatch", "roof_red", "slate", "thatch", "roof_red"][k % 8],
        "pitch": r.uniform(50.0, 57.0),
        "jetty": r.uniform(0.3, 0.45) if floors > 1 else 0.0,
        "gable_front": k % 3 == 2,
        "door_x": r.choice([-1.0, 0.0, 1.0]) * 0.18,
        "chimney": r.random() < 0.8,
        "shutters": r.choice(["door_wood", "door_green", "door_red", "door_wood"]),
        "door": r.choice(["door_wood", "door_wood", "door_red", "door_green"]),
    }
    if p["roof"] == "thatch" and p["floors"] > 2:
        p["roof"] = "slate"
    return p


def build(seed, **over):
    p = params(seed)
    p.update(over)
    mb = MeshBuilder()
    rng = random.Random(seed * 31 + 5)
    info = build_house(mb, p, rng)
    return mb, info


def build_house(mb, p, rng, door_w=1.1, double_door=False):
    w, d, floors = p["width"], p["depth"], p["floors"]
    hw = w * 0.5
    j = p["jetty"]
    plaster = p["plaster"]
    # 台基
    box(mb, "castle_stone", -hw - 0.12, -d * 0.5 - 0.12, 0.0, hw + 0.12, d * 0.5 + 0.12, PLINTH)
    z = PLINTH
    storeys = []
    for k in range(floors):
        h = GROUND_H if k == 0 else UPPER_H
        yd = d * 0.5 + j * k
        storeys.append((z, h, yd))
        z += h
    top_z = z
    door_s = hw + p["door_x"] * w - 0.0
    for k, (zb, h, yd) in enumerate(storeys):
        stone = k == 0 and p["ground"] == "stone"
        key = "castle_stone" if stone else plaster
        ws = walls_box(mb, key, -hw, -yd, zb, hw, yd, zb + h)
        frame = "castle_stone" if stone else "timber"
        lengths = {"front": w, "back": w, "left": 2 * yd, "right": 2 * yd}
        win_h = 1.0 if k == 0 else 0.9
        win_z = 0.9 if k == 0 else 0.7
        for side, wall in ws.items():
            L = lengths[side]
            skip = []
            # 窗户位置
            if side in ("front", "back"):
                n = max(1, int((L - 1.0) / 2.0))
                xs = [L * (i + 0.5) / n for i in range(n)]
            else:
                n = 1 if L < 6.0 else 2
                xs = [L * (i + 0.5) / n for i in range(n)]
            if side == "front" and k == 0:
                skip.append((door_s - door_w * 0.5 - 0.25, door_s + door_w * 0.5 + 0.25))
                xs = [x for x in xs if abs(x - door_s) > door_w * 0.5 + 0.75]
                if not xs and L > 4.0:
                    xs = [door_s - 1.8 if door_s > L * 0.5 else door_s + 1.8]
            for x in xs:
                skip.append((x - 0.55, x + 0.55))
            if not stone:
                timber_frame(mb, wall, L, h, skip=skip, rng=rng)
            else:
                # 石砌角石：交替长短的浅色石块
                for zz in range(int(h / 0.45)):
                    ln = 0.45 if zz % 2 else 0.3
                    wall.box(mb, "cobble_wall", 0.0, zz * 0.45, ln, zz * 0.45 + 0.4, 0.0, 0.05)
                    wall.box(mb, "cobble_wall", L - ln, zz * 0.45, L, zz * 0.45 + 0.4, 0.0, 0.05)
            for x in xs:
                window_m(mb, wall, x, win_z, 0.36 if k else 0.42, win_h, shutters=p["shutters"] if not stone else "",
                         frame=frame)
            if side == "front" and k == 0:
                door_m(mb, wall, door_s, 0.0, door_w, 2.15, mat=p["door"], frame=frame, arched=stone, double=double_door)
        # 挑出：楼板下面一排搁栅头 + 托梁
        if k > 0 and j > 0:
            for sy in (-1, 1):
                y_in, y_out = sy * (yd - j), sy * yd
                n_j = int(w / 0.55)
                for i in range(n_j + 1):
                    x = -hw + 0.15 + (w - 0.3) * i / n_j
                    box(mb, "timber", x - 0.07, min(y_in, y_out), zb - 0.18, x + 0.07, max(y_in, y_out) + 0.0, zb)
                box(mb, "timber", -hw, min(y_out, y_out - sy * 0.2), zb - 0.22, hw, max(y_out, y_out - sy * 0.2), zb)
                mb.face("roof_under", [(-hw, y_in, zb - 0.18), (hw, y_in, zb - 0.18), (hw, y_out, zb - 0.18), (-hw, y_out, zb - 0.18)], (0, 0, -1))
    # 屋顶
    yd_top = storeys[-1][2]
    roof = p["roof"]
    thatch = roof == "thatch"
    if p["gable_front"]:
        ridge, gables = gable_roof(mb, roof, -yd_top, yd_top, -hw, hw, top_z, p["pitch"], axis="y",
                                   eave=0.4, gable=0.35, thatch=thatch)
    else:
        ridge, gables = gable_roof(mb, roof, -hw, hw, -yd_top, yd_top, top_z, p["pitch"], axis="x",
                                   eave=0.45, gable=0.3, thatch=thatch)
    for sa, tri in gables:
        if p["gable_front"]:
            n = (0, sa, 0)
        else:
            n = (sa, 0, 0)
        mb.face(plaster, tri, n)
        _gable_frame(mb, tri, n, p["gable_front"] and sa < 0, p["shutters"])
    # 烟囱
    top = ridge
    if p["chimney"]:
        if p["gable_front"]:
            cx, cy = hw * 0.45, yd_top * 0.35
            half = hw
            zr = top_z + (half - abs(cx)) * math.tan(math.radians(p["pitch"]))
        else:
            cx, cy = (hw - 0.9) * (1 if rng.random() < 0.5 else -1), yd_top * 0.3
            zr = top_z + (yd_top - abs(cy)) * math.tan(math.radians(p["pitch"]))
        chimney(mb, cx, cy, top_z - 0.5, max(zr, ridge - 0.6) + 1.1)
        top = max(top, zr + 1.3)
    # 门前石阶
    box(mb, "castle_stone", door_s - hw - 0.8 if False else -hw + door_s - 0.8, -d * 0.5 - 0.55, 0.0,
        -hw + door_s + 0.8, -d * 0.5 - 0.12, 0.16)
    eave = 0.45
    fw = w + (0.7 if not p["gable_front"] else 0.8)
    fd = 2 * yd_top + (0.9 if not p["gable_front"] else 0.7)
    info = {
        "footprint": [round(fw, 2), round(max(fd, d + 0.7), 2)],
        "height": round(top, 2),
        "door": [round(-hw + door_s, 2), -d * 0.5, 0.0],
        "params": {k: (round(v, 3) if isinstance(v, float) else v) for k, v in p.items()},
    }
    return info


def _gable_frame(mb, tri, n, front, shutters):
    """山墙三角的木构：中柱 + 一道系梁 + 两根斜撑（沿屋面），朝街的山墙开一扇小窗"""
    import numpy as np
    a, b, c = (np.asarray(t, dtype=float) for t in tri)
    u = b - a
    L = float(np.linalg.norm(u))
    u /= L
    nn = np.asarray(n, dtype=float)
    # 让 u 从外面看指向右：cross(u, up) 应该 = -n
    if np.dot(np.cross(u, np.array([0.0, 0.0, 1.0])), nn) > 0:
        a, b = b, a
        u = -u
    wall = Wall(a, u, nn)
    hgt = c[2] - a[2]
    wall.beam(mb, "timber", 0.12, 0.12, L * 0.5, hgt - 0.1, 0.16, 0.06)
    wall.beam(mb, "timber", L - 0.12, 0.12, L * 0.5, hgt - 0.1, 0.16, 0.06)
    zc = hgt * 0.45
    half = L * 0.5 * (1 - zc / hgt)
    wall.beam(mb, "timber", L * 0.5 - half + 0.1, zc, L * 0.5 + half - 0.1, zc, 0.15, 0.06)
    if front and hgt > 2.4:
        window_m(mb, wall, L * 0.5, zc + 0.25, 0.3, 0.75, shutters=shutters)
        wall.beam(mb, "timber", L * 0.5, 0.12, L * 0.5, zc, 0.15, 0.06)
    else:
        wall.beam(mb, "timber", L * 0.5, 0.12, L * 0.5, hgt - 0.3, 0.16, 0.06)
        for sx in (-1, 1):
            wall.beam(mb, "timber", L * 0.5 + sx * 0.1, 0.2, L * 0.5 + sx * half * 0.9, zc - 0.05, 0.12, 0.05)
