"""农家院墙模块：直的一段 4 米长、约 2 米高的砖墙（或土坯墙），墙头一条小青瓦（土坯墙是草）压顶。
沿 X 从 -2 到 +2，原点在模块中心地面，墙厚 0.36（y ±0.18）；两面一样，外侧约定朝 -Y（导出后 Godot +Z）。
两端切平，首尾相接；和 cn_courtyard_gate（同样 4 米长）可以直接拼在一条线上。"""
import math

from ..builder import MeshBuilder
from ._medieval import box

NAME = "农家院墙"
CATEGORY = "street"
DESC = "Blender 生成的农家院墙：4 米一段的红砖 / 青砖 / 土坯墙，墙头一条小青瓦或草压顶，首尾相接围成院子。"
VARY = "变体 0 红砖、1 青砖、2 土坯墙配草压顶。"
TAGS = ["cn_village", "yard"]
VARIANTS = 3


def coping(mb, x0, x1, z, key="tile_cn", w=0.62, h=0.22):
    """墙头的小双坡压顶（屋脊沿 X）"""
    yc = 0.0
    for s in (-1, 1):
        pts = [(x0, yc, z + h), (x1, yc, z + h), (x1, yc + s * w * 0.5, z), (x0, yc + s * w * 0.5, z)]
        mb.face(key, pts, (0, s * 0.6, 0.8))
        mb.face(key, [(x0, yc + s * w * 0.5, z), (x1, yc + s * w * 0.5, z), (x1, yc + s * w * 0.5, z - 0.05),
                      (x0, yc + s * w * 0.5, z - 0.05)], (0, s, 0))
    for xe, sx in ((x0, -1), (x1, 1)):
        mb.face(key, [(xe, -w * 0.5, z), (xe, w * 0.5, z), (xe, 0.0, z + h)], (sx, 0, 0))
    box(mb, "roof_cap", x0, -0.06, z + h - 0.03, x1, 0.06, z + h + 0.06)


def build(seed, **over):
    k = (seed - 1) % 3
    key = ["brick_red_cn", "brick_grey", "mudbrick"][k]
    H = [2.0, 2.1, 1.9][k]
    mb = MeshBuilder()
    box(mb, "stone" if k < 2 else "brick_grey", -2.0, -0.22, 0.0, 2.0, 0.22, 0.3)  # 墙基
    box(mb, key, -2.0, -0.18, 0.3, 2.0, 0.18, H)
    if k < 2:
        box(mb, "brick_grey", -2.0, -0.21, H - 0.1, 2.0, 0.21, H)  # 一皮出挑的砖
        coping(mb, -2.0, 2.0, H)
        top = H + 0.28
    else:
        mb.tube("thatch", (-2.0, 0.0, H + 0.12), (2.0, 0.0, H + 0.12), 0.3, 0.3, 8, math.pi / 8, caps=True)
        top = H + 0.42
    return mb, {"footprint": [4.0, 0.62], "height": round(top, 2), "params": {"wall": key, "height": H}}
