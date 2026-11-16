"""柴火垛：一层层码放的劈柴（截面朝前后，端面是浅色年轮木），两端用木桩挡住，有的上面盖一块小木板棚。
柴垛沿 X 展开，端面朝 ±Y（正面 -Y = Godot +Z）。原点在柴垛中心地面。"""
import math
import random

from ..builder import MeshBuilder
from ._medieval import box

NAME = "柴火垛"
CATEGORY = "props"
DESC = "Blender 生成的柴火垛：一层层码放的劈柴，两端木桩挡住，有的带小木板棚，靠在房屋和铁匠铺墙边。"
VARY = "长度、层数、有没有小棚子、劈柴的大小随变体变化。"
TAGS = ["town", "medieval", "yard", "forest"]
VARIANTS = 3


def build(seed, **over):
    k = seed - 1
    r = random.Random(seed * 53 + 2)
    length = [1.8, 2.4, 1.4][k % 3]
    rows = [4, 5, 3][k % 3]
    roof = k % 3 != 2
    depth = 0.55
    mb = MeshBuilder()
    box(mb, "timber", -length * 0.5 - 0.05, -depth * 0.5, 0.0, length * 0.5 + 0.05, depth * 0.5, 0.08)
    rad = 0.075
    z = 0.08 + rad
    for row in range(rows):
        n = int(length / (rad * 2.05))
        off = rad if row % 2 else 0.0
        for i in range(n):
            x = -length * 0.5 + rad + off + i * rad * 2.05
            if x > length * 0.5 - rad:
                break
            rr = rad * r.uniform(0.85, 1.05)
            y0, y1 = -depth * 0.5 + r.uniform(-0.04, 0.02), depth * 0.5 + r.uniform(-0.02, 0.04)
            mb.tube("trunk", (x, y0, z), (x, y1, z), rr, rr, 6, 0.0, caps=False)
            for yy, nn in ((y0, -1), (y1, 1)):
                pts = [(x + math.cos(r_a) * rr, yy, z + math.sin(r_a) * rr) for r_a in [r.uniform(0, 0) + j * math.pi / 3 for j in range(6)]]
                mb.face("crate", pts, (0, nn, 0))
        z += rad * 1.8
    top = z - rad * 0.8
    for sx in (-1, 1):
        x = sx * (length * 0.5 + 0.08)
        box(mb, "timber", x - 0.05, -0.05, 0.0, x + 0.05, 0.05, top + (0.25 if roof else 0.05))
    if roof:
        zt = top + 0.25
        mb.face("boards", [(-length * 0.5 - 0.25, -depth * 0.5 - 0.2, zt - 0.12), (length * 0.5 + 0.25, -depth * 0.5 - 0.2, zt - 0.12),
                           (length * 0.5 + 0.25, depth * 0.5 + 0.15, zt + 0.08), (-length * 0.5 - 0.25, depth * 0.5 + 0.15, zt + 0.08)], (0, -0.4, 1))
        box(mb, "timber", -length * 0.5 - 0.25, -depth * 0.5 - 0.2, zt - 0.17, length * 0.5 + 0.25, -depth * 0.5 - 0.14, zt - 0.1)
        top = zt + 0.1
    return mb, {"footprint": [round(length + 0.5, 2), round(depth + 0.4, 2)], "height": round(top, 2),
                "params": {"length": length, "rows": rows, "roof": roof}}
