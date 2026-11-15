"""灌木：贴地的 2~3 个团块；约三成开花（顶面是花）。对照 Godot 端 build_bush。"""
import math
import random

from ..builder import MeshBuilder
from ._common import leaf_blob

NAME = "灌木"
CATEGORY = "plants"
DESC = "Blender 生成的灌木：贴地的两三团枝叶，约三成顶上开着小花。"
VARY = "团块数量和大小、是否开花随种子变化；放进场景时再随机朝向、比例、色调。"
TAGS = ["forest", "plains", "town", "yard"]
VARIANTS = 8


def build(seed, **over):
    r = random.Random(seed * 15485863 + 7)
    mb = MeshBuilder()
    top = "flowers" if (seed % 3 == 0) else "leaf"   # 8 个变体里有 2 个开花
    rad = r.uniform(0.5, 0.8)
    hh = rad * r.uniform(0.95, 1.2)
    leaf_blob(mb, 0, 0, rad * 0.55, rad, hh, r.random() * math.pi, top, "leaf_dark")
    reach = rad
    for i in range(r.randint(1, 2)):
        a = r.random() * math.tau
        r2 = rad * r.uniform(0.55, 0.8)
        x, y = math.cos(a) * rad * 0.75, math.sin(a) * rad * 0.75
        leaf_blob(mb, x, y, r2 * 0.5, r2, r2, r.random() * math.pi, top, "leaf_dark")
        reach = max(reach, math.hypot(x, y) + r2)
    return mb, {"footprint": [reach * 2, reach * 2], "height": rad * 0.55 + hh * 0.5, "plant": True}
