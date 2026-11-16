"""村口小卖部：一间砖房，正面一扇开着的售货窗——木板窗扇往上撑开当雨搭，下面是水泥柜台，窗上方一块空白招牌（不写字）；
侧面一扇小门；门口码着几箱汽水瓶。变体 0 小青瓦双坡顶，1 水泥平顶。正面朝 -Y（导出后 Godot +Z），原点在占地中心地面。"""
import math

from ..builder import MeshBuilder
from ._medieval import box, walls_box
from ._modern import cn_roof

NAME = "小卖部"
CATEGORY = "buildings"
DESC = "Blender 生成的村口小卖部：砖房正面一扇撑开的木板售货窗、水泥柜台、空白招牌，门口码着几箱汽水瓶。"
VARY = "变体 0 红砖配小青瓦顶，1 青砖配水泥平顶；招牌颜色不同。"
TAGS = ["cn_village", "town", "roadside"]
VARIANTS = 2


def _crate(mb, x, y, z, bottle):
    """一箱汽水：木箱 + 一排排瓶口"""
    box(mb, "crate", x - 0.25, y - 0.18, z, x + 0.25, y + 0.18, z + 0.28)
    for i in range(4):
        for j in range(3):
            bx, by = x - 0.18 + i * 0.12, y - 0.11 + j * 0.11
            box(mb, bottle, bx - 0.03, by - 0.03, z + 0.28, bx + 0.03, by + 0.03, z + 0.36)


def build(seed, **over):
    k = (seed - 1) % 2
    wall = ["brick_red_cn", "brick_grey"][k]
    sign = ["paint_red", "paint_teal"][k]
    w, d, H = 5.5, 4.5, 3.0
    hw, hd = w * 0.5, d * 0.5
    mb = MeshBuilder()
    box(mb, "cement", -hw - 0.1, -hd - 0.1, 0.0, hw + 0.1, hd + 0.1, 0.15)
    W = walls_box(mb, wall, -hw, -hd, 0.15, hw, hd, 0.15 + H)
    f = W["front"]
    # 售货窗：窗洞（深色）+ 水泥柜台 + 撑起来的木板窗扇
    s0, s1, z0, z1 = 0.8, w - 0.8, 0.95, 2.2
    f.quad(mb, "glass", s0, z0, s1, z1, 0.01)
    f.box(mb, "cement", s0 - 0.1, z0 - 0.12, s1 + 0.1, z0, 0.0, 0.4)
    for s in (s0 - 0.08, s1):
        f.box(mb, "wall_wood", s, z0, s + 0.08, z1 + 0.08, 0.0, 0.08)
    f.box(mb, "wall_wood", s0 - 0.08, z1, s1 + 0.08, z1 + 0.08, 0.0, 0.08)
    # 窗扇往外上方撑开约 60°
    a = math.radians(60.0)
    yy0, zz0 = -hd - 0.04, 0.15 + z1 + 0.08
    out = 1.0
    yy1, zz1 = yy0 - out * math.sin(a), zz0 - out * math.cos(a) + 0.0
    x0, x1 = -hw + s0 - 0.08, -hw + s1 + 0.08
    pts = [(x0, yy0, zz0), (x1, yy0, zz0), (x1, yy1, zz0 + out * math.cos(a)), (x0, yy1, zz0 + out * math.cos(a))]
    mb.face("door_wood", pts, (0, -0.5, 0.86))
    mb.face("door_wood", [(x, y, z - 0.04) for x, y, z in pts][::-1], (0, 0.5, -0.86))
    for x in (x0 + 0.1, x1 - 0.1):
        mb.tube("wall_wood", (x, yy0 - 0.02, 0.15 + z0), (x, yy1 + 0.08, zz0 + out * math.cos(a) - 0.04), 0.025, 0.025, 4)
    # 招牌（空白）
    f.box(mb, sign, 0.5, 2.45, w - 0.5, 2.9, 0.0, 0.08)
    f.box(mb, "paint_yellow", 0.45, 2.42, w - 0.45, 2.45, 0.0, 0.1)
    f.box(mb, "paint_yellow", 0.45, 2.9, w - 0.45, 2.93, 0.0, 0.1)
    # 侧门
    W["right"].box(mb, "door_wood", d * 0.5 - 0.45, 0.0, d * 0.5 + 0.45, 2.0, 0.0, 0.04)
    W["right"].box(mb, "red_paper", d * 0.5 - 0.15, 2.1, d * 0.5 + 0.15, 2.35, 0.0, 0.015)
    # 屋顶
    top = 0.15 + H
    if k == 0:
        ridge, gables = cn_roof(mb, -hw, hw, -hd, hd, top, 26.0, eave=0.45, gable=0.25)
        for sa, tri in gables:
            mb.face(wall, tri, (sa, 0, 0))
        height = ridge + 0.45
    else:
        box(mb, "cement", -hw - 0.2, -hd - 0.2, top, hw + 0.2, hd + 0.2, top + 0.15)
        box(mb, wall, -hw, -hd, top + 0.15, hw, -hd + 0.24, top + 0.6)
        height = top + 0.6
    # 门口的汽水箱
    for i, (x, y) in enumerate(((-hw + 0.6, -hd - 0.6), (-hw + 1.15, -hd - 0.6), (-hw + 0.85, -hd - 0.6))):
        z = 0.0 if i < 2 else 0.36
        _crate(mb, x if i < 2 else -hw + 0.88, y, z, ["paint_green", "paint_red", "paint_yellow"][i])
    return mb, {"footprint": [round(w + 0.6, 2), round(d + 1.6, 2)], "height": round(height, 2),
                "params": {"width": w, "depth": d, "roof": ["tile", "flat"][k]}}
