"""搪瓷脸盆和小板凳：白底红边的搪瓷盆（盆里有水），旁边一只矮木板凳。
变体 0 盆放在地上 + 一只板凳，1 盆搁在木头洗脸架上 + 架子上搭一条毛巾，2 两只盆（一大一小）+ 板凳 + 一块搓衣板。
原点在这组东西的中心地面。"""
from ..builder import MeshBuilder
from ._medieval import box

NAME = "脸盆板凳"
CATEGORY = "props"
DESC = "Blender 生成的搪瓷脸盆和小板凳：白底红边的搪瓷盆，矮木板凳，有的搁在洗脸架上、搭着毛巾。"
VARY = "变体 0 盆 + 板凳、1 洗脸架、2 两只盆 + 搓衣板。"
TAGS = ["cn_village", "yard"]
VARIANTS = 3


def basin(mb, x, y, z, r=0.24, h=0.12):
    mb.frustum("paint_white", x, y, z, z + h, r * 0.68, r, 14, bottom=True, top=False)
    mb.frustum("paint_red", x, y, z + h, z + h + 0.018, r, r * 1.06, 14, top=False)       # 红边
    mb.frustum("water", x, y, z + h * 0.72, z + h * 0.74, r * 0.9, r * 0.9, 14)


def stool(mb, x, y, w=0.36, d=0.2, h=0.26):
    box(mb, "wall_wood", x - w * 0.5, y - d * 0.5, h - 0.035, x + w * 0.5, y + d * 0.5, h)
    for sx in (-1, 1):
        box(mb, "wall_wood", x + sx * (w * 0.5 - 0.06) - 0.02, y - d * 0.5 + 0.01, 0.0, x + sx * (w * 0.5 - 0.06) + 0.02, y + d * 0.5 - 0.01, h - 0.035)
    box(mb, "wall_wood", x - w * 0.5 + 0.06, y - 0.015, 0.1, x + w * 0.5 - 0.06, y + 0.015, 0.14)


def build(seed, **over):
    k = (seed - 1) % 3
    mb = MeshBuilder()
    if k == 0:
        basin(mb, -0.25, 0.0, 0.0)
        stool(mb, 0.35, 0.05)
        fp, hh = [1.1, 0.6], 0.27
    elif k == 1:
        # 洗脸架：四条腿 + 上下两道框 + 后面高出来的毛巾杆
        for sx in (-1, 1):
            for sy in (-1, 1):
                mb.tube("wall_wood", (sx * 0.2, sy * 0.2, 0.0), (sx * 0.2, sy * 0.2, 0.7 if sy < 0 else 1.25), 0.02, 0.02, 6)
        for z in (0.25, 0.66):
            for a in ((-1, -1, 1, -1), (1, -1, 1, 1), (1, 1, -1, 1), (-1, 1, -1, -1)):
                mb.tube("wall_wood", (a[0] * 0.2, a[1] * 0.2, z), (a[2] * 0.2, a[3] * 0.2, z), 0.015, 0.015, 5)
        mb.tube("wall_wood", (-0.22, 0.2, 1.2), (0.22, 0.2, 1.2), 0.016, 0.016, 5)
        box(mb, "cloth_blue", -0.12, 0.185, 0.85, 0.12, 0.215, 1.215)      # 毛巾
        basin(mb, 0.0, 0.0, 0.67, 0.23)
        stool(mb, 0.55, -0.05)
        fp, hh = [1.2, 0.6], 1.25
    else:
        basin(mb, -0.35, 0.05, 0.0, 0.28, 0.14)
        basin(mb, 0.22, -0.18, 0.0, 0.2, 0.1)
        stool(mb, 0.3, 0.3)
        # 搓衣板：斜靠在大盆沿上
        mb.face("boards", [(-0.47, -0.15, 0.02), (-0.23, -0.15, 0.02), (-0.23, 0.12, 0.3), (-0.47, 0.12, 0.3)], (0, -1, 0.6))
        mb.face("boards", [(-0.47, -0.13, 0.0), (-0.23, -0.13, 0.0), (-0.23, 0.14, 0.28), (-0.47, 0.14, 0.28)], (0, 1, -0.6))
        fp, hh = [1.2, 0.9], 0.3
    return mb, {"footprint": fp, "height": hh, "params": {"basins": 2 if k == 2 else 1}}
