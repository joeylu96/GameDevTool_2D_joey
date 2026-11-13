"""灯塔：石砌底座 + 红白相间、往上收的圆塔身 + 门和一串小窗 + 观景平台（栏杆）+ 玻璃灯室（夜里发光）+ 红色圆顶。"""
import math
import random

from ..builder import MeshBuilder

NAME = "灯塔"
CATEGORY = "landmarks"
DESC = "Blender 生成的灯塔：石砌底座、红白条纹的塔身、观景平台和玻璃灯室，夜里灯室发光。"
VARY = "高度、条纹数量和颜色（红白 / 灰白）、塔身收分、栏杆柱数随种子变化。"
TAGS = ["shore", "island", "town"]


def build(seed, **over):
    r = random.Random(seed)
    mb = MeshBuilder()
    height = r.uniform(7.0, 9.0)
    r0 = r.uniform(1.35, 1.6)
    r1 = r0 * r.uniform(0.6, 0.7)
    bands = r.choice([4, 5, 6])
    stripe = r.choice(["plaster_red", "plaster_red", "stone"])
    sides = 14
    base_h = 0.7
    # 底座：八角形石台 + 台阶
    mb.frustum("stone", 0, 0, 0.0, base_h, r0 + 0.5, r0 + 0.4, 8, math.pi / 8, top=True)
    mb.box("stone", (-0.7, -(r0 + 1.0), 0.0), (0.7, -(r0 + 0.4), 0.35))
    # 塔身：红白相间的条带，每条一段棱台，半径线性收小
    z = base_h
    seg = (height - base_h) / bands
    for i in range(bands):
        ra = r0 + (r1 - r0) * (i / bands)
        rb = r0 + (r1 - r0) * ((i + 1) / bands)
        mb.frustum("plaster_white" if i % 2 == 0 else stripe, 0, 0, z, z + seg, ra, rb, sides, 0, top=(i == bands - 1))
        z += seg
    # 门（正面 -Y）+ 门楣
    fy = -r0 * math.cos(math.pi / sides) + 0.02
    mb.box("door", (-0.45, fy - 0.08, base_h), (0.45, fy, base_h + 1.9))
    mb.box("trim", (-0.55, fy - 0.12, base_h + 1.9), (0.55, fy, base_h + 2.02))
    # 一串小窗：沿高度交替在正面和侧面
    for k in range(3):
        zz = base_h + 2.6 + k * (height - base_h - 3.2) / 3
        frac = (zz - base_h) / (height - base_h)
        rr = r0 + (r1 - r0) * frac
        ang = -math.pi / 2 + (k % 2) * 0.9
        cx, cy = math.cos(ang) * (rr - 0.02), math.sin(ang) * (rr - 0.02)
        nx, ny = math.cos(ang), math.sin(ang)
        tx, ty = -ny, nx
        w2, h2 = 0.22, 0.4
        pts = [(cx - tx * w2 + nx * 0.03, cy - ty * w2 + ny * 0.03, zz), (cx + tx * w2 + nx * 0.03, cy + ty * w2 + ny * 0.03, zz),
               (cx + tx * w2 + nx * 0.03, cy + ty * w2 + ny * 0.03, zz + h2), (cx - tx * w2 + nx * 0.03, cy - ty * w2 + ny * 0.03, zz + h2)]
        mb.face("glass", pts, (nx, ny, 0))
    # 观景平台 + 栏杆
    deck = height
    mb.frustum("metal_green", 0, 0, deck, deck + 0.15, r1 + 0.55, r1 + 0.6, sides, 0, top=True, bottom=True)
    posts = r.choice([12, 14, 16])
    for k in range(posts):
        a = 2 * math.pi * k / posts
        px, py = math.cos(a) * (r1 + 0.5), math.sin(a) * (r1 + 0.5)
        mb.tube("metal_green", (px, py, deck + 0.15), (px, py, deck + 0.85), 0.025, 0.025, 4)
    mb.frustum("metal_green", 0, 0, deck + 0.8, deck + 0.88, r1 + 0.52, r1 + 0.52, sides, 0, top=True, bottom=True)
    # 灯室：玻璃 + 竖框
    lr = r1 * 0.75
    mb.frustum("bulb", 0, 0, deck + 0.15, deck + 1.35, lr, lr, 10, 0, top=False)
    for k in range(10):
        a = 2 * math.pi * k / 10
        mb.tube("metal", (math.cos(a) * lr, math.sin(a) * lr, deck + 0.15), (math.cos(a) * lr, math.sin(a) * lr, deck + 1.35),
                0.03, 0.03, 4)
    # 圆顶 + 顶针
    roof = r.choice(["roof_red", "roof_red", "roof_grey"])
    mb.frustum(roof, 0, 0, deck + 1.35, deck + 1.55, lr + 0.25, lr + 0.15, 12, 0, top=False, bottom=True)
    mb.frustum(roof, 0, 0, deck + 1.55, deck + 2.25, lr + 0.15, 0.0, 12, 0, top=False)
    mb.tube("metal", (0, 0, deck + 2.2), (0, 0, deck + 2.7), 0.03, 0.0, 4)
    return mb, {"footprint": [2 * (r0 + 0.5), 2 * (r0 + 1.0)], "height": deck + 2.7}
