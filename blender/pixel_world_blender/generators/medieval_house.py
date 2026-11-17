"""中世纪海边小镇的石砌联排楼（参考 res/中世纪海边小镇.jpg）：米白石灰岩 / 奶油色灰泥墙，鲜红瓦顶（双坡或四坡），
圆拱窗（铅条玻璃，夜里亮灯）、楼层之间的石腰线、转角角石、檐口线脚；部分变体在转角挑出一座红锥顶小圆塔，
部分底层是拱形店面 + 红白条纹遮阳棚。2~4 层。
正门朝 -Y（导出后 Godot +Z）；墙体占 x ∈ [-width/2, width/2]、y ∈ [-depth/2, depth/2]；门底边中点 (door_x, -depth/2, 0.25)。
info.footprint = 含屋檐 / 圆塔 / 遮阳棚的外廓；params 里有 width / depth / floors（catalog 的 variant_info 用）。"""
import math
import random

from ..builder import MeshBuilder
from ._medieval import Wall, box, chimney, cone_roof, door_m, gable_roof, hip_roof, walls_box, window_m

NAME = "中世纪石砌楼房"
CATEGORY = "buildings"
DESC = "Blender 生成的中世纪海滨楼房：米白石墙或奶油色灰泥墙、鲜红瓦顶、圆拱铅条窗、石腰线和角石，有的转角挑出红锥顶小圆塔，有的底层是拱形店面和条纹遮阳棚。"
VARY = "宽 6~10 米、深 6~8 米、2~4 层、墙面（石砌 / 灰泥）、屋顶（双坡 / 山墙朝街 / 四坡）、转角圆塔、底层店面和遮阳棚、门的位置、烟囱随变体变化。"
TAGS = ["town", "medieval"]
VARIANTS = 8

GROUND_H = 3.0
UPPER_H = 2.7
PLINTH = 0.25


