"""杨树：竖长的卵形树冠（三四团由大到小往上叠），下面露出一截树干。对照 Godot 端 build_broadleaf("poplar")。"""
import math
import random

from ..builder import MeshBuilder
from ._common import leaf_blob

NAME = "杨树"
CATEGORY = "trees"
DESC = "Blender 生成的杨树：细高的卵形树冠，三四团由大到小往上叠，下面露出一截树干。"
VARY = "树冠团数、大小、整体高度随种子变化；放进场景时再随机朝向、比例、色调。"
TAGS = ["plains", "town", "forest"]
VARIANTS = 6


def build(seed, **over):
    r = random.Random(seed * 104729 + 3)
    mb = MeshBuilder()
    r0 = r.uniform(0.8, 1.0)
    trunk_h = r0 * 0.85 + 0.55 + r.uniform(0.1, 0.4)
    mb.frustum("trunk", 0, 0, 0.0, 0.25, 0.22, 0.15, 8, 0, top=False)
    mb.frustum("trunk", 0, 0, 0.25, trunk_h + 1.4, 0.15, 0.1, 8, 0, top=True)
    cz = trunk_h + r0 * 0.68
    top = cz
    for i in range(r.randint(3, 4)):
        rad = r0 * (1.0 - i * 0.18)
        leaf_blob(mb, r.uniform(-0.1, 0.1), r.uniform(-0.1, 0.1), cz, rad, rad * 1.35, r.random() * math.pi)
        top = cz + rad * 0.68
        cz += rad * 0.95
    return mb, {"footprint": [r0 * 2.2, r0 * 2.2], "height": top, "plant": True}
