"""中世纪帆船（参考 res/中世纪海边小镇.jpg 码头边的大帆船）。
约定：**水线在 z = 0**（船底在水下，原点 = 水线面的中心），**船头朝 -Y**（导出后 Godot +Z）。
变体 0：大型克拉克帆船，长约 18 米、三根桅杆，前后船楼，帆半收；变体 1：中型柯克船，长约 12 米、单桅、方帆张开；
变体 2：小渔船，长约 5 米，一根短桅、收起的帆和两支桨。
船壳用一段段横截面放样（龙骨 → 船底 → 水线 → 船舷），深色船壳 + 一道浅色舷墙木条。"""
import math

import numpy as np

from ..builder import MeshBuilder
from ._medieval import box

NAME = "中世纪帆船"
CATEGORY = "landmarks"
DESC = "Blender 生成的中世纪帆船：圆鼓鼓的木船壳、前后船楼、桅杆横桁和米色帆，停在码头栈桥边。"
VARY = "变体 0 三桅大帆船（约 18 米）、1 单桅柯克船（约 12 米）、2 小渔船（约 5 米）。"
TAGS = ["medieval", "shore"]
VARIANTS = 3


def _hull(mb, L, B, free, draft, n=14, sheer=0.9, stern_w=0.55):
    """放样船壳。返回每个站位的 (y, 半宽, 船舷高)"""
    st = []
    for i in range(n + 1):
        t = i / n                       # 0 = 船头，1 = 船尾
        y = -L * 0.5 + L * t
        w = math.sin(math.pi * min(1.0, t * 1.25) ** 0.75 * 0.5) if t < 0.8 else 1.0 - (1.0 - stern_w) * ((t - 0.8) / 0.2) ** 1.6
        w = max(0.04, w) * B * 0.5
        zd = free + sheer * (abs(t - 0.45) / 0.55) ** 2.0
        zk = -draft * (0.35 + 0.65 * math.sin(math.pi * min(1.0, 0.1 + t * 0.95)))
        st.append((y, w, zd, zk))
    for i in range(n):
        a, b = st[i], st[i + 1]
        for sx in (-1, 1):
            def sec(s):
                y, w, zd, zk = s
                return [(0.0, y, zk), (sx * w * 0.72, y, zk * 0.45), (sx * w * 0.97, y, 0.0), (sx * w, y, zd * 0.62), (sx * w * 0.98, y, zd)]
            pa, pb = sec(a), sec(b)
            for j in range(4):
                key = "hull" if j < 3 else "boards"
                mb.face(key, [pa[j], pb[j], pb[j + 1], pa[j + 1]], (sx, 0, 0.2 if j else -1))
            # 舷墙内侧 + 舷顶木条
            mb.face("hull", [(sx * a[1] * 0.9, a[0], a[2]), (sx * b[1] * 0.9, b[0], b[2]),
                             (sx * b[1] * 0.9, b[0], b[2] - 0.55), (sx * a[1] * 0.9, a[0], a[2] - 0.55)], (-sx, 0, 0))
            mb.face("timber", [(sx * a[1] * 0.98, a[0], a[2]), (sx * b[1] * 0.98, b[0], b[2]),
                               (sx * b[1] * 0.9, b[0], b[2]), (sx * a[1] * 0.9, a[0], a[2])], (0, 0, 1))
        # 甲板
        mb.face("deck", [(-a[1] * 0.9, a[0], a[2] - 0.55), (a[1] * 0.9, a[0], a[2] - 0.55),
                         (b[1] * 0.9, b[0], b[2] - 0.55), (-b[1] * 0.9, b[0], b[2] - 0.55)], (0, 0, 1))
    # 船尾板
    y, w, zd, zk = st[-1]
    mb.face("hull", [(-w * 0.98, y, zd), (w * 0.98, y, zd), (w * 0.97, y, 0.0), (w * 0.72, y, zk * 0.45), (0.0, y, zk),
                     (-w * 0.72, y, zk * 0.45), (-w * 0.97, y, 0.0)], (0, 1, 0))
    # 船头柱
    y0, _, zd0, zk0 = st[0]
    mb.tube("timber", (0, y0 + 0.05, zk0), (0, y0 - 0.25, zd0 + 0.45), 0.09, 0.07, 8)
    return st


