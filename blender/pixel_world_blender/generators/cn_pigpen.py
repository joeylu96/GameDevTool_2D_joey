"""猪圈：一米高的砖墙围成 3×2.6 米的圈，后半边搭一个小青瓦单坡棚子遮雨，前墙上开一个小口放水泥食槽，
地面是水泥。开口（食槽）朝 -Y（导出后 Godot +Z），原点在占地中心地面。"""
import math

from ..builder import MeshBuilder
from ._medieval import box

NAME = "猪圈"
CATEGORY = "props"
DESC = "Blender 生成的农家猪圈：矮砖墙围成的圈，后半边搭着小青瓦单坡棚，前墙边一只水泥食槽。"
VARY = "变体 0 红砖，1 青砖；棚子的进深不同。"
TAGS = ["cn_village", "yard"]
VARIANTS = 2


def build(seed, **over):
    k = (seed - 1) % 2
    key = ["brick_red_cn", "brick_grey"][k]
    w, d, h = 3.0, 2.6, 1.0
    hw, hd = w * 0.5, d * 0.5
    t = 0.24
    mb = MeshBuilder()
    box(mb, "cement", -hw, -hd, 0.0, hw, hd, 0.06)
    box(mb, key, -hw, hd - t, 0.0, hw, hd, 2.0)                   # 后墙高到棚檐
    for sx in (-1, 1):
        box(mb, key, sx * hw - (t if sx > 0 else 0.0), -hd, 0.0, sx * hw + (0.0 if sx > 0 else t), hd - t, h)
    box(mb, key, -hw, -hd, 0.0, -0.45, -hd + t, h)
    box(mb, key, 0.45, -hd, 0.0, hw, -hd + t, h)
    box(mb, key, -0.45, -hd, 0.0, 0.45, -hd + t, 0.35)              # 食槽口下的矮墙
    box(mb, "brick_grey", -hw - 0.03, -hd - 0.03, h, hw + 0.03, -hd + t + 0.03, h + 0.06)
    # 水泥食槽（一半在圈外）
    box(mb, "cement", -0.5, -hd - 0.35, 0.0, 0.5, -hd + 0.4, 0.3)
    box(mb, "water", -0.4, -hd - 0.25, 0.22, 0.4, -hd + 0.3, 0.23)
    # 后半边的单坡棚：两根木柱 + 小青瓦顶（后高前低）
    yb = [0.0, -0.3][k]
    for sx in (-1, 1):
        box(mb, "trunk", sx * (hw - 0.2) - 0.06, yb - 0.06, 0.0, sx * (hw - 0.2) + 0.06, yb + 0.06, 1.6)
    pts = [(-hw - 0.2, yb - 0.4, 1.55), (hw + 0.2, yb - 0.4, 1.55), (hw + 0.2, hd + 0.2, 2.1), (-hw - 0.2, hd + 0.2, 2.1)]
    mb.face("tile_cn", pts, (0, -0.4, 1))
    mb.face("roof_under", [(x, y, z - 0.08) for x, y, z in pts][::-1], (0, 0.4, -1))
    box(mb, "roof_cap", -hw - 0.2, yb - 0.46, 1.47, hw + 0.2, yb - 0.38, 1.56)
    box(mb, "trunk", -hw, yb - 0.1, 1.45, hw, yb + 0.05, 1.55)
    return mb, {"footprint": [round(w + 0.4, 2), round(d + 0.8, 2)], "height": 2.15, "params": {"wall": key}}
