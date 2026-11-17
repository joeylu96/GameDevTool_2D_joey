"""农家院墙模块：直的一段 4 米长的院墙。沿 X 从 -2 到 +2，原点在模块中心地面，墙厚 0.36（y ±0.18）；
两面一样，外侧约定朝 -Y（导出后 Godot +Z）。两端切平，首尾相接；和 cn_courtyard_gate（同样 4 米长）可以直接拼在一条线上。
变体：0 红砖墙 + 平压顶（一皮丁砖出挑 + 水泥抹顶，高 1.9 米）、1 灰色水泥抹面墙（高 1.9 米，压顶略宽）、
2 干垒石墙（粗石块，约 1.2 米高，墙头石块高低不齐）、3 红砖墙 + 小青瓦压顶（高 2 米，老式）。
配套院门的变体序号一一对应（见 cn_courtyard_gate）。"""
import random

from ..builder import MeshBuilder
from ._medieval import box

NAME = "农家院墙"
CATEGORY = "street"
DESC = "Blender 生成的农家院墙：4 米一段，红砖平压顶、灰色水泥抹面、干垒石墙、红砖小青瓦压顶四种，首尾相接围成院子。"
VARY = "变体 0 红砖平压顶、1 水泥抹面、2 干垒石墙（1.2 米高）、3 红砖配小青瓦压顶。"
TAGS = ["cn_village", "yard"]
VARIANTS = 4


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


def drystone_run(mb, x0, x1, h, seed, t=0.2):
    """一段干垒石墙：墙身 + 墙头一排大小不一的压顶石"""
    r = random.Random(seed)
    box(mb, "drystone", x0, -t, 0.0, x1, t, h)
    x = x0
    while x < x1 - 0.05:
        ln = min(r.uniform(0.35, 0.7), x1 - x)
        if x1 - (x + ln) < 0.25:
            ln = x1 - x
        hh = r.uniform(0.08, 0.22)
        box(mb, "drystone", x + 0.015, -t - 0.02, h, x + ln - 0.015, t + 0.02, h + hh)
        x += ln
    return h + 0.22


def build(seed, **over):
    k = (seed - 1) % 4
    mb = MeshBuilder()
    if k == 2:
        top = drystone_run(mb, -2.0, 2.0, 1.05, seed * 17 + 3)
        return mb, {"footprint": [4.0, 0.5], "height": round(top, 2), "params": {"wall": "drystone", "height": 1.2}}
    key = ["brick_red_cn", "render_cn", None, "brick_red_cn"][k]
    H = [1.9, 1.9, 0, 2.0][k]
    box(mb, "stone" if k != 1 else "cement", -2.0, -0.22, 0.0, 2.0, 0.22, 0.3)  # 墙基
    box(mb, key, -2.0, -0.18, 0.3, 2.0, 0.18, H)
    if k == 0:
        box(mb, "brick_red_cn", -2.0, -0.22, H - 0.12, 2.0, 0.22, H)      # 一皮出挑的丁砖
        box(mb, "cement", -2.0, -0.2, H, 2.0, 0.2, H + 0.06)              # 水泥抹顶
        top = H + 0.06
    elif k == 1:
        box(mb, "cement", -2.0, -0.23, H, 2.0, 0.23, H + 0.1)
        box(mb, "brick_grey", -2.0, -0.19, 0.3, 2.0, 0.19, 0.55)          # 墙脚露出的砖
        top = H + 0.1
    else:
        box(mb, "brick_grey", -2.0, -0.21, H - 0.1, 2.0, 0.21, H)
        coping(mb, -2.0, 2.0, H)
        top = H + 0.28
    return mb, {"footprint": [4.0, 0.62], "height": round(top, 2), "params": {"wall": key, "height": H}}
