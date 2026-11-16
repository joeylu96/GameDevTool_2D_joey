"""石磨：变体 0 手推小石磨（砖砌磨台上两扇圆磨盘，上扇插一根推杆，旁边一只簸箕），
变体 1 驴拉的大碾子（圆形碾盘 + 立在中间的木轴 + 一个石碾滚 + 长木杆）。原点在磨台中心地面。"""
import math

from ..builder import MeshBuilder
from ._medieval import box

NAME = "石磨"
CATEGORY = "props"
DESC = "Blender 生成的农家石磨：砖砌磨台上的两扇圆磨盘配推杆，或者带碾滚的大石碾。"
VARY = "变体 0 手推石磨，1 大石碾。"
TAGS = ["cn_village", "yard"]
VARIANTS = 2


def build(seed, **over):
    k = (seed - 1) % 2
    mb = MeshBuilder()
    if k == 0:
        mb.frustum("brick_grey", 0.0, 0.0, 0.0, 0.6, 0.62, 0.6, 12)
        mb.frustum("stone", 0.0, 0.0, 0.6, 0.66, 0.6, 0.6, 16)            # 磨盘底座（接面粉的圆台）
        mb.frustum("stone", 0.0, 0.0, 0.66, 0.84, 0.36, 0.36, 16)         # 下扇
        mb.frustum("stone", 0.0, 0.0, 0.86, 1.06, 0.36, 0.35, 16)         # 上扇
        mb.frustum("coal", 0.12, 0.0, 1.06, 1.065, 0.05, 0.05, 8)          # 磨眼
        mb.tube("trunk", (0.0, -0.3, 0.98), (0.0, -1.1, 1.0), 0.03, 0.03, 6)  # 推杆
        mb.tube("trunk", (-0.3, -1.1, 1.0), (0.3, -1.1, 1.0), 0.035, 0.035, 6)
        box(mb, "boards", 0.55, -0.5, 0.0, 0.95, -0.15, 0.06)               # 簸箕
        return mb, {"footprint": [1.4, 2.4], "height": 1.1, "params": {"kind": "hand"}}
    mb.frustum("stone", 0.0, 0.0, 0.0, 0.5, 1.6, 1.6, 20)                  # 碾盘
    mb.frustum("trunk", 0.0, 0.0, 0.5, 1.3, 0.09, 0.08, 8)                  # 中轴
    mb.tube("stone", (-0.3, -0.8, 0.82), (0.3, -0.8, 0.82), 0.32, 0.32, 14, math.pi / 14)  # 碾滚
    box(mb, "trunk", -0.38, -0.86, 0.75, -0.32, 0.0, 0.85)
    box(mb, "trunk", 0.32, -0.86, 0.75, 0.38, 0.0, 0.85)
    mb.tube("trunk", (0.0, 0.0, 1.2), (0.0, -2.2, 1.0), 0.04, 0.04, 6)      # 拉杆
    return mb, {"footprint": [3.2, 4.0], "height": 1.3, "params": {"kind": "roller"}}
