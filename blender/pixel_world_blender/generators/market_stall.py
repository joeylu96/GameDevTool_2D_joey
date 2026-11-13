"""集市摊位：木柜台 + 四根立柱 + 条纹帆布顶棚（前低后高）+ 柜台上的水果筐 + 旁边的木箱。"""
import random

from ..builder import MeshBuilder

NAME = "集市摊位"
CATEGORY = "street"
DESC = "Blender 生成的集市摊位：木柜台、条纹帆布顶棚、水果筐和木箱，适合小镇广场。"
VARY = "顶棚颜色（红 / 青 / 黄条纹）、摊位宽度、水果种类和数量随种子变化。"


def build(seed, **over):
    r = random.Random(seed)
    mb = MeshBuilder()
    w = r.uniform(2.2, 3.0)
    d = 1.3
    hw, hd = w / 2, d / 2
    canvas = r.choice(["canvas_red", "canvas_teal", "canvas_ochre"])
    # 柜台（正面朝 -Y）
    mb.box("wall_wood", (-hw, -hd, 0), (hw, -hd + 0.6, 0.95))
    mb.box("trim", (-hw - 0.05, -hd - 0.05, 0.95), (hw + 0.05, -hd + 0.65, 1.02))
    # 立柱
    for sx in (-1, 1):
        mb.box("trunk", (sx * hw - 0.06, -hd - 0.06, 0), (sx * hw + 0.06, -hd + 0.06, 2.2))
        mb.box("trunk", (sx * hw - 0.06, hd - 0.06, 0), (sx * hw + 0.06, hd + 0.06, 2.6))
    # 顶棚：前低后高，向前伸出一点，前沿有一圈垂边
    f, b = (-hd - 0.35, 2.25), (hd + 0.1, 2.65)
    mb.face(canvas, [(-hw - 0.2, f[0], f[1]), (hw + 0.2, f[0], f[1]), (hw + 0.2, b[0], b[1]), (-hw - 0.2, b[0], b[1])], (0, -0.3, 1))
    mb.face(canvas, [(-hw - 0.2, f[0], f[1] - 0.02), (-hw - 0.2, b[0], b[1] - 0.02), (hw + 0.2, b[0], b[1] - 0.02), (hw + 0.2, f[0], f[1] - 0.02)], (0, 0.3, -1))
    mb.box(canvas, (-hw - 0.2, f[0] - 0.02, f[1] - 0.25), (hw + 0.2, f[0] + 0.02, f[1]), top=False)
    # 水果筐
    fruits = ["fruit_red", "fruit_yellow", "fruit_green"]
    n = r.randint(2, 4)
    for i in range(n):
        x = -hw + 0.4 + (w - 0.8) * (i + 0.5) / n
        mb.box("wall_wood", (x - 0.25, -hd + 0.05, 1.02), (x + 0.25, -hd + 0.5, 1.15), top=False)
        fr = r.choice(fruits)
        for k in range(r.randint(4, 7)):
            fx = x + r.uniform(-0.18, 0.18)
            fy = -hd + 0.27 + r.uniform(-0.15, 0.15)
            mb.frustum(fr, fx, fy, 1.1, 1.22, 0.06, 0.03, 5, r.random(), top=True)
    # 旁边的木箱
    if r.random() < 0.7:
        x = hw + 0.5
        mb.box("wall_ochre", (x - 0.3, -0.3, 0), (x + 0.3, 0.3, 0.6))
    return mb, {"footprint": [w + 1.2, d + 0.6], "height": 2.7}
