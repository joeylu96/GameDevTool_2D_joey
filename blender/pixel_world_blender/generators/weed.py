"""水草：4~6 片细长的三棱叶，长在浅水的湖底，随水流摆动。对照 Godot 端 build_weed。"""
import math
import random

from ..builder import MeshBuilder

NAME = "水草"
CATEGORY = "water"
DESC = "Blender 生成的水草：一丛细长的三棱叶，长在浅水湖底，随水流轻轻摆动。"
VARY = "叶片数量和高度随种子变化。"
TAGS = ["shore"]
VARIANTS = 3


def build(seed, **over):
    r = random.Random(seed * 5003 + 1)
    mb = MeshBuilder()
    top = 0.0
    for i in range(r.randint(4, 6)):
        cx, cy = r.uniform(-0.18, 0.18), r.uniform(-0.18, 0.18)
        h = r.uniform(0.35, 0.8)
        mb.frustum("weed", cx, cy, 0.0, h, 0.045, 0.0, 3, r.random() * math.tau, top=False)
        top = max(top, h)
    return mb, {"footprint": [0.5, 0.5], "height": top, "plant": True}
