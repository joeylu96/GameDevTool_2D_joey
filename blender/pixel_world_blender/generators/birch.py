"""白桦：微弯的白色主干（分三段收细）+ 3~4 根斜向上的枝 + 椭圆形的嫩绿叶团簇，下缘露出 2 米多白色树干。
对照 Godot 端 pw_tree_builder._birch。"""
import math
import random

from ..builder import MeshBuilder
from ._common import leaf_blob

NAME = "白桦"
CATEGORY = "trees"
DESC = "Blender 生成的白桦：微弯的白色树干带黑色树疤，嫩绿的叶团簇从主干中部包到树梢。"
VARY = "树高、弯曲方向、枝条数量和方向、叶团数量和大小随种子变化；放进场景时再随机朝向、比例、色调。"
TAGS = ["forest", "plains", "town"]
VARIANTS = 8


def build(seed, **over):
    r = random.Random(seed * 7919 + 11)
    mb = MeshBuilder()
    h = r.uniform(4.6, 5.6)
    bend = (r.uniform(-0.2, 0.2), r.uniform(-0.2, 0.2))
    pts = [(0, 0, 0.25), (bend[0] * 0.3, bend[1] * 0.3, h * 0.42), (bend[0] * 0.7, bend[1] * 0.7, h * 0.72), (bend[0], bend[1], h)]
    radii = [0.16, 0.13, 0.095, 0.05]
    mb.frustum("birch_bark", 0, 0, 0.0, 0.25, 0.23, 0.16, 8, 0, top=False)
    for i in range(3):
        mb.tube("birch_bark", pts[i], pts[i + 1], radii[i], radii[i + 1], 8, caps=(i == 2))
    tips = []
    nb = r.randint(3, 4)
    a0 = r.random() * math.tau
    for i in range(nb):
        t = r.random()
        base = tuple(pts[1][k] + (pts[2][k] - pts[1][k]) * t for k in range(3))
        a = a0 + math.tau * i / nb + r.uniform(-0.3, 0.3)
        ln = r.uniform(0.45, 0.7)
        tip = (base[0] + math.cos(a) * ln, base[1] + math.sin(a) * ln, base[2] + ln * r.uniform(0.7, 1.0))
        mb.tube("birch_bark", base, tip, 0.06, 0.025, 6, caps=False)
        tips.append(tip)
    cc = (pts[2][0], pts[2][1], pts[2][2] + 0.1)
    crx = r.uniform(0.65, 0.85)
    cry = h * 0.3
    blobs = list(tips) + [(pts[3][0], pts[3][1], pts[3][2] + 0.1)]
    for i in range(r.randint(6, 8)):
        a = r.random() * math.tau
        e = r.uniform(-0.55, 0.8)
        rr = math.sqrt(max(1.0 - e * e, 0.05)) * crx * r.uniform(0.5, 0.9)
        blobs.append((cc[0] + math.cos(a) * rr, cc[1] + math.sin(a) * rr, cc[2] + e * cry))
    top = 0.0
    reach = 0.0
    for (x, y, z) in blobs:
        rad = r.uniform(0.58, 0.78) * (1.0 - min(max((z - cc[2]) / (cry * 2.0), 0.0), 0.35))
        leaf_blob(mb, x, y, z, rad, rad * 1.2, r.random() * math.pi, "leaf_birch", "leaf_birch_dark", 7)
        top = max(top, z + rad * 0.6)
        reach = max(reach, math.hypot(x, y) + rad)
    return mb, {"footprint": [reach * 2, reach * 2], "height": top, "plant": True}
