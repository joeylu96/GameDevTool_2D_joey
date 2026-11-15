"""风车塔身：石砌八边形底座 + 白色锥塔 + 腰线 + 门窗 + 尖顶 + 伸出的轮轴。叶片是另一个资产 windmill_blades（会转）。
对照 Godot 端 build_windmill_tower。门朝 -Y（导出后 Godot +Z）。叶片轮毂中心：Blender (0, -1.85, 6.9) = Godot (0, 6.9, 1.85)，
和 Godot 端 Props.windmill_hub() 一样；三个变体的轮毂位置相同。"""
import math

from ..builder import MeshBuilder
from ._common import door, window

NAME = "风车塔身"
CATEGORY = "landmarks"
DESC = "Blender 生成的风车塔身：石砌底座、白色锥形塔、木门小窗和尖顶，叶片另外装在轮轴上转动。"
VARY = "屋顶颜色（红 / 灰）、塔身（白灰泥 / 赭黄横木板）、门的颜色随变体变化；尺寸和轮毂位置不变。"
TAGS = ["plains"]
VARIANTS = 3
HUB = (0.0, -1.85, 6.9)


def build(seed, **over):
    k = (seed - 1) % 3
    roof = ("roof_red", "roof_grey", "roof_red")[k]
    body = ("plaster_white", "plaster_white", "siding_ochre")[k]
    door_mat = ("door_wood", "door_red", "door_green")[k]
    mb = MeshBuilder()
    rot = math.pi / 8
    mb.frustum("stone", 0, 0, -0.2, 0.4, 2.4, 2.3, 8, rot, top=True)
    mb.frustum(body, 0, 0, 0.4, 6.4, 2.0, 1.45, 8, rot, top=False)
    mb.frustum("trim", 0, 0, 3.3, 3.5, 1.82, 1.8, 8, rot, top=False)
    mb.frustum("roof_cap", 0, 0, 6.4, 6.6, 1.65, 1.6, 8, rot, top=False, bottom=True)
    mb.frustum(roof, 0, 0, 6.6, 8.6, 1.6, 0.0, 8, rot, top=False)
    # 门窗贴在正面（-Y）那个面上：塔身是八边形、一个面正对 -Y（rot = π/8）
    ap = 2.0 * math.cos(math.pi / 8) + 0.01
    door(mb, (0, -(ap - 0.06), 0.4), (0, -1, 0), w=0.9, h=1.8, mat=door_mat, glass_top=False)
    y = 3.9
    rr = (2.0 + (1.45 - 2.0) * (y - 0.4) / 6.0) * math.cos(math.pi / 8) + 0.01
    window(mb, (0, -rr, y), (0, -1, 0), 0.25, 0.6)
    mb.tube("trunk", (0, -0.6, 6.9), (HUB[0], HUB[1] - 0.25, HUB[2]), 0.18, 0.16, 8)
    return mb, {"footprint": [4.8, 4.8], "height": 8.6, "hub": list(HUB)}
