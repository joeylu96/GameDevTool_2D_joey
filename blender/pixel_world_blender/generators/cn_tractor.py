"""红色四轮小拖拉机（八九十年代农村常见的那种）：长机头（引擎盖 + 前格栅 + 两只车灯 + 竖排气管），两只小前轮、
两只带挡泥板的大后轮，驾驶座、方向盘。变体 0 带四根立柱撑起的遮阳棚，1 没有棚、只有座椅后面一道防滚架，机头偏橙红。
车头朝 -Y（导出后 Godot +Z），原点在整车中心地面，长约 3.3 米、宽约 1.8 米。"""
import math

from ..builder import MeshBuilder
from ._medieval import box
from ._modern import wheel

NAME = "四轮拖拉机"
CATEGORY = "props"
DESC = "Blender 生成的红色四轮小拖拉机：长机头、竖排气管、两只小前轮和两只带挡泥板的大后轮，有的带遮阳棚。"
VARY = "变体 0 带遮阳棚，1 不带棚（只有防滚架）。"
TAGS = ["cn_village", "yard", "roadside"]
VARIANTS = 2


def build(seed, **over):
    k = (seed - 1) % 2
    mb = MeshBuilder()
    red = "paint_red"
    # 车架 + 发动机
    box(mb, "paint_black", -0.22, -1.5, 0.42, 0.22, 1.0, 0.62)
    box(mb, "paint_black", -0.3, -1.3, 0.55, 0.3, -0.25, 0.8)
    # 引擎盖（前低后高一点）+ 前格栅 + 车灯
    box(mb, red, -0.36, -1.55, 0.78, 0.36, -0.15, 1.22)
    box(mb, red, -0.3, -1.5, 1.22, 0.3, -0.2, 1.28)
    box(mb, "steel", -0.28, -1.58, 0.82, 0.28, -1.55, 1.18)
    for i in range(5):
        z = 0.86 + i * 0.065
        box(mb, "paint_black", -0.25, -1.6, z, 0.25, -1.58, z + 0.03)
    for sx in (-1, 1):
        mb.tube("bulb", (sx * 0.42, -1.5, 1.05), (sx * 0.42, -1.58, 1.05), 0.08, 0.08, 10)
        mb.tube("steel", (sx * 0.42, -1.42, 1.05), (sx * 0.42, -1.5, 1.05), 0.085, 0.085, 10)
    # 排气管
    mb.tube("paint_black", (0.2, -0.9, 1.25), (0.2, -0.9, 1.95), 0.045, 0.045, 8)
    mb.tube("steel", (0.2, -0.9, 1.95), (0.2, -0.9, 2.02), 0.06, 0.05, 8)
    # 前桥 + 小前轮
    mb.tube("paint_black", (-0.62, -1.05, 0.32), (0.62, -1.05, 0.32), 0.05, 0.05, 6)
    for sx in (-1, 1):
        wheel(mb, sx * 0.66, -1.05, 0.32, 0.32, 0.18, hub=red, sides=14)
    # 后桥 + 大后轮（带花纹）+ 挡泥板
    mb.tube("paint_black", (-0.7, 0.75, 0.58), (0.7, 0.75, 0.58), 0.07, 0.07, 8)
    for sx in (-1, 1):
        x = sx * 0.74
        wheel(mb, x, 0.75, 0.58, 0.58, 0.3, hub=red, sides=16)
        for i in range(12):
            a = 2 * math.pi * i / 12
            cy, cz = 0.75 + math.cos(a) * 0.59, 0.58 + math.sin(a) * 0.59
            box(mb, "tyre", x - 0.15, cy - 0.035, cz - 0.035, x + 0.15, cy + 0.035, cz + 0.035)
        # 挡泥板：轮子上方一段弧（三段折板）
        xi, xo = sx * 0.52, sx * 0.95
        pts = [(0.75 + math.cos(math.radians(a)) * 0.68, 0.58 + math.sin(math.radians(a)) * 0.68) for a in (160, 120, 80, 40, 10)]
        for (y0, z0), (y1, z1) in zip(pts[:-1], pts[1:]):
            mb.face(red, [(xi, y0, z0), (xo, y0, z0), (xo, y1, z1), (xi, y1, z1)], (0, 0, 1))
            mb.face(red, [(xi, y0, z0 - 0.04), (xo, y0, z0 - 0.04), (xo, y1, z1 - 0.04), (xi, y1, z1 - 0.04)], (0, 0, -1))
            mb.face(red, [(xo, y0, z0), (xo, y1, z1), (xo, y1, z1 - 0.04), (xo, y0, z0 - 0.04)], (sx, 0, 0))
    # 驾驶台：踏板、座椅、仪表板、方向盘
    box(mb, "steel", -0.5, -0.15, 0.6, 0.5, 0.7, 0.66)
    box(mb, red, -0.3, -0.2, 0.66, 0.3, -0.05, 1.3)
    mb.tube("paint_black", (0.0, -0.05, 1.2), (0.0, 0.22, 1.42), 0.025, 0.025, 6)
    mb.tube("paint_black", (0.0, 0.2, 1.4), (0.0, 0.235, 1.43), 0.2, 0.2, 12)
    box(mb, "paint_black", -0.24, 0.55, 0.95, 0.24, 1.0, 1.05)
    box(mb, "paint_black", -0.24, 0.95, 1.05, 0.24, 1.05, 1.5)
    mb.tube("steel", (0.0, 0.75, 0.66), (0.0, 0.75, 0.95), 0.06, 0.06, 8)
    box(mb, "paint_black", -0.12, 1.0, 0.45, 0.12, 1.25, 0.6)  # 牵引钩
    height = 2.02
    if k == 0:  # 遮阳棚
        for sx in (-1, 1):
            for y in (-0.12, 1.05):
                mb.tube("steel", (sx * 0.5, y, 0.66 if y < 0 else 1.2), (sx * 0.5, y, 2.25), 0.03, 0.03, 6)
        box(mb, red, -0.62, -0.3, 2.25, 0.62, 1.2, 2.33)
        box(mb, "paint_white", -0.58, -0.26, 2.33, 0.58, 1.16, 2.36)
        height = 2.36
    else:  # 防滚架
        for sx in (-1, 1):
            mb.tube("steel", (sx * 0.42, 1.08, 1.2), (sx * 0.42, 1.08, 1.95), 0.03, 0.03, 6)
        mb.tube("steel", (-0.42, 1.08, 1.95), (0.42, 1.08, 1.95), 0.03, 0.03, 6)
    return mb, {"footprint": [1.95, 3.35], "height": height, "params": {"canopy": k == 0}}
