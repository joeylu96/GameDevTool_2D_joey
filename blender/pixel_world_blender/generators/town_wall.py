"""城墙模块：一段 6 米长的石砌城墙，首尾相接连成一圈。
约定：沿 X 从 -3 到 +3（模块长 6 米，两端平切，直接拼接）；墙厚 1.6 米（y ∈ [-0.8, 0.8]），
**外侧（城外）朝 -Y**（导出后 Godot +Z），内侧（城里）朝 +Y；走道顶面高 4.2 米，外侧胸墙 + 垛口顶到约 5.6 米，
内侧一道矮护墙。垛口按 1.5 米周期排（两端各留半个垛口缺），拼接后连续。原点在模块中心地面。"""
from ..builder import MeshBuilder
from ._medieval import Wall, box, crenellations

NAME = "城墙"
CATEGORY = "landmarks"
DESC = "Blender 生成的中世纪城墙模块：6 米一段的浅色石砌城墙，外侧垛口、顶上走道和内侧护墙，首尾相接围成城镇。"
VARY = "变体 0 朴素、1 带箭窗和腰线、2 内侧带扶壁和外侧排水石嘴；变体 0、1 米白石灰岩，变体 2 灰绿色石（雪地城堡）。"
TAGS = ["town", "medieval"]
VARIANTS = 3

L = 6.0
T = 1.6
WALK = 4.2


def build(seed, **over):
    k = seed - 1
    stone = ["castle_stone", "castle_stone", "stone_greygreen"][k % 3]
    mb = MeshBuilder()
    hl, ht = L * 0.5, T * 0.5
    para = 0.45
    # 勒脚（外侧略宽）
    box(mb, "cobble_wall", -hl, -ht - 0.25, 0.0, hl, ht + 0.1, 0.8)
    # 墙体外、内两面（两端截面单独画，拼接处是平的）
    mb.face(stone, [(-hl, -ht, 0.8), (hl, -ht, 0.8), (hl, -ht, WALK + 0.55), (-hl, -ht, WALK + 0.55)], (0, -1, 0))
    mb.face(stone, [(hl, ht, 0.8), (-hl, ht, 0.8), (-hl, ht, WALK + 0.35), (hl, ht, WALK + 0.35)], (0, 1, 0))
    for x, sx in ((-hl, -1), (hl, 1)):
        mb.face(stone, [(x, -ht, 0.8), (x, ht, 0.8), (x, ht, WALK + 0.35), (x, ht - 0.15, WALK + 0.35), (x, ht - 0.15, WALK),
                        (x, -ht + para, WALK), (x, -ht + para, WALK + 0.55), (x, -ht, WALK + 0.55)], (sx, 0, 0))
    # 走道石板
    mb.face("cobble_wall", [(-hl, -ht + para, WALK), (hl, -ht + para, WALK), (hl, ht - 0.15, WALK), (-hl, ht - 0.15, WALK)], (0, 0, 1))
    # 外侧胸墙顶 + 内侧面
    mb.face(stone, [(-hl, -ht, WALK + 0.55), (hl, -ht, WALK + 0.55), (hl, -ht + para, WALK + 0.55), (-hl, -ht + para, WALK + 0.55)], (0, 0, 1))
    mb.face(stone, [(hl, -ht + para, WALK), (-hl, -ht + para, WALK), (-hl, -ht + para, WALK + 0.55), (hl, -ht + para, WALK + 0.55)], (0, 1, 0))
    crenellations(mb, stone, -hl, hl, -ht, -ht + para, WALK + 0.55, h=0.85, merlon=0.9, gap=0.6, start=-hl + 0.3)
    # 内侧矮护墙
    mb.face(stone, [(-hl, ht - 0.15, WALK + 0.35), (hl, ht - 0.15, WALK + 0.35), (hl, ht, WALK + 0.35), (-hl, ht, WALK + 0.35)], (0, 0, 1))
    mb.face(stone, [(-hl, ht - 0.15, WALK), (hl, ht - 0.15, WALK), (hl, ht - 0.15, WALK + 0.35), (-hl, ht - 0.15, WALK + 0.35)], (0, -1, 0))
    # 垛口下挑出的石条（外侧）
    box(mb, "cobble_wall", -hl, -ht - 0.12, WALK - 0.25, hl, -ht, WALK - 0.05)
    outer = Wall((-hl, -ht, 0.0), (1, 0, 0), (0, -1, 0))
    if k % 3 == 1:
        box(mb, "cobble_wall", -hl, -ht - 0.08, 2.2, hl, -ht, 2.36)
        for s in (1.5, 4.5):
            outer.quad(mb, "coal", s - 0.07, 2.7, s + 0.07, 3.6, 0.012)
            outer.box(mb, "cobble_wall", s - 0.2, 2.6, s + 0.2, 2.7, 0.0, 0.06)
    if k % 3 == 2:
        box(mb, stone, -0.45, ht, 0.0, 0.45, ht + 0.7, 3.2)
        box(mb, stone, -0.38, ht, 3.2, 0.38, ht + 0.4, 3.9)
        for x in (-1.5, 1.5):
            box(mb, "cobble_wall", x - 0.1, -ht - 0.45, WALK - 0.2, x + 0.1, -ht, WALK - 0.05)
    info = {"footprint": [L, T + 0.35], "height": WALK + 1.4,
            "params": {"length": L, "thickness": T, "walk": WALK, "outside": "-Y"}}
    return mb, info
