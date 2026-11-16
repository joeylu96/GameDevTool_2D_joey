"""村里的电线杆：变体 0 木杆 + 一根横担（三个白瓷瓶）、1 水泥杆 + 两根横担、2 水泥杆 + 横担 + 一盏路灯（灯朝 -Y，夜里亮）。
原点在杆脚中心地面，横担沿 X。电线不画（两根杆之间连不起来）。"""
import math

from ..builder import MeshBuilder
from ._medieval import box

NAME = "电线杆"
CATEGORY = "street"
DESC = "Blender 生成的农村电线杆：木杆或水泥杆，横担上一排白瓷瓶，有的还挂着一盏路灯。"
VARY = "变体 0 木杆一根横担、1 水泥杆两根横担、2 水泥杆带路灯。"
TAGS = ["cn_village", "roadside"]
VARIANTS = 3


def _crossarm(mb, z, key, n=3, half=0.9):
    box(mb, key, -half, -0.06, z - 0.06, half, 0.06, z + 0.06)
    mb.tube(key, (-half * 0.6, 0.0, z - 0.05), (0.0, 0.0, z - 0.6), 0.03, 0.03, 4)
    mb.tube(key, (half * 0.6, 0.0, z - 0.05), (0.0, 0.0, z - 0.6), 0.03, 0.03, 4)
    for i in range(n):
        x = -half + 0.12 + (2 * half - 0.24) * i / max(n - 1, 1)
        mb.frustum("paint_white", x, 0.0, z + 0.06, z + 0.16, 0.05, 0.045, 6)
        mb.frustum("paint_white", x, 0.0, z + 0.16, z + 0.22, 0.065, 0.03, 6)


def build(seed, **over):
    k = (seed - 1) % 3
    mb = MeshBuilder()
    h = [7.0, 8.5, 8.0][k]
    if k == 0:
        mb.tube("trunk", (0, 0, 0.0), (0, 0, h), 0.13, 0.1, 8, math.pi / 8)
        box(mb, "iron", -0.14, -0.14, 0.0, 0.14, 0.14, 0.04)
        _crossarm(mb, h - 0.4, "trunk")
    else:
        mb.frustum("cement", 0.0, 0.0, 0.0, h, 0.15, 0.1, 10, top=True)
        _crossarm(mb, h - 0.35, "iron", n=3)
        if k == 1:
            _crossarm(mb, h - 1.3, "iron", n=4, half=1.1)
        else:
            # 路灯：弯臂伸向 -Y + 碗形灯罩，底下的灯泡发光
            z = h - 2.0
            mb.tube("iron", (0, -0.1, z), (0, -0.9, z + 0.35), 0.03, 0.03, 6)
            mb.frustum("paint_teal", 0.0, -1.0, z + 0.1, z + 0.35, 0.3, 0.06, 10, top=True, bottom=False)
            mb.frustum("bulb", 0.0, -1.0, z + 0.02, z + 0.12, 0.09, 0.09, 8)
    # 杆上钉着的一块小牌子（空白）
    box(mb, "paint_white", -0.12, -0.17 if k == 0 else -0.19, 2.2, 0.12, -0.12 if k == 0 else -0.14, 2.5)
    info = {"footprint": [2.4, 0.6], "height": round(h + 0.25, 2), "params": {"style": ["wood", "concrete", "concrete_lamp"][k]}}
    if k == 2:
        info["light"] = [0.0, -1.0, h - 2.0]
    return mb, info
