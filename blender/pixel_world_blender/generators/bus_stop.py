"""公交候车亭：钢框 + 玻璃后板和侧板 + 微微前倾的顶棚，里面一条长凳，一侧立着灯箱广告牌（空白，夜里发光）。
开口朝 -Y（导出后 Godot +Z，朝路），原点在占地中心地面。"""
from ..builder import MeshBuilder
from ._medieval import box

NAME = "公交候车亭"
CATEGORY = "street"
DESC = "Blender 生成的公交候车亭：钢框玻璃亭、前倾顶棚、亭内长凳，一侧是夜里发光的空白灯箱。"
VARY = "长度（3 / 4 米）和顶棚颜色随变体变化。"
TAGS = ["town", "modern", "roadside"]
VARIANTS = 2


def _glass(mb, pts):
    """两面都朝外的玻璃板（不发光）"""
    mb.face("glass_car", pts, None)
    mb.face("glass_car", pts[::-1], None)


def build(seed, **over):
    k = (seed - 1) % 2
    L = [3.0, 4.0][k]
    roof = ["paint_grey", "paint_teal"][k]
    hl = L * 0.5
    D, H = 1.4, 2.5
    mb = MeshBuilder()
    box(mb, "concrete", -hl - 0.1, -D * 0.5 - 0.1, 0.0, hl + 0.1, D * 0.5 + 0.1, 0.08)
    # 四根钢柱（后两根 + 前两根细一些）
    for x in (-hl + 0.05, hl - 0.05):
        box(mb, "steel", x - 0.05, D * 0.5 - 0.1, 0.08, x + 0.05, D * 0.5, H)
        box(mb, "steel", x - 0.04, -D * 0.5 + 0.1, 0.08, x + 0.04, -D * 0.5 + 0.18, H + 0.08)
    # 后玻璃板、侧玻璃板（底下留空，上面一道横框）
    yb = D * 0.5 - 0.05
    _glass(mb, [(-hl + 0.1, yb, 0.3), (hl - 0.1, yb, 0.3), (hl - 0.1, yb, H - 0.15), (-hl + 0.1, yb, H - 0.15)])
    box(mb, "steel", -hl, yb - 0.04, H - 0.15, hl, yb + 0.04, H - 0.08)
    box(mb, "steel", -hl, yb - 0.04, 0.25, hl, yb + 0.04, 0.3)
    x_side = -hl + 0.05
    _glass(mb, [(x_side, -D * 0.5 + 0.2, 0.3), (x_side, yb - 0.05, 0.3), (x_side, yb - 0.05, H - 0.15), (x_side, -D * 0.5 + 0.2, H - 0.15)])
    # 灯箱广告牌（另一侧，空白、夜里发光）
    xl = hl - 0.05
    box(mb, "steel", xl - 0.08, -D * 0.5 + 0.2, 0.2, xl + 0.08, yb - 0.05, H - 0.1)
    box(mb, "bulb", xl - 0.1, -D * 0.5 + 0.28, 0.3, xl + 0.1, yb - 0.13, H - 0.2)
    # 顶棚：前高后低的薄板（往后排水）+ 前沿檐口
    box(mb, roof, -hl - 0.15, -D * 0.5 - 0.15, H, hl + 0.15, D * 0.5 + 0.15, H + 0.12)
    box(mb, "steel", -hl - 0.15, -D * 0.5 - 0.18, H - 0.05, hl + 0.15, -D * 0.5 - 0.12, H + 0.15)
    # 长凳
    box(mb, "steel", -hl + 0.4, 0.05, 0.42, hl - 0.4, 0.45, 0.47)
    for x in (-hl + 0.5, hl - 0.5):
        box(mb, "steel", x - 0.03, 0.4, 0.08, x + 0.03, 0.46, 0.47)
    return mb, {"footprint": [round(L + 0.3, 2), round(D + 0.3, 2)], "height": round(H + 0.15, 2), "params": {"length": L}}
