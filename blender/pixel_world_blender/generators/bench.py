"""长椅：长约 1.6 米，正面（坐的一面）朝 -Y（导出后对应 Godot +Z）。
变体序号 = 款式：0 木条长椅 + 铁艺腿（slat）、1 带扶手的绿漆长椅（park）、2 原木长凳（log）。对照 Godot 端 build_bench。"""
from ..builder import MeshBuilder

NAME = "长椅"
CATEGORY = "street"
DESC = "Blender 生成的长椅：木条长椅、公园绿漆长椅、原木长凳三种款式，摆在路灯旁和广场上。"
VARY = "三种款式（变体 0 木条、1 公园、2 原木）。"
TAGS = ["roadside", "plaza", "town"]
VARIANTS = 3
STYLES = ["slat", "park", "log"]


def _b(mb, key, x0, y0, z0, x1, y1, z1, top=True):
    """按 Godot 坐标写的盒子（Godot (x, y, z) → 这里 (x, -z, y)）"""
    mb.box(key, (x0, -z1, y0), (x1, -z0, y1), top=top)


def build(seed, **over):
    style = STYLES[(seed - 1) % 3]
    mb = MeshBuilder()
    if style == "park":
        for i in range(3):
            z = -0.18 + i * 0.14
            _b(mb, "deck", -0.85, 0.42, z, 0.85, 0.48, z + 0.11)
        for i in range(2):
            y = 0.62 + i * 0.16
            _b(mb, "deck", -0.85, y, -0.3, 0.85, y + 0.11, -0.24)
        for x in (-0.8, 0.8):
            _b(mb, "metal_green", x - 0.05, 0, -0.26, x + 0.05, 0.95, -0.2, top=False)
            _b(mb, "metal_green", x - 0.05, 0, 0.12, x + 0.05, 0.42, 0.18, top=False)
            _b(mb, "metal_green", x - 0.05, 0.62, -0.26, x + 0.05, 0.67, 0.2)
        h = 0.95
    elif style == "log":
        _b(mb, "trunk", -0.8, 0.32, -0.18, 0.8, 0.48, 0.18)
        for x in (-0.55, 0.55):
            mb.frustum("rock", x, 0, 0.0, 0.32, 0.2, 0.17, 6, 0.3, top=False)
        h = 0.48
    else:
        _b(mb, "boards", -0.8, 0.42, -0.2, 0.8, 0.5, 0.22)
        _b(mb, "boards", -0.8, 0.6, -0.28, 0.8, 0.95, -0.21)
        for x in (-0.66, 0.66):
            _b(mb, "metal", x - 0.05, 0, -0.18, x + 0.05, 0.42, 0.2, top=False)
            _b(mb, "metal", x - 0.04, 0.42, -0.3, x + 0.04, 0.98, -0.2)
        h = 0.98
    return mb, {"footprint": [1.8, 0.7], "height": h, "style": style}
