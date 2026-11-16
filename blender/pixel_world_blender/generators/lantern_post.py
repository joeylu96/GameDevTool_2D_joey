"""中世纪灯柱：方木柱（底部石块压着）+ 斜撑的横臂，臂端铁链挂一盏铁框灯笼，灯笼里的玻璃夜里发光（bulb_warm）。
横臂伸向 -Y（导出后 Godot +Z，朝路）。原点在柱脚中心地面。"""
import math

from ..builder import MeshBuilder
from ._medieval import box

NAME = "中世纪灯柱"
CATEGORY = "street"
DESC = "Blender 生成的中世纪灯柱：方木柱、斜撑横臂、铁链挂着铁框灯笼，夜里灯笼发出暖光，摆在中世纪小镇的街边。"
VARY = "柱高、横臂长度、单臂 / 双臂随变体变化。"
TAGS = ["town", "medieval", "roadside"]
VARIANTS = 3


def _lantern(mb, x, y, z):
    """灯笼顶在 z：铁顶盖 + 四根铁框 + 发光玻璃 + 铁底"""
    mb.frustum("iron", x, y, z - 0.12, z, 0.17, 0.04, 4, math.pi / 4, top=True, bottom=True)
    mb.frustum("bulb", x, y, z - 0.42, z - 0.12, 0.11, 0.13, 4, math.pi / 4, top=False, bottom=False)
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        px, py = x + math.cos(a) * 0.135, y + math.sin(a) * 0.135
        box(mb, "iron", px - 0.018, py - 0.018, z - 0.44, px + 0.018, py + 0.018, z - 0.1)
    mb.frustum("iron", x, y, z - 0.5, z - 0.42, 0.06, 0.14, 4, math.pi / 4, top=True, bottom=True)
    box(mb, "iron", x - 0.015, y - 0.015, z, x + 0.015, y + 0.015, z + 0.2)


def build(seed, **over):
    k = seed - 1
    h = [2.8, 3.1, 2.9][k % 3]
    arm = [0.85, 1.0, 0.8][k % 3]
    double = k % 3 == 2
    mb = MeshBuilder()
    box(mb, "castle_stone", -0.3, -0.3, 0.0, 0.3, 0.3, 0.3)
    box(mb, "timber", -0.1, -0.1, 0.3, 0.1, 0.1, h)
    mb.frustum("iron", 0.0, 0.0, h, h + 0.12, 0.12, 0.02, 4, math.pi / 4)
    dirs = [(0, -1)] + ([(0, 1)] if double else [])
    for dx, dy in dirs:
        y_end = dy * arm
        box(mb, "timber", -0.06, min(0.0, y_end), h - 0.28, 0.06, max(0.0, y_end), h - 0.16)
        mb.tube("timber", (0.0, dy * 0.08, h - 0.9), (0.0, dy * arm * 0.6, h - 0.24), 0.045, 0.045, 4, math.pi / 4)
        _lantern(mb, 0.0, y_end - dy * 0.08, h - 0.42)
    return mb, {"footprint": [0.6, round(arm * (2 if double else 1) + 0.6, 2)], "height": round(h + 0.12, 2),
                "light": [0.0, -(arm - 0.08), h - 0.7], "params": {"height": h, "arm": arm, "double": double}}
