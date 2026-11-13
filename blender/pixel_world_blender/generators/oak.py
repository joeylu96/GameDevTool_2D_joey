"""阔叶树（橡树）：粗短树干分出 2~3 根主枝，每根枝头顶一簇树冠，中间再补一大簇；
下层的簇用深色叶子、上层浅色，看起来有体积感。树冠底部离地有一段距离，树干总能露出来。"""
import math
import random

from ..builder import MeshBuilder

NAME = "阔叶树"
CATEGORY = "trees"
DESC = "Blender 生成的阔叶树：树干分叉成几根主枝，每根枝头一簇树冠，下层深上层浅。"
VARY = "主枝数量和方向、树冠簇的大小和数量、树干高度和粗细随种子变化；放进场景时再随机朝向、比例、色调。"
TAGS = ["forest", "plains", "town"]


def build(seed, **over):
    r = random.Random(seed)
    mb = MeshBuilder()
    trunk_h = r.uniform(1.5, 2.1)
    tr = r.uniform(0.17, 0.22)
    # 树干：根部外扩一点，再往上收
    mb.frustum("trunk", 0, 0, 0.0, 0.3, tr * 1.45, tr, 8, 0, top=False)
    mb.frustum("trunk", 0, 0, 0.3, trunk_h, tr, tr * 0.8, 8, 0, top=False)
    top = (0.0, 0.0, trunk_h)
    clusters = []
    n_branch = r.randint(2, 3)
    a0 = r.random() * math.tau
    reach = 0.0
    for i in range(n_branch):
        a = a0 + math.tau * i / n_branch + r.uniform(-0.4, 0.4)
        ln = r.uniform(0.8, 1.2)
        rise = r.uniform(0.7, 1.1)
        end = (math.cos(a) * ln, math.sin(a) * ln, trunk_h + rise)
        mb.tube("trunk", top, end, tr * 0.7, tr * 0.38, 6, caps=False)
        cr = r.uniform(0.85, 1.1)
        clusters.append((end[0], end[1], end[2] + cr * 0.25, cr))
        reach = max(reach, ln + cr)
    # 中间的大簇 + 顶上一小簇，把枝头之间的空隙补满
    cz = trunk_h + 1.3
    clusters.append((0.0, 0.0, cz, r.uniform(1.1, 1.3)))
    clusters.append((r.uniform(-0.3, 0.3), r.uniform(-0.3, 0.3), cz + 0.95, r.uniform(0.7, 0.85)))
    height = 0.0
    for (x, y, z, cr) in clusters:
        key = "leaf_dark" if z < cz else "leaf"
        mb.blob(key, x, y, z, cr, cr * 1.35, 8, r.random())
        height = max(height, z + cr * 0.68)
    return mb, {"footprint": [reach * 2, reach * 2], "height": height, "plant": True}
