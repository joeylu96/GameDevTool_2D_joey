"""篱笆柱：和 fence 模块同款的单根柱子，放在原点。用来收一排篱笆的尾、门口缺口的两侧。
变体序号 = 款式，和 fence 一一对应：0 白栅栏、1 木栏、2 石墙、3 深色木条。"""
from ..builder import MeshBuilder
from .fence import STYLES, post

NAME = "篱笆柱"
CATEGORY = "street"
DESC = "Blender 生成的篱笆柱：和篱笆模块同款的单根柱子，一排篱笆的末尾和门口两侧用。"
VARY = "四种款式，和篱笆模块一一对应。"
TAGS = ["yard", "town", "plains"]
VARIANTS = 4


def build(seed, **over):
    style = STYLES[(seed - 1) % 4]
    mb = MeshBuilder()
    post(mb, style, 0.0)
    return mb, {"footprint": [0.4, 0.4], "height": 1.2, "style": style}
