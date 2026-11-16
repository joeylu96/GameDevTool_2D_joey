"""铁匠铺：三面敞开的木棚（6 根木柱 + 双坡屋顶），后墙是半高石墙；后角一座石砌锻炉（炉膛里的炭火夜里发光）
连着穿出屋顶的石烟囱，前面木墩上一个铁砧，旁边淬火水桶、工具架（挂着锤子、钳子）和一小堆铁锭。
敞开的一面朝 -Y（导出后 Godot +Z），原点在占地中心。"""
import math
import random

from ..builder import MeshBuilder
from ._medieval import box, chimney, gable_roof

NAME = "铁匠铺"
CATEGORY = "buildings"
DESC = "Blender 生成的中世纪铁匠铺：三面敞开的木棚、半高石后墙，石砌锻炉的炭火夜里发光，铁砧、淬火水桶、挂着锤钳的工具架。"
VARY = "屋顶（茅草 / 红瓦 / 青石板）、锻炉在左还是右、棚子大小随变体变化。"
TAGS = ["town", "medieval", "yard"]
VARIANTS = 3


def build(seed, **over):
    k = seed - 1
    r = random.Random(seed * 211 + 4)
    p = {
        "width": [6.0, 6.5, 5.5][k % 3],
        "depth": [5.0, 5.5, 4.8][k % 3],
        "roof": ["thatch", "roof_red", "slate"][k % 3],
        "forge_side": [1, -1, 1][k % 3],
    }
    p.update(over)
    mb = MeshBuilder()
    w, d = p["width"], p["depth"]
    hw, hd = w * 0.5, d * 0.5
    eave_h = 2.7
    # 地面：夯土 / 石板
    box(mb, "cobble_wall", -hw - 0.1, -hd - 0.1, 0.0, hw + 0.1, hd + 0.1, 0.12)
    # 柱子 + 檐梁
    for x in (-hw + 0.15, 0.0, hw - 0.15):
        for y in (-hd + 0.15, hd - 0.15):
            box(mb, "timber", x - 0.11, y - 0.11, 0.12, x + 0.11, y + 0.11, eave_h)
            box(mb, "castle_stone", x - 0.17, y - 0.17, 0.12, x + 0.17, y + 0.17, 0.35)
    for y in (-hd + 0.15, hd - 0.15):
        box(mb, "timber", -hw, y - 0.12, eave_h - 0.22, hw, y + 0.12, eave_h)
    for x in (-hw + 0.15, hw - 0.15):
        box(mb, "timber", x - 0.12, -hd, eave_h - 0.22, x + 0.12, hd, eave_h)
        # 角撑
        for y, sy in ((-hd + 0.15, 1), (hd - 0.15, -1)):
            mb.tube("timber", (x, y, eave_h - 0.9), (x, y + sy * 0.7, eave_h - 0.2), 0.06, 0.06, 4, math.pi / 4)
    # 半高石后墙 + 侧面矮墙（锻炉那一侧）
    box(mb, "castle_stone", -hw + 0.05, hd - 0.35, 0.12, hw - 0.05, hd - 0.05, 1.5)
    fs = p["forge_side"]
    box(mb, "castle_stone", fs * (hw - 0.35), -0.2, 0.12, fs * (hw - 0.05), hd - 0.05, 1.5)
    # 屋顶
    thatch = p["roof"] == "thatch"
    ridge, gables = gable_roof(mb, p["roof"], -hw, hw, -hd, hd, eave_h, 40.0 if not thatch else 48.0, axis="x",
                               eave=0.55, gable=0.45, thatch=thatch)
    for sa, tri in gables:
        mb.face("boards", tri, (sa, 0, 0))
    # 锻炉：石台 + 炉膛炭火 + 炉罩 + 烟囱
    fx, fy = fs * (hw - 1.15), hd - 1.0
    box(mb, "cobble_wall", fx - 0.8, fy - 0.6, 0.12, fx + 0.8, fy + 0.6, 0.95)
    box(mb, "forge_coal", fx - 0.5, fy - 0.35, 0.95, fx + 0.5, fy + 0.25, 1.02)
    for (a0, a1, b0, b1) in ((-0.8, -0.5, -0.6, 0.6), (0.5, 0.8, -0.6, 0.6), (-0.5, 0.5, 0.25, 0.6)):
        box(mb, "castle_stone", fx + a0, fy + b0, 0.95, fx + a1, fy + b1, 1.12)
    # 炉罩（下宽上窄）
    mb.frustum("cobble_wall", fx, fy + 0.15, 1.9, 2.6, 0.75, 0.42, 4, math.pi / 4, top=False, bottom=True)
    chimney(mb, fx, fy + 0.15, 2.55, ridge + 0.9, s=0.33)
    # 风箱
    box(mb, "barrel", fx - fs * 1.2 - 0.3, fy - 0.2, 0.55, fx - fs * 1.2 + 0.3, fy + 0.45, 0.75)
    box(mb, "timber", fx - fs * 1.2 - 0.05, fy + 0.45, 0.6, fx - fs * 1.2 + 0.05, fy + 0.9, 0.7)
    # 铁砧（木墩上）
    ax, ay = fx - fs * 1.6, -0.6
    mb.frustum("trunk", ax, ay, 0.12, 0.62, 0.3, 0.28, 8, 0.0, top=True)
    box(mb, "iron", ax - 0.16, ay - 0.12, 0.62, ax + 0.16, ay + 0.12, 0.72)
    box(mb, "iron", ax - 0.09, ay - 0.08, 0.72, ax + 0.09, ay + 0.08, 0.8)
    box(mb, "iron", ax - 0.3, ay - 0.14, 0.8, ax + 0.26, ay + 0.14, 0.92)
    mb.tube("iron", (ax - 0.3, ay, 0.86), (ax - 0.52, ay, 0.88), 0.07, 0.02, 4, math.pi / 4)
    # 锤子放在砧上
    box(mb, "trunk", ax - 0.05, ay - 0.3, 0.93, ax + 0.0, ay + 0.1, 0.97)
    box(mb, "iron", ax - 0.08, ay + 0.06, 0.92, ax + 0.03, ay + 0.18, 1.0)
    # 淬火水桶
    bx, by = ax + fs * 0.9, ay + 0.3
    mb.frustum("barrel", bx, by, 0.12, 0.72, 0.32, 0.36, 10, 0.0, top=False)
    mb.frustum("water", bx, by, 0.66, 0.67, 0.33, 0.33, 10, 0.0, top=True)
    for zz in (0.3, 0.6):
        mb.frustum("iron", bx, by, zz - 0.03, zz + 0.03, 0.355, 0.36, 10, 0.0, top=False)
    # 工具架（靠后墙另一侧）：横杆 + 挂着的工具
    tx = -fs * (hw - 1.4)
    box(mb, "timber", tx - 0.9, hd - 0.45, 1.75, tx + 0.9, hd - 0.35, 1.85)
    for x in (tx - 0.85, tx + 0.85):
        box(mb, "timber", x - 0.05, hd - 0.45, 0.12, x + 0.05, hd - 0.35, 1.85)
    for i in range(5):
        x = tx - 0.6 + i * 0.3
        ln = r.uniform(0.45, 0.75)
        box(mb, "trunk", x - 0.025, hd - 0.48, 1.75 - ln, x + 0.025, hd - 0.44, 1.75)
        box(mb, "iron", x - 0.08, hd - 0.5, 1.75 - ln - 0.12, x + 0.08, hd - 0.43, 1.75 - ln)
    # 铁锭 / 废铁堆
    for i in range(4):
        ix, iy = tx + r.uniform(-0.6, 0.6), hd - 1.0 + r.uniform(-0.2, 0.2)
        box(mb, "iron", ix - 0.18, iy - 0.06, 0.12 + i % 2 * 0.07, ix + 0.18, iy + 0.06, 0.19 + i % 2 * 0.07)
    info = {
        "footprint": [round(w + 1.1, 2), round(d + 1.2, 2)],
        "height": round(ridge + 1.05, 2),
        "params": {k: (round(v, 3) if isinstance(v, float) else v) for k, v in p.items()},
    }
    return mb, info