def _deck_z(st, y):
    for a, b in zip(st[:-1], st[1:]):
        if a[0] <= y <= b[0]:
            t = (y - a[0]) / (b[0] - a[0])
            return a[2] + (b[2] - a[2]) * t - 0.55, a[1] + (b[1] - a[1]) * t
    return st[-1][2] - 0.55, st[-1][1]


def _mast(mb, st, y, h, yard_w, sail="furled", r=0.13, flag="cloth_red", yards=1, small=False):
    zd, _ = _deck_z(st, y)
    top = zd + h
    mb.tube("timber", (0, y, zd - 0.3), (0, y, top), r, r * 0.6, 10)
    for q in range(yards):
        zy = zd + h * (0.78 - 0.33 * q)
        yw = yard_w * (1.0 - 0.2 * q)
        mb.tube("timber", (-yw * 0.5, y - 0.12, zy), (yw * 0.5, y - 0.12, zy), 0.035 if small else 0.07, 0.035 if small else 0.07, 8)
        if sail == "furled":   # 收起的帆：捆在横桁下面的一卷
            fr = 0.1 if small else 0.2
            mb.tube("sail", (-yw * 0.46, y - 0.14, zy - fr), (yw * 0.46, y - 0.14, zy - fr), fr, fr, 10)
        else:                  # 张开一半 / 全开的帆：向船头鼓起的三条帆布
            drop = h * (0.42 if sail == "set" else 0.22)
            rows = 4
            for i in range(rows):
                t0, t1 = i / rows, (i + 1) / rows
                def pt(x, t):
                    bulge = math.sin(math.pi * t) * 0.55 * (1 - (2 * x / yw) ** 2 * 0.6)
                    return (x * (1 - 0.06 * t), y - 0.14 - bulge, zy - 0.08 - drop * t)
                cols = 6
                for j in range(cols):
                    x0 = -yw * 0.47 + yw * 0.94 * j / cols
                    x1 = -yw * 0.47 + yw * 0.94 * (j + 1) / cols
                    quad = [pt(x0, t0), pt(x1, t0), pt(x1, t1), pt(x0, t1)]
                    mb.face("sail", quad, (0, -1, 0))
                    mb.face("sail", [(p[0], p[1] + 0.02, p[2]) for p in quad][::-1], (0, 1, 0))
    # 桅盘 + 小旗
    if small:
        return top
    mb.frustum("timber", 0.0, y, zd + h * 0.86, zd + h * 0.86 + 0.35, 0.28, 0.4, 10, 0.0, top=False, bottom=True)
    for dy, n in ((0.0, (0, -1, 0)), (0.012, (0, 1, 0))):
        mb.face(flag, [(0.03, y + dy, top + 0.02), (0.03, y + dy, top - 0.42), (0.9, y + dy, top - 0.2)], n)
    return top


