"""石头：两段多边形棱台，边数和扁平程度随机；有时旁边带一块小石头。对照 Godot 端 build_rock。"""
import math
import random

from ..builder import MeshBuilder

NAME = "石头"
CATEGORY = "rocks"
DESC = "Blender 生成的石头：两段多边形叠成的低矮岩块，有的旁边还卧着一块小石头。"
VARY = "大小、边数、扁平程度、有没有小石头随种子变化；放进场景时再随机朝向和比例。"
TAGS = ["forest", "plains", "town", "shore", "winter"]
VARIANTS = 8


def build(seed, **over):
    r = random.Random(seed * 2654435761 % 4294967296)
    mb = MeshBuilder()
    count = 2 if seed % 3 == 1 else 1
    reach = 0.0
    top = 0.0
    for i in range(count):
        cx, cy = (0.0, 0.0) if i == 0 else (r.uniform(0.4, 0.6), r.uniform(-0.3, 0.3))
        rad = r.uniform(0.35, 0.6) * (1.0 if i == 0 else 0.5)
        h = rad * r.uniform(0.6, 1.1)
        sides = r.randint(5, 7)
        rot = r.random() * math.pi
        mb.frustum("rock", cx, cy, -0.05, h * 0.55, rad, rad * 0.85, sides, rot, top=False)
        mb.frustum("rock", cx, cy, h * 0.55, h, rad * 0.85, rad * r.uniform(0.3, 0.55), sides, rot + 0.3, top=True)
        reach = max(reach, math.hypot(cx, cy) + rad)
        top = max(top, h)
    return mb, {"footprint": [reach * 2, reach * 2], "height": top, "plant": True}
