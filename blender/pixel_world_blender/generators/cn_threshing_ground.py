"""晒场：一块 6×5 米的水泥地坪（略高出地面，边上一圈砖沿），中间摊着一片晒的麦粒、堆着一个粮堆，
旁边靠着一把木耙和一把木锨。原点在地坪中心地面。"""
import math

from ..builder import MeshBuilder
from ._medieval import box

NAME = "晒场"
CATEGORY = "props"
DESC = "Blender 生成的晒场：水泥地坪上摊着晒的麦粒、堆着粮堆，边上靠着木耙和木锨。"
VARY = "变体 0 小麦，1 玉米（金黄）；粮堆大小不同。"
TAGS = ["cn_village", "yard"]
VARIANTS = 2


def build(seed, **over):
    k = (seed - 1) % 2
    grain = ["hay", "paint_yellow"][k]
    mb = MeshBuilder()
    w, d = 6.0, 5.0
    hw, hd = w * 0.5, d * 0.5
    box(mb, "cement", -hw, -hd, 0.0, hw, hd, 0.08)
    for (x0, y0, x1, y1) in ((-hw, -hd, hw, -hd + 0.12), (-hw, hd - 0.12, hw, hd), (-hw, -hd, -hw + 0.12, hd), (hw - 0.12, -hd, hw, hd)):
        box(mb, "brick_grey", x0, y0, 0.0, x1, y1, 0.14)
    # 摊开的一片（很薄、边缘不规则的多边形）
    pts = [(-2.2 + 0.25 * math.cos(i * 1.7), -1.4 + 2.6 * i / 9 + 0.15 * math.sin(i * 2.3), 0.095) for i in range(10)]
    pts += [(0.6 + 0.3 * math.sin(i * 1.3), 1.2 - 2.6 * i / 9, 0.095) for i in range(10)]
    mb.face(grain, pts, (0, 0, 1))
    # 粮堆
    r = [0.9, 1.1][k]
    mb.frustum(grain, 1.6, 0.2, 0.08, 0.5, r, r * 0.45, 10, 0.2, top=False)
    mb.frustum(grain, 1.6, 0.2, 0.5, 0.75, r * 0.45, 0.0, 10, 0.2)
    # 木耙、木锨（靠在粮堆边，斜放在地上）
    mb.tube("trunk", (-0.2, 1.6, 0.12), (1.4, 1.9, 0.35), 0.025, 0.025, 6)
    box(mb, "boards", 1.35, 1.7, 0.1, 1.5, 2.15, 0.4)
    mb.tube("trunk", (-0.6, -1.9, 0.12), (0.9, -1.4, 0.3), 0.025, 0.025, 6)
    box(mb, "boards", 0.85, -1.6, 0.08, 1.25, -1.2, 0.14)
    return mb, {"footprint": [w, d], "height": 0.8, "params": {"grain": ["wheat", "corn"][k]}}
