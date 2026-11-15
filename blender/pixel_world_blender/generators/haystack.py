"""草垛：躺倒的圆柱形干草卷（变体 0、2）或圆锥形的草堆（变体 1、3）。对照 Godot 端 build_haystack。"""
import random

from ..builder import MeshBuilder

NAME = "草垛"
CATEGORY = "props"
DESC = "Blender 生成的草垛：平原农田里躺倒的干草卷，或者圆锥形的草堆。"
VARY = "卷 / 堆两种形状，大小随种子变化。"
TAGS = ["plains", "yard"]
VARIANTS = 4


def build(seed, **over):
    r = random.Random(seed * 6007 + 5)
    mb = MeshBuilder()
    if seed % 2 == 1:
        rad = r.uniform(0.6, 0.75)
        ln = r.uniform(1.0, 1.3)
        mb.tube("hay", (-ln * 0.5, 0, rad), (ln * 0.5, 0, rad), rad, rad, 10, caps=True)
        return mb, {"footprint": [ln, rad * 2], "height": rad * 2}
    rad = r.uniform(1.1, 1.5)
    mb.frustum("hay", 0, 0, 0.0, rad * 0.9, rad, rad * 0.8, 9, r.random(), top=False)
    mb.frustum("hay", 0, 0, rad * 0.9, rad * 1.9, rad * 0.8, 0.12, 9, r.random(), top=True)
    return mb, {"footprint": [rad * 2, rad * 2], "height": rad * 1.9}
