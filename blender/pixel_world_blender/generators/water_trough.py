"""饮水槽：长条的木板槽（铁箍）或整块凿出的石槽，里面盛着水；木槽架在两个木墩上，有的旁边立一个手摇水泵。
长边沿 X，正面朝 -Y（导出后 Godot +Z）。原点在中心地面。"""
import math

from ..builder import MeshBuilder
from ._medieval import box

NAME = "饮水槽"
CATEGORY = "props"
DESC = "Blender 生成的中世纪饮水槽：铁箍木槽或凿出的石槽盛着水，有的旁边立着手摇水泵，摆在马厩、酒馆和广场边。"
VARY = "木槽 / 石槽、长度、有没有手摇水泵随变体变化。"
TAGS = ["town", "medieval", "yard", "plaza"]
VARIANTS = 3


def build(seed, **over):
    k = seed - 1
    stone = k % 3 == 1
    length = [1.8, 2.0, 1.5][k % 3]
    pump = k % 3 == 2
    mb = MeshBuilder()
    hl, hw = length * 0.5, 0.36
    if stone:
        h = 0.62
        mat = "cobble_wall"
        box(mb, mat, -hl, -hw, 0.0, hl, -hw + 0.1, h)
        box(mb, mat, -hl, hw - 0.1, 0.0, hl, hw, h)
        box(mb, mat, -hl, -hw + 0.1, 0.0, -hl + 0.1, hw - 0.1, h)
        box(mb, mat, hl - 0.1, -hw + 0.1, 0.0, hl, hw - 0.1, h)
        box(mb, mat, -hl + 0.1, -hw + 0.1, 0.0, hl - 0.1, hw - 0.1, 0.2)
        mb.face("water", [(-hl + 0.1, -hw + 0.1, h - 0.1), (hl - 0.1, -hw + 0.1, h - 0.1), (hl - 0.1, hw - 0.1, h - 0.1), (-hl + 0.1, hw - 0.1, h - 0.1)], (0, 0, 1))
        top = h
    else:
        z0, h = 0.32, 0.75
        for x in (-hl + 0.25, hl - 0.25):
            mb.frustum("trunk", x, 0.0, 0.0, z0, 0.2, 0.18, 8, 0.0, top=True)
        box(mb, "boards", -hl, -hw, z0, hl, -hw + 0.06, h)
        box(mb, "boards", -hl, hw - 0.06, z0, hl, hw, h)
        box(mb, "boards", -hl, -hw + 0.06, z0, -hl + 0.06, hw - 0.06, h)
        box(mb, "boards", hl - 0.06, -hw + 0.06, z0, hl, hw - 0.06, h)
        box(mb, "boards", -hl + 0.06, -hw + 0.06, z0, hl - 0.06, hw - 0.06, z0 + 0.05)
        for x in (-hl + 0.2, hl - 0.2):
            box(mb, "iron", x - 0.03, -hw - 0.015, z0 + 0.05, x + 0.03, hw + 0.015, h + 0.015)
        mb.face("water", [(-hl + 0.06, -hw + 0.06, h - 0.09), (hl - 0.06, -hw + 0.06, h - 0.09), (hl - 0.06, hw - 0.06, h - 0.09), (-hl + 0.06, hw - 0.06, h - 0.09)], (0, 0, 1))
        top = h
    if pump:
        px = hl + 0.25
        box(mb, "timber", px - 0.12, -0.12, 0.0, px + 0.12, 0.12, 1.35)
        box(mb, "iron", px - 0.14, -0.14, 1.35, px + 0.14, 0.14, 1.42)
        mb.tube("iron", (px, -0.12, 1.05), (px - 0.3, -0.12, 1.0), 0.035, 0.03, 6)
        mb.tube("iron", (px - 0.3, -0.12, 1.0), (px - 0.3, -0.12, 0.85), 0.03, 0.03, 6)
        mb.tube("iron", (px + 0.1, 0.0, 1.3), (px + 0.5, 0.0, 1.55), 0.025, 0.025, 6)
        top = max(top, 1.55)
    return mb, {"footprint": [round(length + (0.8 if pump else 0.2), 2), round(hw * 2 + 0.2, 2)], "height": round(top, 2),
                "params": {"stone": stone, "length": length, "pump": pump}}