def params(seed):
    r = random.Random(seed * 1543 + 71)
    k = seed - 1
    p = {
        "width": round(r.uniform(6.0, 10.0) * 2) / 2,
        "depth": round(r.uniform(6.0, 8.0) * 2) / 2,
        "floors": [3, 2, 4, 2, 3, 3, 2, 4][k % 8],
        "ground": "stone",
        "plaster": ["plaster_cream", "castle_stone", "plaster_cream", "plaster_cream", "castle_stone", "plaster_cream",
                    "castle_stone", "plaster_cream"][k % 8],
        "roof": "tile_red",
        "roof_type": ["hip", "gable", "gable_front", "hip", "gable", "hip", "gable_front", "gable"][k % 8],
        "pitch": r.uniform(36.0, 44.0),
        "jetty": 0.0,
        "gable_front": False,
        "turret": k % 8 in (0, 2, 5, 7),
        "turret_side": 1 if k % 2 == 0 else -1,
        "shop": k % 8 in (1, 2, 4, 6),
        "awning": ["canvas_red", "canvas_ochre", "canvas_red", "canvas_teal"][k % 4],
        "door_x": r.choice([-1.0, 0.0, 1.0]) * 0.18,
        "chimney": r.random() < 0.7,
        "shutters": "",
        "door": r.choice(["door_wood", "door_wood", "door_red", "door_teal"]),
    }
    p["gable_front"] = p["roof_type"] == "gable_front"
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
    hw, hd = w * 0.5, d * 0.5
    wall_key = p["plaster"]
    trim = "cobble_wall"
    box(mb, trim, -hw - 0.14, -hd - 0.14, 0.0, hw + 0.14, hd + 0.14, PLINTH)
    z = PLINTH
    storeys = []
    for k in range(floors):
        h = GROUND_H if k == 0 else UPPER_H
        storeys.append((z, h))
        z += h
    top_z = z
    door_s = hw + p["door_x"] * w
    shop = p.get("shop", False)
    tur = p.get("turret", False)
    ts = p.get("turret_side", 1)
    for k, (zb, h) in enumerate(storeys):
        key = "castle_stone" if k == 0 else wall_key
        ws = walls_box(mb, key, -hw, -hd, zb, hw, hd, zb + h)
        if k > 0:  # 楼层之间的石腰线
            box(mb, trim, -hw - 0.07, -hd - 0.07, zb - 0.09, hw + 0.07, hd + 0.07, zb + 0.09)
        lengths = {"front": w, "back": w, "left": d, "right": d}
        for side, wall in ws.items():
            L = lengths[side]
            # 转角角石
            for zz in range(int(h / 0.5)):
                ln = 0.5 if zz % 2 else 0.32
                wall.box(mb, trim, 0.0, zz * 0.5 + 0.04, ln, zz * 0.5 + 0.46, 0.0, 0.05)
                wall.box(mb, trim, L - ln, zz * 0.5 + 0.04, L, zz * 0.5 + 0.46, 0.0, 0.05)
            n = max(1, int((L - 1.2) / 1.9))
            xs = [L * (i + 0.5) / n for i in range(n)]
            if side == "front" and k == 0:
                xs = [x for x in xs if abs(x - door_s) > door_w * 0.5 + 0.9]
                door_m(mb, wall, door_s, 0.0, door_w, 2.3, mat=p["door"], frame=trim, arched=True, double=double_door)
                if shop:  # 拱形店面：大拱窗
                    for x in xs:
                        window_m(mb, wall, x, 0.55, 0.62, 1.9, shutters="", frame=trim, arched=True)
                    continue
            if tur and side == "front" and k > 0:  # 圆塔挡住的那一格不开窗
                xs = [x for x in xs if abs(x - (L if ts > 0 else 0.0)) > 1.5]
            for x in xs:
                window_m(mb, wall, x, 0.8 if k else 1.0, 0.34 if k else 0.4, 1.35 if k else 1.3, shutters="", frame=trim,
                         arched=True)
    # 屋顶
    rt = p.get("roof_type", "gable")
    roof = p["roof"]
    box(mb, trim, -hw - 0.1, -hd - 0.1, top_z - 0.22, hw + 0.1, hd + 0.1, top_z)
    if rt == "hip":
        ridge = hip_roof(mb, roof, -hw, hw, -hd, hd, top_z, p["pitch"], eave=0.45)
        gables = []
    elif rt == "gable_front":
        ridge, gables = gable_roof(mb, roof, -hd, hd, -hw, hw, top_z, p["pitch"], axis="y", eave=0.4, gable=0.3,
                                   fascia=trim, cap="tile_darkred")
    else:
        ridge, gables = gable_roof(mb, roof, -hw, hw, -hd, hd, top_z, p["pitch"], axis="x", eave=0.45, gable=0.3,
                                   fascia=trim, cap="tile_darkred")
    for sa, tri in gables:
        n = (0, sa, 0) if rt == "gable_front" else (sa, 0, 0)
        mb.face(wall_key, tri, n)
        if rt == "gable_front" and sa < 0 and ridge - top_z > 2.0:
            gw = Wall((-hw, -hd, top_z), (1, 0, 0), (0, -1, 0))
            window_m(mb, gw, hw, 0.5, 0.3, 1.0, shutters="", frame=trim, arched=True)
    top = ridge
    # 烟囱
    if p["chimney"]:
        cx = (hw - 1.0) * (-ts)
        cy = hd * 0.35
        chimney(mb, cx, cy, top_z - 0.4, ridge + 0.7, s=0.34)
        top = max(top, ridge + 0.9)
    # 转角小圆塔：从二层起挑出，红锥顶
    ext_x = 0.0
    if tur and floors > 1:
        tr = 1.05
        cx, cy = ts * (hw - 0.15), -hd + 0.15
        z0 = storeys[1][0]
        mb.frustum(trim, cx, cy, z0 - 1.0, z0, 0.35, tr + 0.05, 12, math.pi / 12, top=False, bottom=True)
        th = top_z + 1.3
        mb.frustum(wall_key, cx, cy, z0, th, tr, tr, 12, math.pi / 12, top=False)
        for zz in [s[0] for s in storeys[2:]] + [th - 0.1]:
            mb.frustum(trim, cx, cy, zz - 0.09, zz + 0.09, tr + 0.07, tr + 0.07, 12, math.pi / 12, top=True, bottom=True)
        # 塔上的小拱窗（朝前和朝外两面）
        for zb, h in storeys[1:]:
            for a in (-math.pi / 2, 0.0 if ts > 0 else math.pi):
                nx, ny = math.cos(a), math.sin(a)
                apo = tr * math.cos(math.pi / 12) + 0.012
                u = (-ny, nx, 0.0) if a != -math.pi / 2 else (1, 0, 0)
                if a != -math.pi / 2:
                    u = (0, 1, 0) if ts > 0 else (0, -1, 0)
                c0 = (cx + nx * apo - u[0] * 0.3, cy + ny * apo - u[1] * 0.3, zb)
                window_m(mb, Wall(c0, u, (nx, ny, 0)), 0.3, 0.9, 0.2, 1.1, shutters="", frame=trim, arched=True)
        top = max(top, cone_roof(mb, cx, cy, th, tr + 0.3, 3.4, key=roof))
        ext_x = tr
    # 遮阳棚（店面）
    front_ext = 0.55
    if shop:
        aw = p.get("awning", "canvas_red")
        x0, x1 = -hw + 0.3, hw - 0.3
        y0, y1 = -hd - 0.03, -hd - 1.5
        z_hi, z_lo = PLINTH + GROUND_H - 0.25, PLINTH + 2.25
        mb.face(aw, [(x0, y0, z_hi), (x1, y0, z_hi), (x1, y1, z_lo), (x0, y1, z_lo)], (0, -0.4, 1))
        mb.face(aw, [(x0, y0, z_hi - 0.03), (x0, y1, z_lo - 0.03), (x1, y1, z_lo - 0.03), (x1, y0, z_hi - 0.03)], (0, 0.4, -1))
        mb.face(aw, [(x0, y1, z_lo), (x1, y1, z_lo), (x1, y1, z_lo - 0.28), (x0, y1, z_lo - 0.28)], (0, -1, 0))
        for x in (x0 + 0.1, x1 - 0.1):
            box(mb, "timber", x - 0.05, y1 + 0.06, 0.0, x + 0.05, y1 + 0.16, z_lo)
        front_ext = 1.6
    # 门前石阶
    box(mb, trim, -hw + door_s - 0.85, -hd - 0.55, 0.0, -hw + door_s + 0.85, -hd - 0.12, 0.16)
    fw = w + 0.9 + ext_x
    fd = d + 0.45 + max(0.45, front_ext, ext_x)
    info = {
        "footprint": [round(fw, 2), round(fd, 2)],
        "height": round(top, 2),
        "door": [round(-hw + door_s, 2), -hd, 0.0],
        "params": {k: (round(v, 3) if isinstance(v, float) else v) for k, v in p.items()},
    }
    return info