def build(seed, **over):
    k = (seed - 1) % 3
    mb = MeshBuilder()
    if k == 0:
        L, B, free, draft = 18.0, 5.2, 2.0, 1.6
        st = _hull(mb, L, B, free, draft, n=16, sheer=1.5)
        # 船尾楼（两层）和船头楼
        zs, ws = _deck_z(st, L * 0.5 - 2.6)
        box(mb, "boards", -ws * 0.92, L * 0.5 - 5.2, zs, ws * 0.92, L * 0.5 - 0.15, zs + 1.9)
        box(mb, "deck", -ws * 0.98, L * 0.5 - 5.4, zs + 1.9, ws * 0.98, L * 0.5 + 0.1, zs + 2.02)
        box(mb, "boards", -ws * 0.8, L * 0.5 - 2.9, zs + 2.02, ws * 0.8, L * 0.5 - 0.1, zs + 3.4)
        box(mb, "deck", -ws * 0.86, L * 0.5 - 3.05, zs + 3.4, ws * 0.86, L * 0.5 + 0.15, zs + 3.5)
        for x in (-ws * 0.5, 0.0, ws * 0.5):   # 船尾窗
            mb.face("glass_lead", [(x - 0.3, L * 0.5 - 0.09, zs + 2.4), (x + 0.3, L * 0.5 - 0.09, zs + 2.4),
                                   (x + 0.3, L * 0.5 - 0.09, zs + 3.1), (x - 0.3, L * 0.5 - 0.09, zs + 3.1)], (0, 1, 0))
        for yy in (L * 0.5 - 5.4, L * 0.5 - 3.05):   # 栏杆
            zz = zs + (2.02 if yy < L * 0.5 - 4 else 3.5)
            box(mb, "timber", -ws * 0.9, yy, zz + 0.55, ws * 0.9, yy + 0.08, zz + 0.65)
            for x in np.linspace(-ws * 0.85, ws * 0.85, 7):
                box(mb, "timber", x - 0.04, yy, zz, x + 0.04, yy + 0.08, zz + 0.55)
        zb, wb = _deck_z(st, -L * 0.5 + 2.2)
        box(mb, "boards", -wb * 0.9, -L * 0.5 + 0.9, zb, wb * 0.9, -L * 0.5 + 3.6, zb + 1.3)
        box(mb, "deck", -wb, -L * 0.5 + 0.6, zb + 1.3, wb, -L * 0.5 + 3.8, zb + 1.42)
        mb.tube("timber", (0, -L * 0.5 + 1.0, zb + 1.3), (0, -L * 0.5 - 2.6, zb + 2.6), 0.11, 0.06, 8)  # 船首斜桅
        top = _mast(mb, st, -0.6, 13.5, 6.4, sail="half", r=0.17, yards=2)
        _mast(mb, st, -L * 0.5 + 3.2, 9.5 + 1.3, 4.6, sail="furled", flag="cloth_gold")
        _mast(mb, st, L * 0.5 - 3.6, 7.5 + 2.0, 3.6, sail="furled", flag="cloth_blue")
        box(mb, "crate", -0.9, 1.6, _deck_z(st, 2.0)[0], 0.0, 2.5, _deck_z(st, 2.0)[0] + 0.7)
        mb.frustum("barrel", 0.8, 2.2, _deck_z(st, 2.2)[0], _deck_z(st, 2.2)[0] + 0.85, 0.32, 0.3, 12, 0.0, top=True)
    elif k == 1:
        L, B, free, draft = 12.0, 4.0, 1.5, 1.2
        st = _hull(mb, L, B, free, draft, n=14, sheer=1.0)
        zs, ws = _deck_z(st, L * 0.5 - 1.6)
        box(mb, "boards", -ws * 0.92, L * 0.5 - 3.2, zs, ws * 0.92, L * 0.5 - 0.12, zs + 1.5)
        box(mb, "deck", -ws, L * 0.5 - 3.4, zs + 1.5, ws, L * 0.5 + 0.1, zs + 1.6)
        box(mb, "timber", -ws * 0.92, L * 0.5 - 3.4, zs + 2.1, ws * 0.92, L * 0.5 - 3.32, zs + 2.2)
        for x in np.linspace(-ws * 0.85, ws * 0.85, 5):
            box(mb, "timber", x - 0.04, L * 0.5 - 3.4, zs + 1.6, x + 0.04, L * 0.5 - 3.32, zs + 2.1)
        top = _mast(mb, st, -0.8, 10.5, 5.6, sail="set", r=0.15)
        mb.frustum("barrel", -0.7, 1.4, _deck_z(st, 1.4)[0], _deck_z(st, 1.4)[0] + 0.8, 0.3, 0.28, 12, 0.0, top=True)
    else:
        L, B, free, draft = 5.2, 1.8, 0.55, 0.35
        st = _hull(mb, L, B, free, draft, n=10, sheer=0.25, stern_w=0.6)
        for y in (-0.9, 0.7):   # 横座板
            zd, w = _deck_z(st, y)
            box(mb, "boards", -w * 0.9, y - 0.14, zd + 0.3, w * 0.9, y + 0.14, zd + 0.36)
        top = _mast(mb, st, -0.3, 3.4, 1.9, sail="furled", r=0.06, small=True)
        for sx in (-1, 1):      # 桨
            mb.tube("timber", (sx * 0.5, 0.9, 0.5), (sx * 1.9, -0.6, 0.12), 0.035, 0.035, 6)
            box(mb, "boards", sx * 1.85 - 0.12, -0.9, 0.08, sx * 1.85 + 0.12, -0.5, 0.12)
    # 舵
    box(mb, "timber", -0.07, L * 0.5 - 0.02, -draft * 0.8, 0.07, L * 0.5 + (0.45 if k < 2 else 0.2), free * 0.6)
    return mb, {"footprint": [round(B + (0.4 if k < 2 else 2.2), 2), round(L + (3.2 if k == 0 else 0.6), 2)], "height": round(top, 2),
                "params": {"length": L, "beam": B, "waterline_z": 0.0, "bow": "-Y (Godot +Z)", "draft": draft}}
