"""垃圾桶：变体 0 圆柱形钢垃圾桶（带顶盖、投口）、1 方形木挂板垃圾箱、2 并排的两个分类垃圾桶（蓝 / 灰）。
投口朝 -Y（导出后 Godot +Z），原点在占地中心地面。"""
from ..builder import MeshBuilder
from ._medieval import box

NAME = "垃圾桶"
CATEGORY = "street"
DESC = "Blender 生成的街边垃圾桶：圆柱钢桶、木挂板方箱、两个并排的分类桶三种。"
VARY = "三种款式（变体 0 圆柱钢桶、1 木挂板方箱、2 分类桶）。"
TAGS = ["town", "modern", "roadside", "plaza"]
VARIANTS = 3


def _wheelie(mb, x, color):
    """带轮子的分类桶：桶身 + 盖 + 两个小轮"""
    box(mb, color, x - 0.3, -0.3, 0.08, x + 0.3, 0.3, 0.95)
    box(mb, color, x - 0.33, -0.36, 0.95, x + 0.33, 0.32, 1.01)
    box(mb, "paint_black", x - 0.12, -0.38, 0.88, x + 0.12, -0.33, 0.93)
    for sx in (-1, 1):
        mb.tube("tyre", (x + sx * 0.25, 0.26, 0.08), (x + sx * 0.33, 0.26, 0.08), 0.08, 0.08, 8)


def build(seed, **over):
    k = (seed - 1) % 3
    mb = MeshBuilder()
    if k == 0:
        mb.frustum("steel", 0.0, 0.0, 0.0, 0.05, 0.3, 0.3, 12)
        mb.frustum("paint_black", 0.0, 0.0, 0.05, 0.85, 0.27, 0.28, 12, top=False)
        mb.frustum("steel", 0.0, 0.0, 0.85, 1.0, 0.3, 0.26, 12)
        box(mb, "paint_black", -0.13, -0.3, 0.86, 0.13, -0.2, 0.96)
        for z in (0.3, 0.6):
            mb.frustum("steel", 0.0, 0.0, z, z + 0.04, 0.285, 0.285, 12, top=False)
        return mb, {"footprint": [0.6, 0.6], "height": 1.0, "params": {"style": "round"}}
    if k == 1:
        box(mb, "concrete", -0.33, -0.33, 0.0, 0.33, 0.33, 0.06)
        box(mb, "clad_wood", -0.3, -0.3, 0.06, 0.3, 0.3, 0.9)
        box(mb, "steel", -0.32, -0.32, 0.9, 0.32, 0.32, 0.97)
        box(mb, "paint_black", -0.16, -0.31, 0.7, 0.16, -0.29, 0.85)
        return mb, {"footprint": [0.66, 0.66], "height": 0.97, "params": {"style": "box"}}
    _wheelie(mb, -0.36, "paint_blue")
    _wheelie(mb, 0.36, "paint_grey")
    return mb, {"footprint": [1.4, 0.8], "height": 1.01, "params": {"style": "pair"}}
