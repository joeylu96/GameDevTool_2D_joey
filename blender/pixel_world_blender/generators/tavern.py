"""酒馆 / 客栈：大号的半木构楼（约 10 × 8 米、2~3 层），石砌底层，双开木门上方一个木雨棚（两根柱子撑着），
门边铁支架上挂着画了酒杯的招牌，门前摆长凳和木桶。正门朝 -Y（导出后 Godot +Z）。整体按外廓（含门廊）居中，门底边中点见 info.door。"""
import random

from ..builder import MeshBuilder
from ._medieval import box, prism, recenter_y
from .medieval_house import build_house, params as house_params

NAME = "酒馆"
CATEGORY = "buildings"
DESC = "Blender 生成的中世纪酒馆：石砌底层的大号半木构楼，双开木门、门廊雨棚、铁支架上挂着酒杯招牌，门前长凳和酒桶。"
VARY = "宽 10~11 米、深 7.5~8 米、2 或 3 层、灰泥颜色、屋顶（青石板 / 红瓦）、屋脊方向、招牌颜色随变体变化。"
TAGS = ["town", "medieval", "plaza"]
VARIANTS = 4


def build(seed, **over):
    r = random.Random(seed * 977 + 3)
    p = house_params(seed + 40)
    p.update({
        "width": [10.0, 11.0, 10.5, 10.0][(seed - 1) % 4],
        "depth": [7.5, 8.0, 7.5, 8.0][(seed - 1) % 4],
        "floors": [2, 3, 3, 2][(seed - 1) % 4],
        "ground": "stone",
        "roof": ["slate", "roof_red", "slate", "roof_red"][(seed - 1) % 4],
        "plaster": ["plaster_white", "plaster_ochre", "plaster_white", "plaster_ochre"][(seed - 1) % 4],
        "gable_front": (seed - 1) % 4 == 2,
        "door_x": 0.0,
        "chimney": True,
        "jetty": r.uniform(0.3, 0.4),
    })
    p.update(over)
    mb = MeshBuilder()
    info = build_house(mb, p, random.Random(seed * 7 + 1), door_w=1.7, double_door=True)
    hd = p["depth"] * 0.5
    yf = -hd
    # 门廊雨棚：两根柱子 + 斜坡小屋顶
    cy0, cy1 = yf, yf - 1.6
    z_hi, z_lo = 3.0, 2.55
    for sx in (-1, 1):
        x = sx * 1.6
        box(mb, "timber", x - 0.09, cy1 + 0.05, 0.0, x + 0.09, cy1 + 0.23, z_lo)
        prism(mb, "timber", [(x - 0.06, cy1 + 0.14, z_lo - 0.6), (x - 0.06, yf - 0.02, z_hi - 0.05),
                             (x - 0.06, yf - 0.02, z_hi - 0.25), (x - 0.06, cy1 + 0.14, z_lo - 0.8)], None, None, (1, 0, 0), 0.12)
    roof = p["roof"] if p["roof"] != "thatch" else "slate"
    mb.face(roof, [(-1.9, cy0, z_hi + 0.1), (1.9, cy0, z_hi + 0.1), (1.9, cy1 - 0.15, z_lo), (-1.9, cy1 - 0.15, z_lo)], (0, -0.4, 1))
    mb.face("roof_under", [(-1.9, cy0, z_hi - 0.02), (1.9, cy0, z_hi - 0.02), (1.9, cy1 - 0.15, z_lo - 0.12), (-1.9, cy1 - 0.15, z_lo - 0.12)], (0, 0.3, -1))
    mb.face("timber", [(-1.9, cy1 - 0.15, z_lo), (1.9, cy1 - 0.15, z_lo), (1.9, cy1 - 0.15, z_lo - 0.12), (-1.9, cy1 - 0.15, z_lo - 0.12)], (0, -1, 0))
    for sx in (-1, 1):
        mb.face("timber", [(sx * 1.9, cy0, z_hi + 0.1), (sx * 1.9, cy1 - 0.15, z_lo), (sx * 1.9, cy1 - 0.15, z_lo - 0.12), (sx * 1.9, cy0, z_hi - 0.02)], (sx, 0, 0))
    box(mb, "timber", -1.9, cy1 + 0.05, z_lo - 0.22, 1.9, cy1 + 0.23, z_lo - 0.04)
    # 招牌：墙上伸出的铁支架 + 两根吊链 + 木牌（酒杯图案）
    sx = 3.2 if p["width"] > 10.2 else 2.9
    zs = 4.2
    box(mb, "iron", sx - 0.05, yf - 1.25, zs - 0.04, sx + 0.05, yf, zs + 0.06)
    prism(mb, "iron", [(sx - 0.03, yf, zs - 0.6), (sx - 0.03, yf, zs - 0.5), (sx - 0.03, yf - 0.9, zs - 0.02), (sx - 0.03, yf - 1.0, zs - 0.02)], None, None, (1, 0, 0), 0.06)
    for yy in (yf - 0.35, yf - 1.05):
        box(mb, "iron", sx - 0.02, yy - 0.02, zs - 0.3, sx + 0.02, yy + 0.02, zs)
    sign = ["cloth_red", "cloth_green", "door_wood", "cloth_blue"][(seed - 1) % 4]
    box(mb, "timber", sx - 0.06, yf - 1.2, zs - 1.15, sx + 0.06, yf - 0.2, zs - 0.28)
    box(mb, sign, sx - 0.08, yf - 1.12, zs - 1.07, sx + 0.08, yf - 0.28, zs - 0.36)
    # 酒杯图案（两面）
    for side in (-1, 1):
        x = sx + side * 0.085
        x2 = sx + side * 0.11
        box(mb, "cloth_gold", min(x, x2), yf - 0.85, zs - 0.95, max(x, x2), yf - 0.55, zs - 0.55)
        box(mb, "frame_white" if False else "snow", min(x, x2), yf - 0.85, zs - 0.62, max(x, x2), yf - 0.55, zs - 0.52)
        box(mb, "cloth_gold", min(x, x2), yf - 0.55, zs - 0.88, max(x, x2), yf - 0.47, zs - 0.62)
    # 门前长凳和酒桶
    for bx in (-3.3, 3.3):
        if abs(bx - sx) < 0.8:
            bx = -bx
        box(mb, "boards", bx - 0.8, yf - 0.75, 0.42, bx + 0.8, yf - 0.4, 0.5)
        for lx in (-0.65, 0.65):
            box(mb, "timber", bx + lx - 0.05, yf - 0.7, 0.0, bx + lx + 0.05, yf - 0.45, 0.42)
    for bx, by in ((-4.4, yf - 0.6), (-4.6, yf - 1.35), (4.5, yf - 0.7)):
        if abs(bx) > p["width"] * 0.5 + 0.3:
            bx = (p["width"] * 0.5 - 0.5) * (1 if bx > 0 else -1)
        mb.frustum("barrel", bx, by, 0.0, 0.45, 0.3, 0.35, 10, 0.0, top=False)
        mb.frustum("barrel", bx, by, 0.45, 0.9, 0.35, 0.3, 10, 0.0, top=True)
        for zz in (0.18, 0.72):
            mb.frustum("iron", bx, by, zz - 0.03, zz + 0.03, 0.335, 0.335, 10, 0.0, top=False)
    # 整体按外廓（含门廊和长凳）居中
    yd_top = hd + p["jetty"] * (p["floors"] - 1)
    yfront, yback = min(cy1 - 0.3, -yd_top - 0.45), yd_top + 0.45
    dy = recenter_y(mb, yfront, yback)
    info["footprint"] = [info["footprint"][0], round(yback - yfront, 2)]
    info["door"] = [0.0, round(-hd + dy, 2), 0.0]
    return mb, info
