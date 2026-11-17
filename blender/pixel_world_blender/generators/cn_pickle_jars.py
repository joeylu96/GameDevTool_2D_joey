"""一组腌菜坛子：深褐色釉面的陶坛，大肚子、收口，盖着木盖或倒扣一只碗，靠墙摆成一排或一堆。
变体 0 三只（大中小），1 两只大坛，2 四只挤成一堆。原点在这组坛子的中心地面。"""
import random

from ..builder import MeshBuilder

NAME = "腌菜坛"
CATEGORY = "props"
DESC = "Blender 生成的腌菜坛：几只深褐釉面的大肚陶坛，盖着木盖，摆在屋檐下。"
VARY = "坛子的数量、大小和摆法随变体变化。"
TAGS = ["cn_village", "yard"]
VARIANTS = 3


def jar(mb, x, y, r, h, lid="timber"):
    mb.frustum("glaze", x, y, 0.0, h * 0.12, r * 0.55, r * 0.72, 12, bottom=False, top=False)
    mb.frustum("glaze", x, y, h * 0.12, h * 0.5, r * 0.72, r, 12, top=False)
    mb.frustum("glaze", x, y, h * 0.5, h * 0.82, r, r * 0.7, 12, top=False)
    mb.frustum("glaze", x, y, h * 0.82, h * 0.92, r * 0.7, r * 0.52, 12, top=False)
    mb.frustum("glaze", x, y, h * 0.92, h, r * 0.52, r * 0.6, 12)
    if lid == "bowl":
        mb.frustum("paint_white", x, y, h, h + r * 0.3, r * 0.62, r * 0.25, 12)
    else:
        mb.frustum(lid, x, y, h, h + 0.04, r * 0.66, r * 0.64, 12)
        mb.frustum(lid, x, y, h + 0.04, h + 0.09, 0.035, 0.03, 6)


def build(seed, **over):
    k = (seed - 1) % 3
    r = random.Random(seed * 53 + 1)
    mb = MeshBuilder()
    if k == 0:
        spec = [(-0.55, 0.0, 0.33, 0.85, "timber"), (0.1, 0.03, 0.26, 0.66, "timber"), (0.6, -0.02, 0.19, 0.48, "bowl")]
        fp = [1.7, 0.75]
    elif k == 1:
        spec = [(-0.38, 0.0, 0.34, 0.9, "timber"), (0.38, 0.0, 0.32, 0.82, "bowl")]
        fp = [1.5, 0.75]
    else:
        spec = [(-0.36, 0.2, 0.3, 0.78, "timber"), (0.3, 0.22, 0.27, 0.7, "timber"), (-0.05, -0.28, 0.22, 0.55, "bowl"),
                (0.48, -0.25, 0.17, 0.42, "timber")]
        fp = [1.45, 1.3]
    top = 0.0
    for x, y, rr, h, lid in spec:
        jar(mb, x + r.uniform(-0.03, 0.03), y, rr, h, lid)
        top = max(top, h + 0.1)
    return mb, {"footprint": fp, "height": round(top, 2), "params": {"count": len(spec)}}
