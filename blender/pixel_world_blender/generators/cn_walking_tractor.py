"""手扶拖拉机（带拖斗）：前面是柴油机头——机身、水箱、大飞轮、排气管，两只带花纹的大驱动轮，两根长扶手往后伸到驾驶座；
后面挂一个木板拖斗，两只小轮子。变体 0 绿色机头 + 空拖斗，1 红色机头 + 拖斗里装着一堆麦秸。
机头朝 -Y（导出后 Godot +Z），原点在整车中心地面，全长约 4.6 米。"""
import math

from ..builder import MeshBuilder
from ._medieval import box
from ._modern import wheel

NAME = "手扶拖拉机"
CATEGORY = "props"
DESC = "Blender 生成的手扶拖拉机：柴油机头、大飞轮、两只大驱动轮、长扶手，后面挂着木板拖斗，有的装着一堆麦秸。"
VARY = "变体 0 绿色机头 + 空拖斗，1 红色机头 + 拖斗装麦秸。"
TAGS = ["cn_village", "yard", "roadside"]
VARIANTS = 2


def build(seed, **over):
    k = (seed - 1) % 2
    paint = ["paint_green", "paint_red"][k]
    mb = MeshBuilder()
    yh = -1.6  # 机头中心
    # 机身 + 水箱 + 油箱
    box(mb, paint, -0.3, yh - 0.55, 0.45, 0.3, yh + 0.35, 0.95)
    box(mb, "steel", -0.22, yh - 0.62, 0.55, 0.22, yh - 0.55, 0.88)      # 散热格栅
    for i in range(4):
        z = 0.6 + i * 0.07
        box(mb, "paint_black", -0.2, yh - 0.64, z, 0.2, yh - 0.62, z + 0.035)
    box(mb, paint, -0.24, yh - 0.35, 0.95, 0.24, yh + 0.15, 1.15)        # 水箱
    box(mb, paint, -0.18, yh + 0.15, 0.95, 0.18, yh + 0.45, 1.1)         # 油箱
    mb.tube("paint_black", (0.18, yh - 0.1, 1.0), (0.2, yh - 0.1, 1.5), 0.04, 0.04, 6)  # 排气管
    mb.tube("paint_black", (0.2, yh - 0.1, 1.5), (0.2, yh - 0.2, 1.55), 0.04, 0.04, 6)
    # 飞轮（机身右侧）
    mb.tube("steel", (0.3, yh - 0.1, 0.72), (0.38, yh - 0.1, 0.72), 0.3, 0.3, 14, math.pi / 14)
    mb.tube(paint, (0.38, yh - 0.1, 0.72), (0.4, yh - 0.1, 0.72), 0.12, 0.12, 10)
    # 变速箱 + 两只大驱动轮
    box(mb, paint, -0.25, yh + 0.2, 0.25, 0.25, yh + 0.6, 0.6)
    for sx in (-1, 1):
        x = sx * 0.55
        wheel(mb, x, yh + 0.4, 0.42, 0.42, 0.22, tyre="tyre", hub=paint, sides=14)
        for i in range(10):  # 轮胎花纹
            a = 2 * math.pi * i / 10
            c = (x, yh + 0.4 + math.cos(a) * 0.43, 0.42 + math.sin(a) * 0.43)
            box(mb, "tyre", x - 0.11, c[1] - 0.03, c[2] - 0.03, x + 0.11, c[1] + 0.03, c[2] + 0.03)
        mb.tube("steel", (sx * 0.25, yh + 0.4, 0.42), (x, yh + 0.4, 0.42), 0.05, 0.05, 6)
    # 长扶手：从变速箱往后上方伸，末端黑色把套
    for sx in (-1, 1):
        p0 = (sx * 0.22, yh + 0.55, 0.6)
        p1 = (sx * 0.4, yh + 1.7, 1.05)
        mb.tube("steel", p0, p1, 0.03, 0.03, 6)
        mb.tube("tyre", p1, (sx * 0.42, yh + 1.9, 1.08), 0.035, 0.035, 6)
    mb.tube("steel", (-0.3, yh + 1.2, 0.88), (0.3, yh + 1.2, 0.88), 0.025, 0.025, 6)
    # 拖斗：牵引杆 + 木板车厢 + 驾驶座 + 两只小轮
    ytr = 0.85
    box(mb, "iron", -0.05, yh + 0.6, 0.45, 0.05, ytr - 0.9, 0.52)
    box(mb, "iron", -0.7, ytr - 0.95, 0.5, 0.7, ytr + 1.05, 0.6)
    box(mb, "boards", -0.75, ytr - 0.9, 0.6, 0.75, ytr + 1.0, 0.65)
    for (x0, y0, x1, y1) in ((-0.75, ytr - 0.9, 0.75, ytr - 0.85), (-0.75, ytr + 0.95, 0.75, ytr + 1.0),
                             (-0.75, ytr - 0.9, -0.7, ytr + 1.0), (0.7, ytr - 0.9, 0.75, ytr + 1.0)):
        box(mb, "boards", x0, y0, 0.65, x1, y1, 1.05)
    box(mb, "wall_wood", -0.3, ytr - 0.88, 1.05, 0.3, ytr - 0.6, 1.12)   # 驾驶座（拖斗前沿）
    for sx in (-1, 1):
        wheel(mb, sx * 0.85, ytr + 0.1, 0.3, 0.3, 0.16, sides=12)
    height = 1.55
    if k == 1:
        mb.blob("hay", 0.0, ytr + 0.05, 1.35, 0.72, 0.9, 10)
        height = 1.8
    return mb, {"footprint": [1.9, 4.6], "height": height, "params": {"paint": paint, "load": k == 1}}
