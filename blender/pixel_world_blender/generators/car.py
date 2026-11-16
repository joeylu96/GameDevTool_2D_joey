"""小汽车：两厢掀背、三厢轿车、面包车三种车型，多种车漆颜色。车身是侧面轮廓挤出，车窗是贴在车身外的玻璃
（不发光），四个车轮、前后保险杠、车灯、后视镜。车头朝 -Y（导出后 Godot +Z），原点在车身中心地面，长约 4 米。"""
from ..builder import MeshBuilder
from ._medieval import box
from ._modern import extrude_profile, wheel

NAME = "小汽车"
CATEGORY = "props"
DESC = "Blender 生成的小汽车：两厢掀背、三厢轿车、面包车三种车型，多种车漆，停在路边和院子里。"
VARY = "车型（两厢 / 三厢 / 面包车）和车漆颜色（红 / 蓝 / 白 / 灰 / 黄 / 青）随变体变化。"
TAGS = ["town", "modern", "roadside"]
VARIANTS = 6

PAINTS = ["paint_red", "paint_blue", "paint_white", "paint_grey", "paint_yellow", "paint_teal"]

# 侧面轮廓（y 从车头 -L/2 到车尾 +L/2，z 向上），按车型；数值是车长 / 车高的比例
SHAPES = {
    "hatch": {"L": 3.9, "H": 1.48, "prof": [(0.0, 0.18), (0.0, 0.42), (0.04, 0.5), (0.27, 0.58), (0.4, 0.97), (0.85, 1.0),
                                            (0.97, 0.78), (1.0, 0.5), (1.0, 0.18)],
              "glass": [(0.42, 0.62), (0.84, 0.62), (0.95, 0.76)], "wb": (0.17, 0.82)},
    "sedan": {"L": 4.5, "H": 1.42, "prof": [(0.0, 0.18), (0.0, 0.42), (0.04, 0.5), (0.26, 0.57), (0.38, 0.96), (0.7, 0.98),
                                            (0.82, 0.62), (0.98, 0.58), (1.0, 0.45), (1.0, 0.18)],
              "glass": [(0.4, 0.6), (0.69, 0.6), (0.79, 0.62)], "wb": (0.17, 0.8)},
    "van": {"L": 4.4, "H": 1.9, "prof": [(0.0, 0.14), (0.0, 0.4), (0.05, 0.45), (0.13, 0.52), (0.26, 0.97), (0.98, 1.0),
                                          (1.0, 0.95), (1.0, 0.14)],
            "glass": [(0.27, 0.6), (0.97, 0.6), (0.97, 0.9)], "wb": (0.16, 0.84)},
}


def build(seed, **over):
    k = seed - 1
    kind = ["hatch", "sedan", "van", "hatch", "sedan", "van"][k % 6]
    paint = PAINTS[k % len(PAINTS)]
    sh = SHAPES[kind]
    L, H = sh["L"], sh["H"]
    W = 1.75 if kind != "van" else 1.85
    hw = W * 0.5
    mb = MeshBuilder()
    prof = [(-L * 0.5 + u * L, v * H) for u, v in sh["prof"]]
    extrude_profile(mb, paint, prof, -hw, hw)
    # 车窗：两侧各一条（沿轮廓的车顶段往里缩一点），前挡风、后窗
    g0, g1, g2 = sh["glass"]
    ye = -L * 0.5 + g1[0] * L
    zlo, zhi = g0[1] * H, (sh["prof"][4][1] if kind != "van" else 0.97) * H - 0.06
    # 侧窗前沿顺着 A 柱（挡风玻璃那条斜线）
    (y3, z3), (y4, z4) = prof[3], prof[4]
    yf = y3 + (y4 - y3) * (zlo - z3) / max(z4 - z3, 1e-6) + 0.1
    for sx in (-1, 1):
        x = sx * (hw + 0.006)
        roof_y0 = y4 + 0.1
        roof_y1 = -L * 0.5 + sh["prof"][5][0] * L - 0.05
        pts = [(x, yf, zlo), (x, ye, zlo), (x, min(ye, roof_y1), zhi), (x, roof_y0, zhi)]
        mb.face("glass_car", pts, (sx, 0, 0))
        # B 柱
        yb = (yf + ye) * 0.5
        box(mb, paint, x - 0.012, yb - 0.05, zlo, x + 0.012, yb + 0.05, zhi)
    # 前挡风：沿轮廓第 3→4 段，贴在外面一点
    (ya, za), (yb2, zb) = prof[3], prof[4]
    n = (0.0, -(zb - za), (yb2 - ya))
    mb.face("glass_car", [(-hw + 0.1, ya + 0.04, za + 0.04), (hw - 0.1, ya + 0.04, za + 0.04), (hw - 0.1, yb2 - 0.01, zb - 0.04),
                          (-hw + 0.1, yb2 - 0.01, zb - 0.04)], n)
    # 后窗
    i_rear = 5 if kind != "van" else 6
    (yc, zc), (yd, zd) = prof[i_rear], prof[i_rear + 1]
    if kind == "van":  # 面包车尾门是竖的：只有上半截是玻璃
        yc, yd, zd = yc + 0.01, yd + 0.01, 0.6 * H
    n2 = (0.0, (zc - zd), -(yc - yd))
    if abs(n2[1]) + abs(n2[2]) < 1e-6:
        n2 = (0.0, 1.0, 0.0)
    mb.face("glass_car", [(-hw + 0.12, yc + 0.01, zc - 0.05), (hw - 0.12, yc + 0.01, zc - 0.05), (hw - 0.12, yd - 0.02, zd + 0.06),
                          (-hw + 0.12, yd - 0.02, zd + 0.06)], n2)
    # 车轮：轮拱处
    r = 0.33 if kind != "van" else 0.35
    for u in sh["wb"]:
        y = -L * 0.5 + u * L
        for sx in (-1, 1):
            wheel(mb, sx * (hw - 0.1), y, r, r, 0.22)
    # 保险杠、车灯、后视镜、底部阴影条
    yfr, yre = -L * 0.5, L * 0.5
    box(mb, "tyre", -hw + 0.02, yfr - 0.05, 0.2, hw - 0.02, yfr + 0.1, 0.38)
    box(mb, "tyre", -hw + 0.02, yre - 0.1, 0.2, hw - 0.02, yre + 0.05, 0.38)
    for sx in (-1, 1):
        box(mb, "brass", sx * (hw - 0.32) - 0.17, yfr - 0.015, 0.5 * H * 0.9, sx * (hw - 0.32) + 0.17, yfr + 0.02, 0.5 * H * 0.9 + 0.1)
        box(mb, "paint_red", sx * (hw - 0.25) - 0.13, yre - 0.02, 0.5 * H, sx * (hw - 0.25) + 0.13, yre + 0.015, 0.5 * H + 0.12)
        box(mb, paint, sx * (hw + 0.12) - 0.07, yf + 0.05, zlo + 0.02, sx * (hw + 0.12) + 0.07, yf + 0.15, zlo + 0.14)
    box(mb, "tyre", -hw + 0.1, -L * 0.5 + 0.3, 0.1, hw - 0.1, L * 0.5 - 0.3, 0.2)
    return mb, {"footprint": [round(W + 0.3, 2), round(L, 2)], "height": round(H, 2),
                "params": {"kind": kind, "paint": paint, "length": L}}
