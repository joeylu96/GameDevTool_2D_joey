"""木箱：方箱 + 四角深色木条。变体 0/1/2 = 边长 0.5 / 0.62 / 0.74 米。对照 Godot 端 build_crate。"""
from ..builder import MeshBuilder

NAME = "木箱"
CATEGORY = "props"
DESC = "Blender 生成的木箱：木板箱体，四角包着深色木条，码头和营地边的货物。"
VARY = "三种大小（0.5 / 0.62 / 0.74 米）。"
TAGS = ["yard", "camp", "shore", "roadside"]
VARIANTS = 3


def build(seed, **over):
    size = 0.5 + ((seed - 1) % 3) * 0.12
    mb = MeshBuilder()
    h = size * 0.5
    mb.box("crate", (-h, -h, 0), (h, h, size))
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * h, sy * h
            mb.box("trunk", (x - 0.05, y - 0.05, 0), (x + 0.05, y + 0.05, size), top=True)
    return mb, {"footprint": [size + 0.1, size + 0.1], "height": size}
