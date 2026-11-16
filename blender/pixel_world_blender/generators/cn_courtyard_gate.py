"""农家院门（门楼）：两根砖垛 + 木过梁 + 小青瓦双坡门头，两扇木板大门朝院里（+Y）敞开着。
总长 4 米（x -2..+2，和 cn_courtyard_wall 模块一样长，两端直接接院墙），门洞 3 米宽（x ±1.5）、2.6 米高；
外侧朝 -Y（导出后 Godot +Z），原点在门洞中心地面。门垛外侧贴红纸对联，门楣贴横批（不写字）。"""
import math

from ..builder import MeshBuilder
from ._medieval import box
from ._modern import cn_roof

NAME = "农家院门"
CATEGORY = "street"
DESC = "Blender 生成的农家院门：砖垛、木过梁、小青瓦门头，两扇木板大门朝院里敞开，门垛上贴着红纸对联。"
VARY = "变体 0 红砖、1 青砖；门的颜色随变体变化。"
TAGS = ["cn_village", "yard"]
VARIANTS = 2


def build(seed, **over):
    k = (seed - 1) % 2
    key = ["brick_red_cn", "brick_grey"][k]
    door = ["door_red", "door_wood"][k]
    mb = MeshBuilder()
    H = 2.6
    for sx in (-1, 1):
        x0, x1 = sx * 1.5, sx * 2.0
        box(mb, "stone", min(x0, x1), -0.3, 0.0, max(x0, x1), 0.3, 0.35)
        box(mb, key, min(x0, x1), -0.26, 0.35, max(x0, x1), 0.26, H + 0.55)
        # 对联：贴在门垛朝外的一面
        xc = sx * 1.75
        box(mb, "red_paper", xc - 0.14, -0.275, 0.6, xc + 0.14, -0.26, 2.3)
        # 门扇：朝院里（+Y）推开，贴着门垛内侧
        box(mb, door, sx * 1.5 - (0.06 if sx > 0 else -0.0), 0.26, 0.05, sx * 1.5 + (0.0 if sx > 0 else 0.06), 0.26 + 1.45, H - 0.05)
        for z in (0.5, H - 0.6):
            box(mb, "iron", sx * 1.5 - 0.075, 0.4, z - 0.04, sx * 1.5 + 0.075, 1.55, z + 0.04)
    # 门槛石、木过梁、门楣横批
    box(mb, "stone", -1.5, -0.2, 0.0, 1.5, 0.2, 0.12)
    box(mb, "wall_wood", -2.05, -0.3, H, 2.05, 0.3, H + 0.25)
    box(mb, "red_paper", -0.6, -0.315, H + 0.03, 0.6, -0.3, H + 0.22)
    box(mb, key, -2.0, -0.26, H + 0.25, 2.0, 0.26, H + 0.55)
    ridge, gables = cn_roof(mb, -2.0, 2.0, -0.3, 0.3, H + 0.55, 30.0, eave=0.45, gable=0.25, t=0.1)
    for sa, tri in gables:
        mb.face(key, tri, (sa, 0, 0))
    return mb, {"footprint": [4.6, 1.5], "height": round(ridge + 0.45, 2),
                "params": {"opening": 3.0, "length": 4.0, "wall": key}}
