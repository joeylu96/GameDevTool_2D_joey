"""院子里的竹桌椅：一张方竹桌（桌面一排竹条、四条竹腿、一圈横撑）配竹椅，桌上一把紫砂茶壶。
变体 0 两把椅子面对面，1 两把椅子摆成直角 + 两只茶杯，2 一把椅子 + 一只小竹凳。原点在桌子中心地面。"""
import math

from ..builder import MeshBuilder
from ._medieval import box

NAME = "竹桌椅"
CATEGORY = "props"
DESC = "Blender 生成的竹桌椅：方竹桌配两把竹椅，桌上一把茶壶，摆在农家院子里喝茶。"
VARY = "椅子的数量和摆法、有没有茶杯随变体变化。"
TAGS = ["cn_village", "yard"]
VARIANTS = 3


def _leg(mb, x, y, z0, z1, r=0.028):
    mb.tube("bamboo", (x, y, z0), (x, y, z1), r, r, 6)


def _table(mb, s=0.36, h=0.62):
    for sx in (-1, 1):
        for sy in (-1, 1):
            _leg(mb, sx * s * 0.86, sy * s * 0.86, 0.0, h, 0.03)
    for i in range(7):  # 桌面竹条
        y = -s + (i + 0.5) * 2 * s / 7
        box(mb, "bamboo", -s, y - s / 7 + 0.006, h, s, y + s / 7 - 0.006, h + 0.035)
    for z in (0.18, h - 0.08):
        for a in ((-1, -1, 1, -1), (1, -1, 1, 1), (1, 1, -1, 1), (-1, 1, -1, -1)):
            mb.tube("bamboo", (a[0] * s * 0.86, a[1] * s * 0.86, z), (a[2] * s * 0.86, a[3] * s * 0.86, z), 0.018, 0.018, 5)
    return h + 0.035


def _chair(mb, cx, cy, yaw, sw=0.21, sh=0.42, bh=0.92):
    """竹椅：座面朝 yaw 方向（弧度，0 = 朝 +X）"""
    c, s = math.cos(yaw), math.sin(yaw)

    def P(fx, sx, z):  # fx 向前，sx 向左
        return (cx + c * fx - s * sx, cy + s * fx + c * sx, z)

    for fx in (-1, 1):
        for sx in (-1, 1):
            top = bh if fx < 0 else sh
            mb.tube("bamboo", P(fx * sw, sx * sw, 0.0), P(fx * sw - (0.05 if fx < 0 else 0), sx * sw, top), 0.024, 0.022, 6)
    for i in range(5):  # 座面
        t = -sw + (i + 0.5) * 2 * sw / 5
        mb.tube("bamboo", P(t, -sw, sh), P(t, sw, sh), 0.03, 0.03, 6)
    for z in (sh + 0.2, sh + 0.34, bh - 0.04):  # 靠背横条
        mb.tube("bamboo", P(-sw - 0.035, -sw, z), P(-sw - 0.035, sw, z), 0.022, 0.022, 6)
    for sx in (-1, 1):  # 腿间横撑
        mb.tube("bamboo", P(-sw, sx * sw, 0.16), P(sw, sx * sw, 0.16), 0.015, 0.015, 5)


def _teapot(mb, x, y, z):
    mb.frustum("glaze", x, y, z, z + 0.06, 0.05, 0.075, 10, bottom=False)
    mb.frustum("glaze", x, y, z + 0.06, z + 0.12, 0.075, 0.04, 10)
    mb.frustum("glaze", x, y, z + 0.12, z + 0.145, 0.02, 0.012, 6)
    mb.tube("glaze", (x + 0.06, y, z + 0.06), (x + 0.13, y, z + 0.11), 0.016, 0.01, 5)       # 壶嘴
    mb.tube("glaze", (x - 0.07, y, z + 0.1), (x - 0.11, y, z + 0.05), 0.012, 0.012, 5)       # 壶把
    mb.tube("glaze", (x - 0.11, y, z + 0.05), (x - 0.06, y, z + 0.03), 0.012, 0.012, 5)


def build(seed, **over):
    k = (seed - 1) % 3
    mb = MeshBuilder()
    top = _table(mb)
    _teapot(mb, 0.05, -0.04, top)
    if k == 0:
        _chair(mb, -0.78, 0.0, 0.0)
        _chair(mb, 0.78, 0.0, math.pi)
        fp = [2.1, 0.9]
    elif k == 1:
        _chair(mb, -0.78, 0.05, 0.1)
        _chair(mb, 0.05, 0.78, -math.pi / 2 + 0.15)
        for cx, cy in ((-0.18, 0.1), (0.1, 0.2)):
            mb.frustum("paint_white", cx, cy, top, top + 0.05, 0.022, 0.03, 8, bottom=False)
        fp = [1.6, 1.6]
    else:
        _chair(mb, -0.8, 0.0, 0.0)
        for sx in (-1, 1):
            for sy in (-1, 1):
                _leg(mb, 0.75 + sx * 0.13, sy * 0.13, 0.0, 0.3, 0.022)
        box(mb, "bamboo", 0.58, -0.17, 0.3, 0.92, 0.17, 0.335)
        fp = [2.0, 0.9]
    return mb, {"footprint": fp, "height": 0.95, "params": {"chairs": 2 if k < 2 else 1}}
