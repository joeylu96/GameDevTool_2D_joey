"""现代长椅：变体 0 钢架木条椅（有靠背）、1 混凝土长凳配木坐板、2 钢板网格椅。坐的一面朝 -Y（导出后 Godot +Z），
原点在占地中心地面。"""
from ..builder import MeshBuilder
from ._medieval import box

NAME = "现代长椅"
CATEGORY = "street"
DESC = "Blender 生成的现代长椅：钢架木条椅、混凝土长凳配木坐板、钢板网格椅三种，摆在街边、公交站和广场上。"
VARY = "三种款式（变体 0 钢架木条、1 混凝土、2 钢板）。"
TAGS = ["town", "modern", "roadside", "plaza"]
VARIANTS = 3


def build(seed, **over):
    k = (seed - 1) % 3
    mb = MeshBuilder()
    L = [1.8, 2.0, 1.6][k]
    hl = L * 0.5
    if k == 0:
        for x in (-hl + 0.15, hl - 0.15):
            box(mb, "paint_black", x - 0.03, -0.25, 0.0, x + 0.03, -0.19, 0.45)
            box(mb, "paint_black", x - 0.03, 0.15, 0.0, x + 0.03, 0.21, 0.85)
            box(mb, "paint_black", x - 0.03, -0.25, 0.4, x + 0.03, 0.21, 0.45)
        for i in range(4):
            y = -0.24 + i * 0.11
            box(mb, "clad_wood", -hl, y, 0.45, hl, y + 0.09, 0.5)
        for i in range(2):
            z = 0.58 + i * 0.14
            box(mb, "clad_wood", -hl, 0.17, z, hl, 0.23, z + 0.1)
        h = 0.85
    elif k == 1:
        box(mb, "concrete", -hl, -0.25, 0.0, hl, 0.25, 0.4)
        for i in range(5):
            y = -0.25 + i * 0.1
            box(mb, "clad_wood", -hl + 0.05, y + 0.005, 0.4, hl - 0.05, y + 0.085, 0.45)
        h = 0.45
    else:
        for x in (-hl + 0.1, hl - 0.1):
            box(mb, "steel", x - 0.03, -0.24, 0.0, x + 0.03, 0.2, 0.42)
            box(mb, "steel", x - 0.03, 0.14, 0.42, x + 0.03, 0.2, 0.82)
        box(mb, "paint_grey", -hl, -0.25, 0.42, hl, 0.2, 0.46)
        box(mb, "paint_grey", -hl, 0.17, 0.5, hl, 0.21, 0.82)
        h = 0.82
    return mb, {"footprint": [round(L, 2), 0.55], "height": h, "params": {"style": ["slat", "concrete", "steel"][k]}}
