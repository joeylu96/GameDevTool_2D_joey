"""风车叶片：四片格栅叶片 + 帆布，中心在原点，叶片在 XZ 平面内、绕 Y 轴转（导出后 Godot 里在 XY 平面、绕 Z 轴转，
和 Godot 端 build_windmill_blades 一样）。装到 windmill_tower 的轮毂（Godot (0, 6.9, 1.85)）上。"""
import math

import numpy as np

from ..builder import MeshBuilder

NAME = "风车叶片"
CATEGORY = "landmarks"
DESC = "Blender 生成的风车叶片：四片木格栅叶片蒙着帆布，装在风车塔身的轮轴上转动。"
VARY = "帆布颜色（白 / 米黄条纹 / 红条纹）随变体变化。"
TAGS = ["plains"]
VARIANTS = 3


def build(seed, **over):
    k = (seed - 1) % 3
    sail = ("plaster_white", "canvas_ochre", "canvas_red")[k]
    mb = MeshBuilder()
    # 轮毂：沿 Y 的短圆柱
    mb.tube("roof_cap", (0, 0.05, 0), (0, -0.05, 0), 0.3, 0.3, 8, caps=True)
    for i in range(4):
        a = math.tau * i / 4 + 0.3
        d = np.array([math.cos(a), 0.0, math.sin(a)])
        side = np.array([-math.sin(a), 0.0, math.cos(a)])
        mb.tube("trunk", (0, 0, 0), tuple(d * 5.2), 0.07, 0.05, 4)
        for s in (0.15, 0.85):
            mb.tube("wall_wood", tuple(d * 1.0 + side * s), tuple(d * 5.0 + side * s), 0.03, 0.03, 4, caps=False)
        for t in range(9):
            dd = 1.0 + t * 0.5
            mb.tube("wall_wood", tuple(d * dd + side * 0.15), tuple(d * dd + side * 0.85), 0.025, 0.025, 4, caps=False)
        c0, c1 = d * 1.05 + side * 0.18, d * 4.95 + side * 0.18
        c2, c3 = d * 4.95 + side * 0.82, d * 1.05 + side * 0.82
        off_f = np.array([0.0, 0.02, 0.0])   # 帆布在格栅后面一点（+Y 是背面）
        off_b = np.array([0.0, 0.03, 0.0])
        mb.face(sail, [c0 + off_f, c1 + off_f, c2 + off_f, c3 + off_f], (0, -1, 0))
        mb.face(sail, [c0 + off_b, c3 + off_b, c2 + off_b, c1 + off_b], (0, 1, 0))
    return mb, {"footprint": [10.4, 0.4], "height": 5.2, "pivot": [0, 0, 0]}
