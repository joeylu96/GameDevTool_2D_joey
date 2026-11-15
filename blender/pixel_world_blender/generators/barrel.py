"""木桶：中间鼓、上下收口的十边形，两道铁箍。对照 Godot 端 build_barrel；三个变体高矮胖瘦略有不同。"""
from ..builder import MeshBuilder

NAME = "木桶"
CATEGORY = "props"
DESC = "Blender 生成的木桶：中间鼓、上下收口，两道铁箍。"
VARY = "高矮胖瘦三种。"
TAGS = ["yard", "camp", "shore", "roadside"]
VARIANTS = 3


def build(seed, **over):
    k = (seed - 1) % 3
    h = (0.9, 0.78, 1.0)[k]
    r0, r1 = ((0.3, 0.36), (0.28, 0.33), (0.31, 0.37))[k]
    mb = MeshBuilder()
    mb.frustum("barrel", 0, 0, 0.0, h * 0.5, r0, r1, 10, 0, top=False, bottom=True)
    mb.frustum("barrel", 0, 0, h * 0.5, h, r1, r0, 10, 0, top=True)
    for z in (h * 0.155, h * 0.78):
        rr = r0 + (r1 - r0) * min(1.0, (z if z < h * 0.5 else h - z) / (h * 0.5)) + 0.008
        mb.frustum("metal", 0, 0, z, z + 0.07, rr, rr, 10, 0, top=False)
    return mb, {"footprint": [r1 * 2, r1 * 2], "height": h}
