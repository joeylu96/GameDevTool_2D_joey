"""石井：石砌井圈 + 水面 + 两根木柱撑起的小双坡顶 + 横梁辘轳 + 吊桶。"""
import math
import random

from ..builder import MeshBuilder

NAME = "石井"
CATEGORY = "props"
DESC = "Blender 生成的石井：石砌井圈、木柱小屋顶、辘轳和吊桶，适合放在小镇广场或农舍旁。"
VARY = "井圈粗细、屋顶颜色（灰 / 红）、屋顶坡度随种子变化。"
TAGS = ["plaza", "yard", "town"]


def build(seed, **over):
    r = random.Random(seed)
    mb = MeshBuilder()
    rad = r.uniform(0.75, 0.95)
    sides = 10
    mb.frustum("stone", 0, 0, 0.0, 0.85, rad, rad * 0.97, sides, 0, top=False)
    mb.frustum("stone", 0, 0, 0.85, 0.95, rad * 1.04, rad * 1.04, sides, 0, top=True)
    mb.frustum("stone", 0, 0, 0.3, 0.95, rad * 0.75, rad * 0.75, sides, 0, top=False)  # 内壁（朝外法线也能看见井口一圈）
    mb.frustum("water", 0, 0, 0.0, 0.55, rad * 0.74, rad * 0.74, sides, 0, top=True)
    # 柱子 + 横梁 + 辘轳
    for sx in (-1, 1):
        mb.box("trunk", (sx * (rad + 0.05) - 0.07, -0.07, 0.4), (sx * (rad + 0.05) + 0.07, 0.07, 2.2))
    mb.box("trunk", (-rad - 0.15, -0.05, 2.05), (rad + 0.15, 0.05, 2.15))
    for sx in (-1, 1):
        mb.box("metal", (sx * 0.06 - 0.01, -0.01, 1.35), (sx * 0.06 + 0.01, 0.01, 2.05))
    mb.box("wall_wood", (-0.16, -0.16, 1.05), (0.16, 0.16, 1.4))  # 吊桶
    mb.box("metal", (-0.17, -0.17, 1.12), (0.17, 0.17, 1.16))
    # 小屋顶
    roof = r.choice(["roof_grey", "roof_red"])
    pitch = math.radians(r.uniform(32, 42))
    half_w = rad + 0.45
    half_d = 0.75
    z0 = 2.15
    ridge = z0 + half_d * math.tan(pitch)
    for s in (-1, 1):
        a, b = (-half_w, 0, ridge), (half_w, 0, ridge)
        c, d = (half_w, s * half_d, z0), (-half_w, s * half_d, z0)
        mb.face(roof, [a, b, c, d], (0, s, 1))
        mb.face("wall_wood", [(x, y, z - 0.08) for (x, y, z) in (a, b, c, d)], (0, -s, -1))
    for sx in (-1, 1):
        mb.face("trim", [(sx * half_w, -half_d, z0), (sx * half_w, half_d, z0), (sx * half_w, 0, ridge)], (sx, 0, 0))
    return mb, {"footprint": [half_w * 2, max(rad * 2, half_d * 2)], "height": ridge}
