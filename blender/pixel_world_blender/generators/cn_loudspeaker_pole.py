"""村头大喇叭：木杆（或水泥杆）顶上一根横担，挂着一两只灰色号筒喇叭，号口朝外斜向下；杆上缠着一圈线、钉着一只小接线盒。
原点在杆脚中心地面；变体 0 两只喇叭分别朝 -Y 和 +X，变体 1 一只喇叭朝 -Y（导出后 Godot +Z）。"""
import math

import numpy as np

from ..builder import MeshBuilder
from ._medieval import box

NAME = "大喇叭"
CATEGORY = "street"
DESC = "Blender 生成的村头大喇叭：杆顶横担上挂着灰色号筒喇叭，号口斜朝下对着村子。"
VARY = "变体 0 木杆两只喇叭，1 水泥杆一只喇叭。"
TAGS = ["cn_village", "roadside", "plaza"]
VARIANTS = 2


def _horn(mb, base, direction):
    """号筒喇叭：后面一个圆筒（驱动器）+ 往前张开的喇叭口"""
    d = np.asarray(direction, dtype=float)
    d /= np.linalg.norm(d)
    b = np.asarray(base, dtype=float)
    mb.tube("paint_grey", b - d * 0.12, b, 0.09, 0.09, 10)
    mb.tube("paint_grey", b, b + d * 0.5, 0.06, 0.24, 12)
    mb.tube("paint_black", b + d * 0.49, b + d * 0.5, 0.22, 0.22, 12)


def build(seed, **over):
    k = (seed - 1) % 2
    mb = MeshBuilder()
    h = [6.5, 7.0][k]
    if k == 0:
        mb.tube("trunk", (0, 0, 0.0), (0, 0, h), 0.12, 0.09, 8, math.pi / 8)
    else:
        mb.frustum("cement", 0.0, 0.0, 0.0, h, 0.14, 0.1, 10)
    box(mb, "iron", -0.5, -0.05, h - 0.4, 0.5, 0.05, h - 0.3)
    box(mb, "iron", -0.05, -0.5, h - 0.4, 0.05, 0.05, h - 0.3)
    _horn(mb, (0.0, -0.45, h - 0.5), (0.0, -1.0, -0.35))
    if k == 0:
        _horn(mb, (0.45, 0.0, h - 0.5), (1.0, 0.0, -0.35))
    box(mb, "paint_grey", -0.1, -0.16, 2.6, 0.1, -0.08, 2.9)  # 接线盒
    for i in range(3):
        z = 3.2 + i * 0.12
        mb.frustum("tyre", 0.0, 0.0, z, z + 0.04, 0.115, 0.115, 8, top=False)
    return mb, {"footprint": [1.6, 1.6], "height": round(h + 0.05, 2), "params": {"horns": 2 - k}}
