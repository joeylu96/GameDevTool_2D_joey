"""篱笆模块：一段 2 米长的围栏，从 x=-1 到 x=+1（沿 X 方向），只在起点 x=-1 有一根柱子；
一排篱笆首尾相接地摆，最后（以及门口缺口两侧）用 fence_post 补柱子——这样相邻模块的柱子不会重叠（重叠会闪烁）。
变体序号 = 款式：0 白色尖头栅栏（picket）、1 乡村木栏（rail）、2 矮石墙（stone）、3 深色木条栅栏（paling）。
对照 Godot 端 build_fence。正面朝 -Y。"""
from ..builder import MeshBuilder

NAME = "篱笆"
CATEGORY = "street"
DESC = "Blender 生成的篱笆模块：每段 2 米，白色尖头栅栏、乡村木栏、矮石墙、深色木条栅栏四种款式，首尾相接围成一圈。"
VARY = "四种款式（变体 0 白栅栏、1 木栏、2 石墙、3 深色木条）。"
TAGS = ["yard", "town", "plains"]
VARIANTS = 4
STYLES = ["picket", "rail", "stone", "paling"]
LENGTH = 2.0


def _b(mb, key, x0, y0, z0, x1, y1, z1, top=True):
    """按 Godot 坐标写的盒子（Godot (x, y, z) → 这里 (x, -z, y)）"""
    mb.box(key, (x0, -z1, y0), (x1, -z0, y1), top=top)


def post(mb, style, px):
    """一根柱子（fence_post 也用它）"""
    if style == "rail":
        _b(mb, "trunk", px - 0.08, 0, -0.08, px + 0.08, 0.95, 0.08)
    elif style == "stone":
        _b(mb, "stone", px - 0.2, 0, -0.2, px + 0.2, 0.62, 0.2)
        _b(mb, "curb", px - 0.23, 0.62, -0.23, px + 0.23, 0.7, 0.23)
    elif style == "paling":
        _b(mb, "wall_wood", px - 0.07, 0, -0.07, px + 0.07, 1.15, 0.07)
        mb.frustum("wall_wood", px, 0.0, 1.15, 1.23, 0.08, 0.0, 4, 0.785, top=False)
    else:
        _b(mb, "trim", px - 0.06, 0, -0.08, px + 0.06, 0.9, 0.04)
        mb.frustum("trim", px, 0.02, 0.9, 1.0, 0.06, 0.0, 4, 0.785, top=False)


def build(seed, **over):
    style = STYLES[(seed - 1) % 4]
    mb = MeshBuilder()
    x0, x1 = -1.0, 1.0
    post(mb, style, x0)
    if style == "rail":
        for y in (0.35, 0.7):
            _b(mb, "wall_wood", x0, y, -0.04, x1, y + 0.11, 0.05)
        h = 0.95
    elif style == "stone":
        _b(mb, "stone", x0, 0, -0.16, x1, 0.48, 0.16)
        _b(mb, "curb", x0, 0.48, -0.2, x1, 0.58, 0.2)
        h = 0.7
    elif style == "paling":
        for y in (0.3, 0.8):
            _b(mb, "wall_wood", x0, y, -0.06, x1, y + 0.08, -0.02)
        x = x0 + 0.16
        while x < x1 - 0.06:
            _b(mb, "door_wood", x - 0.055, 0.04, -0.02, x + 0.055, 1.0, 0.02, top=False)
            mb.frustum("door_wood", x, 0.0, 1.0, 1.08, 0.055, 0.0, 4, 0.785, top=False)
            x += 0.16
        h = 1.23
    else:
        for y in (0.28, 0.6):
            _b(mb, "trim", x0, y, -0.07, x1, y + 0.07, -0.025)
        x = x0 + 0.18
        while x < x1 - 0.08:
            _b(mb, "trim", x - 0.045, 0.05, -0.025, x + 0.045, 0.76, 0.02, top=False)
            mb.frustum("trim", x, 0.0, 0.76, 0.84, 0.045, 0.0, 4, 0.785, top=False)
            x += 0.21
        h = 1.0
    return mb, {"footprint": [LENGTH, 0.4], "height": h, "style": style, "length": LENGTH}
