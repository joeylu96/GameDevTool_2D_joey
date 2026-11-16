"""二八大杠自行车：黑色车架（上管水平的「大杠」）、28 寸大轮子、车把、车座、后货架、链罩、撑脚撑着停放。
变体 1 后货架上捆着一个麻袋、车把上挂一只布包。车头朝 -Y（导出后 Godot +Z），原点在两轮之间地面，车轮在 YZ 平面。"""
import math

from ..builder import MeshBuilder
from ._medieval import box

NAME = "二八自行车"
CATEGORY = "props"
DESC = "Blender 生成的二八大杠自行车：黑色车架、28 寸大轮、后货架和链罩，撑着脚撑停在院子里或墙边。"
VARY = "变体 0 空车，1 后货架捆着麻袋、车把挂着布包。"
TAGS = ["cn_village", "yard", "roadside"]
VARIANTS = 2

R = 0.35      # 车轮半径（28 寸）
WB = 1.15     # 轴距


def _wheel(mb, y):
    """车轮：轮胎一圈（16 段粗管）+ 轮毂 + 四根粗辐条"""
    n = 16
    pts = [(0.0, y + math.cos(2 * math.pi * i / n) * R, R + math.sin(2 * math.pi * i / n) * R) for i in range(n)]
    for i in range(n):
        mb.tube("tyre", pts[i], pts[(i + 1) % n], 0.028, 0.028, 4, math.pi / 4)
    mb.tube("steel", (-0.05, y, R), (0.05, y, R), 0.05, 0.05, 6)
    for i in range(3):
        a = math.pi * i / 3 + 0.3
        mb.tube("steel", (0.0, y - math.cos(a) * (R - 0.03), R - math.sin(a) * (R - 0.03)),
                (0.0, y + math.cos(a) * (R - 0.03), R + math.sin(a) * (R - 0.03)), 0.015, 0.015, 4)


def build(seed, **over):
    k = (seed - 1) % 2
    mb = MeshBuilder()
    yf, yr = -WB * 0.5, WB * 0.5
    _wheel(mb, yf)
    _wheel(mb, yr)
    frame = "paint_black"
    bb = (0.0, 0.05, 0.3)                   # 中轴
    seat_top = (0.0, 0.2, 0.95)             # 座管顶
    head_top = (0.0, yf + 0.22, 0.98)       # 车头管顶
    head_bot = (0.0, yf + 0.18, 0.78)
    r = 0.022
    mb.tube(frame, seat_top, head_top, r, r, 6)          # 大杠
    mb.tube(frame, bb, head_bot, r, r, 6)                # 下管
    mb.tube(frame, bb, seat_top, r, r, 6)                # 座管
    mb.tube(frame, bb, (0.0, yr, R), r * 0.8, r * 0.8, 6)       # 后下叉
    mb.tube(frame, seat_top, (0.0, yr, R), r * 0.8, r * 0.8, 6)  # 后上叉
    mb.tube(frame, head_bot, head_top, r * 1.2, r * 1.2, 6)       # 车头管
    mb.tube(frame, head_bot, (0.0, yf, R), r, r, 6)                # 前叉
    # 车把：立管 + 横把 + 两个黑色把套
    hb = (0.0, yf + 0.25, 1.1)
    mb.tube("steel", head_top, hb, 0.018, 0.018, 6)
    mb.tube("steel", (-0.28, yf + 0.3, 1.1), (0.28, yf + 0.3, 1.1), 0.016, 0.016, 6)
    for sx in (-1, 1):
        mb.tube("tyre", (sx * 0.2, yf + 0.3, 1.1), (sx * 0.3, yf + 0.33, 1.1), 0.022, 0.022, 6)
    # 车座、后货架、链罩、挡泥板、撑脚
    box(mb, "paint_black", -0.08, seat_top[1] - 0.05, 0.98, 0.08, seat_top[1] + 0.2, 1.04)
    mb.tube("steel", seat_top, (0.0, seat_top[1], 0.98), 0.016, 0.016, 6)
    box(mb, "steel", -0.13, yr - 0.32, 0.8, 0.13, yr + 0.08, 0.83)
    for i in range(3):
        x = -0.1 + i * 0.1
        box(mb, "steel", x - 0.016, yr - 0.32, 0.83, x + 0.016, yr + 0.08, 0.86)
    for sx in (-1, 1):
        mb.tube("steel", (sx * 0.1, yr - 0.3, 0.8), (sx * 0.05, yr, R), 0.015, 0.015, 4)
    box(mb, frame, 0.06, bb[1] - 0.05, 0.25, 0.09, yr - 0.05, 0.42)       # 链罩
    mb.tube("steel", (0.0, bb[1], 0.3), (0.12, bb[1] + 0.05, 0.3), 0.06, 0.06, 8)  # 牙盘
    mb.tube("steel", (0.04, yr - 0.05, 0.3), (-0.25, yr - 0.15, 0.0), 0.018, 0.018, 4)  # 撑脚
    # 前车灯 + 车铃
    mb.tube("steel", (0.0, yf + 0.18, 0.88), (0.0, yf + 0.08, 0.88), 0.045, 0.05, 8)
    mb.frustum("brass", 0.15, yf + 0.3, 1.12, 1.16, 0.035, 0.03, 8)
    height = 1.2
    if k == 1:
        mb.tube("cloth_gold", (-0.2, yr - 0.15, 0.97), (0.2, yr - 0.15, 0.97), 0.13, 0.13, 8)  # 麻袋
        box(mb, "cloth_blue", -0.1, yf + 0.25, 0.82, 0.1, yf + 0.36, 1.08)                    # 布包
        height = 1.25
    return mb, {"footprint": [0.7, 1.95], "height": height, "params": {"load": k == 1}}
