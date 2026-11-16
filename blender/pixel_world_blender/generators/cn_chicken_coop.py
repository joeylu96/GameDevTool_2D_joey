"""鸡窝：四根木腿撑起的小木板窝（离地防潮），草顶，正面一个圆角小门洞和一块带横档的斜坡板通到地面，
窝下面散着几把麦秸。门洞朝 -Y（导出后 Godot +Z），原点在占地中心地面。"""
import math

from ..builder import MeshBuilder
from ._medieval import box, gable_roof

NAME = "鸡窝"
CATEGORY = "props"
DESC = "Blender 生成的农家鸡窝：木腿撑起的木板小窝、草顶、小门洞和带横档的斜坡板。"
VARY = "变体 0 草顶，1 小青瓦顶；窝的大小不同。"
TAGS = ["cn_village", "yard"]
VARIANTS = 2


def build(seed, **over):
    k = (seed - 1) % 2
    w, d = [1.3, 1.1][k], 0.9
    hw, hd = w * 0.5, d * 0.5
    z0, z1 = 0.45, 1.15
    mb = MeshBuilder()
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(mb, "trunk", sx * (hw - 0.05) - 0.04, sy * (hd - 0.05) - 0.04, 0.0, sx * (hw - 0.05) + 0.04, sy * (hd - 0.05) + 0.04, z0)
    box(mb, "boards", -hw, -hd, z0, hw, hd, z1)
    # 门洞（深色）+ 斜坡板
    box(mb, "coal", -0.14, -hd - 0.01, z0 + 0.05, 0.14, -hd, z0 + 0.38)
    box(mb, "wall_wood", -0.18, -hd - 0.03, z0 + 0.38, 0.18, -hd, z0 + 0.43)
    a = math.atan2(z0, 0.7)
    for i in range(1):
        pts = [(-0.15, -hd - 0.02, z0 + 0.02), (0.15, -hd - 0.02, z0 + 0.02), (0.15, -hd - 0.72, 0.02), (-0.15, -hd - 0.72, 0.02)]
        mb.face("boards", pts, (0, -math.sin(a), math.cos(a)))
        mb.face("boards", [(x, y, z - 0.03) for x, y, z in pts][::-1], (0, math.sin(a), -math.cos(a)))
    for j in range(1, 4):
        t = j / 4.0
        y, z = -hd - 0.02 - 0.7 * t, z0 + 0.02 - z0 * t
        box(mb, "wall_wood", -0.15, y - 0.02, z, 0.15, y + 0.02, z + 0.035)
    # 屋顶
    if k == 0:
        ridge, gables = gable_roof(mb, "thatch", -hw, hw, -hd, hd, z1, 40.0, axis="x", eave=0.18, gable=0.12, thatch=True)
    else:
        ridge, gables = gable_roof(mb, "tile_cn", -hw, hw, -hd, hd, z1, 32.0, axis="x", eave=0.18, gable=0.12, t=0.06,
                                   fascia="wall_wood")
    for sa, tri in gables:
        mb.face("boards", tri, (sa, 0, 0))
    # 地上的麦秸
    for x, y in ((-0.3, -0.1), (0.25, 0.15), (0.0, -0.75)):
        mb.frustum("hay", x, y, 0.0, 0.07, 0.22, 0.12, 6, 0.3)
    return mb, {"footprint": [round(w + 0.4, 2), round(d + 0.9, 2)], "height": round(ridge + 0.35, 2),
                "params": {"roof": ["thatch", "tile"][k]}}
