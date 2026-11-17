"""柴堆：劈好的圆木柴一层层码起来，两头各打一根木桩挡着，柴的截面朝外（-Y）。
变体 0 一小堆（宽 1.4 米），1 一长垛（宽 2.4 米、更高），2 长垛上面搭一片挡雨的旧瓦棚。原点在柴堆中心地面。"""
import math
import random

from ..builder import MeshBuilder
from ._medieval import box

NAME = "柴堆"
CATEGORY = "props"
DESC = "Blender 生成的柴堆：码得整整齐齐的圆木柴，两头木桩挡着，有的上面盖一片旧瓦挡雨。"
VARY = "变体 0 小堆、1 长垛、2 长垛带瓦棚。"
TAGS = ["cn_village", "yard"]
VARIANTS = 3


def build(seed, **over):
    k = (seed - 1) % 3
    r = random.Random(seed * 71 + 9)
    mb = MeshBuilder()
    w = [1.4, 2.4, 2.4][k]
    rows = [3, 4, 4][k]
    rad = 0.115
    ln = 0.7
    for sx in (-1, 1):
        mb.tube("trunk", (sx * (w * 0.5 + 0.06), 0.0, 0.0), (sx * (w * 0.5 + 0.06), 0.0, rows * rad * 1.75 + 0.3), 0.05, 0.045, 8)
    n = int(w / (rad * 2))
    top = 0.0
    for row in range(rows):
        z = rad + row * rad * 1.75
        off = rad if row % 2 else 0.0
        for i in range(n - (row % 2)):
            x = -w * 0.5 + rad + off + i * (w - 2 * rad) / max(1, n - 1)
            rr = rad * r.uniform(0.82, 1.08)
            y0 = -ln * 0.5 + r.uniform(-0.05, 0.05)
            mb.tube("trunk", (x, y0, z), (x, y0 + ln, z), rr, rr, 8, caps=False)
            # 两头的截面：浅色的年轮面
            ring = [(x + math.cos(math.tau * q / 8) * rr, z + math.sin(math.tau * q / 8) * rr) for q in range(8)]
            mb.face("wall_wood", [(px, y0, pz) for px, pz in ring], (0, -1, 0))
            mb.face("wall_wood", [(px, y0 + ln, pz) for px, pz in ring], (0, 1, 0))
        top = z + rad
    if k == 2:
        box(mb, "wall_wood", -w * 0.5 - 0.2, -0.5, top + 0.05, w * 0.5 + 0.2, 0.5, top + 0.1)
        pts = [(-w * 0.5 - 0.3, -0.6, top + 0.1), (w * 0.5 + 0.3, -0.6, top + 0.1), (w * 0.5 + 0.3, 0.6, top + 0.38), (-w * 0.5 - 0.3, 0.6, top + 0.38)]
        mb.face("tile_cn_dark", pts, (0, -0.2, 1))
        mb.face("roof_under", [(x, y, z - 0.06) for x, y, z in pts], (0, 0.2, -1))
        mb.face("tile_cn_dark", [pts[0], pts[1], (pts[1][0], pts[1][1], pts[1][2] - 0.06), (pts[0][0], pts[0][1], pts[0][2] - 0.06)], (0, -1, 0))
        top += 0.4
    return mb, {"footprint": [round(w + 0.4, 2), 0.9 if k < 2 else 1.3], "height": round(top, 2), "params": {"width": w}}
