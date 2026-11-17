"""农家院门：总长 4 米（x -2..+2，和 cn_courtyard_wall 模块一样长，两端直接接院墙），门洞 3 米宽（x ±1.5）；
外侧朝 -Y（导出后 Godot +Z），原点在门洞中心地面，门扇都朝院里（+Y）开。变体序号和 cn_courtyard_wall 一一对应：
0 红砖门垛（水泥帽）+ 两扇朝里敞开的木板门，1 水泥抹面门垛 + 两扇朝里敞开的铁栅门，
2 干垒石墙留的豁口 + 竹篱笆门（一扇关着、一扇朝里半开），3 老式门楼（砖垛 + 木过梁 + 小青瓦门头，木板大门敞开，贴红对联）。"""
import math

from ..builder import MeshBuilder
from ._medieval import box
from ._modern import cn_roof
from .cn_courtyard_wall import drystone_run

NAME = "农家院门"
CATEGORY = "street"
DESC = "Blender 生成的农家院门：红砖门垛配木板门、水泥门垛配铁栅门、石墙豁口配竹篱笆门、带小青瓦门头的老式门楼四种，门都朝院里开。"
VARY = "变体 0 红砖垛木门、1 水泥垛铁栅门、2 石墙竹门、3 小青瓦门楼。"
TAGS = ["cn_village", "yard"]
VARIANTS = 4


def _leaf_open(mb, sx, key, h, bars=False):
    """一扇朝院里（+Y）开到底的门，贴着门垛内侧：x = sx*1.5，沿 +Y 伸 1.45 米"""
    x = sx * 1.5
    x0, x1 = (x - 0.06, x) if sx > 0 else (x, x + 0.06)
    if not bars:
        box(mb, key, x0, 0.26, 0.06, x1, 1.71, h)
        for z in (0.45, h - 0.5):
            box(mb, "iron", x0 - 0.015, 0.4, z - 0.04, x1 + 0.015, 1.6, z + 0.04)
    else:
        for z in (0.12, h * 0.55, h - 0.06):
            box(mb, key, x0, 0.26, z - 0.035, x1, 1.71, z + 0.035)
        for i in range(8):
            y = 0.3 + i * 0.195
            mb.tube(key, ((x0 + x1) * 0.5, y, 0.1), ((x0 + x1) * 0.5, y, h + (0.1 if i % 2 == 0 else 0.0)), 0.022, 0.022, 6)


def _bamboo_leaf(mb, hinge, d, ln=1.45, h=1.25):
    """竹篱笆门扇：从 hinge 沿方向 d（单位向量，XY 平面）伸 ln 米——一排竖竹竿 + 两道横竹"""
    hx, hy = hinge
    n = 11
    for i in range(n):
        t = 0.05 + (ln - 0.1) * i / (n - 1)
        x, y = hx + d[0] * t, hy + d[1] * t
        mb.tube("bamboo", (x, y, 0.06), (x, y, h + 0.12 * math.sin(i * 1.7) ** 2), 0.03, 0.026, 6)
    for z in (0.3, h - 0.25):
        mb.tube("bamboo", (hx, hy, z), (hx + d[0] * ln, hy + d[1] * ln, z), 0.032, 0.032, 6)


def build(seed, **over):
    k = (seed - 1) % 4
    mb = MeshBuilder()
    if k == 2:  # 干垒石墙豁口 + 竹门
        for sx in (-1, 1):
            a, b = (sx * 1.5, sx * 2.0)
            drystone_run(mb, min(a, b), max(a, b), 1.2, seed * 31 + (sx > 0), t=0.24)
            mb.tube("bamboo", (sx * 1.46, 0.0, 0.0), (sx * 1.46, 0.0, 1.45), 0.05, 0.045, 8)  # 门柱
        box(mb, "stone", -1.5, -0.2, 0.0, 1.5, 0.2, 0.06)
        _bamboo_leaf(mb, (-1.44, 0.0), (1.0, 0.0))                       # 左扇关着
        a = math.radians(55)
        _bamboo_leaf(mb, (1.44, 0.0), (-math.cos(a), math.sin(a)))       # 右扇朝里半开
        return mb, {"footprint": [4.0, 1.6], "height": 1.5, "params": {"opening": 3.0, "length": 4.0, "wall": "drystone"}}
    if k in (0, 1):
        key = ["brick_red_cn", "render_cn"][k]
        H = 2.15
        for sx in (-1, 1):
            x0, x1 = sorted((sx * 1.5, sx * 2.0))
            box(mb, "stone" if k == 0 else "cement", x0 - 0.03, -0.28, 0.0, x1 + 0.03, 0.28, 0.3)
            box(mb, key, x0, -0.25, 0.3, x1, 0.25, H)
            box(mb, "cement", x0 - 0.05, -0.3, H, x1 + 0.05, 0.3, H + 0.1)
            mb.frustum("cement", (x0 + x1) * 0.5, 0.0, H + 0.1, H + 0.28, 0.2, 0.06, 4, math.pi / 4)  # 垛帽
            if k == 0:
                box(mb, "red_paper", sx * 1.75 - 0.13, -0.265, 0.7, sx * 1.75 + 0.13, -0.25, 1.9)
            _leaf_open(mb, sx, "door_wood" if k == 0 else "iron", 1.85, bars=(k == 1))
        box(mb, "cement" if k == 1 else "stone", -1.5, -0.2, 0.0, 1.5, 0.2, 0.06)
        return mb, {"footprint": [4.2, 2.0], "height": round(H + 0.28, 2), "params": {"opening": 3.0, "length": 4.0, "wall": key}}
    # 3：老式门楼
    key, door = "brick_red_cn", "door_oldred"
    H = 2.6
    for sx in (-1, 1):
        x0, x1 = sx * 1.5, sx * 2.0
        box(mb, "stone", min(x0, x1), -0.3, 0.0, max(x0, x1), 0.3, 0.35)
        box(mb, key, min(x0, x1), -0.26, 0.35, max(x0, x1), 0.26, H + 0.55)
        xc = sx * 1.75
        box(mb, "red_paper", xc - 0.14, -0.275, 0.6, xc + 0.14, -0.26, 2.3)
        _leaf_open(mb, sx, door, H - 0.05)
    box(mb, "stone", -1.5, -0.2, 0.0, 1.5, 0.2, 0.12)
    box(mb, "wall_wood", -2.05, -0.3, H, 2.05, 0.3, H + 0.25)
    box(mb, "red_paper", -0.6, -0.315, H + 0.03, 0.6, -0.3, H + 0.22)
    box(mb, key, -2.0, -0.26, H + 0.25, 2.0, 0.26, H + 0.55)
    ridge, gables = cn_roof(mb, -2.0, 2.0, -0.3, 0.3, H + 0.55, 30.0, eave=0.45, gable=0.25, t=0.1)
    for sa, tri in gables:
        mb.face(key, tri, (sa, 0, 0))
    return mb, {"footprint": [4.6, 2.0], "height": round(ridge + 0.45, 2),
                "params": {"opening": 3.0, "length": 4.0, "wall": key}}
