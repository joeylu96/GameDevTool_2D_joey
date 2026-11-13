"""手推车：木板车斗（侧板分条）+ 两个带辐条的木轮 + 车轴 + 两根车把 + 一根支腿，
车斗里随机装干草、木箱或木桶。"""
import math
import random

from ..builder import MeshBuilder

NAME = "手推车"
CATEGORY = "props"
DESC = "Blender 生成的手推车：木车斗、辐条木轮、车把和支腿，车上随机装干草、木箱或木桶。"
VARY = "车斗长宽、轮子大小和辐条数、装载的货物随种子变化。"
TAGS = ["roadside", "yard", "plains", "town"]


def _wheel(mb, x, y, z, rad, spokes, r):
    """立在 XZ 平面的车轮（轴沿 Y）：轮圈用 16 段短管拼，中心轮毂 + 辐条。"""
    segs = 16
    for i in range(segs):
        a0 = math.tau * i / segs
        a1 = math.tau * (i + 1) / segs
        p0 = (x + math.cos(a0) * rad, y, z + math.sin(a0) * rad)
        p1 = (x + math.cos(a1) * rad, y, z + math.sin(a1) * rad)
        mb.tube("trunk", p0, p1, 0.045, 0.045, 4, math.pi / 4, caps=False)
    mb.tube("trunk", (x, y - 0.08, z), (x, y + 0.08, z), 0.09, 0.09, 8)
    off = r.random() * math.pi
    for k in range(spokes):
        a = off + math.pi * k / spokes  # 辐条穿过轮心，两头各一根
        d = (math.cos(a) * rad * 0.95, 0, math.sin(a) * rad * 0.95)
        mb.tube("trunk", (x - d[0], y, z - d[2]), (x + d[0], y, z + d[2]), 0.022, 0.022, 4, caps=False)


def build(seed, **over):
    r = random.Random(seed)
    mb = MeshBuilder()
    ln = r.uniform(1.3, 1.7)       # 车斗长（沿 X）
    wd = r.uniform(0.85, 1.05)     # 车斗宽（沿 Y）
    rad = r.uniform(0.38, 0.46)    # 轮半径
    z0 = rad + 0.08                # 车斗底面
    hl, hw = ln / 2, wd / 2
    # 车斗底板 + 四周分条侧板（两条板中间留缝）
    mb.box("wall_wood", (-hl, -hw, z0), (hl, hw, z0 + 0.06), bottom=True)
    for zz in (z0 + 0.06, z0 + 0.24):
        mb.box("wall_wood", (-hl, -hw, zz), (hl, -hw + 0.04, zz + 0.14))
        mb.box("wall_wood", (-hl, hw - 0.04, zz), (hl, hw, zz + 0.14))
        mb.box("wall_wood", (-hl, -hw, zz), (-hl + 0.04, hw, zz + 0.14))
        mb.box("wall_wood", (hl - 0.04, -hw, zz), (hl, hw, zz + 0.14))
    for sx in (-1, 0, 1):  # 侧板立柱
        for sy in (-1, 1):
            x = sx * (hl - 0.03)
            mb.box("trunk", (x - 0.035, sy * hw - 0.035, z0), (x + 0.035, sy * hw + 0.035, z0 + 0.42))
    # 车轴 + 轮子（在车斗两侧、略靠前）
    ax = -hl * 0.15
    mb.tube("metal", (ax, -hw - 0.12, rad), (ax, hw + 0.12, rad), 0.03, 0.03, 6)
    spokes = r.choice([3, 4])
    for sy in (-1, 1):
        _wheel(mb, ax, sy * (hw + 0.1), rad, rad, spokes, r)
    # 车把：从车斗后沿向后伸出、向下斜；支腿撑住地面
    for sy in (-1, 1):
        y = sy * (hw - 0.08)
        mb.tube("trunk", (hl - 0.1, y, z0 + 0.03), (hl + 0.75, y, z0 - 0.12), 0.035, 0.03, 6)
    mb.tube("trunk", (hl * 0.7, 0, z0), (hl * 0.7 + 0.08, 0, 0.0), 0.035, 0.035, 6)
    # 货物
    load = r.choice(["hay", "crates", "barrels", "empty"])
    if load == "hay":
        mb.box("hay", (-hl + 0.06, -hw + 0.06, z0 + 0.06), (hl - 0.06, hw - 0.06, z0 + 0.5), top=True)
        mb.blob("hay", r.uniform(-0.2, 0.2), 0, z0 + 0.55, min(hl, hw) * 0.8, 0.35, 8, r.random())
    elif load == "crates":
        for i in range(r.randint(2, 3)):
            s = r.uniform(0.3, 0.38)
            x = -hl + 0.25 + i * (ln - 0.5) / 2
            y = r.uniform(-hw + s / 2 + 0.06, hw - s / 2 - 0.06)
            mb.box("crate", (x - s / 2, y - s / 2, z0 + 0.06), (x + s / 2, y + s / 2, z0 + 0.06 + s))
    elif load == "barrels":
        for i in range(2):
            x = -hl * 0.45 + i * hl * 0.9
            mb.frustum("wall_wood", x, 0, z0 + 0.06, z0 + 0.36, 0.2, 0.23, 10, 0, top=False)
            mb.frustum("wall_wood", x, 0, z0 + 0.36, z0 + 0.66, 0.23, 0.2, 10, 0, top=True)
            for zz in (z0 + 0.14, z0 + 0.56):
                mb.frustum("metal", x, 0, zz, zz + 0.04, 0.225, 0.225, 10, 0, top=False)
    return mb, {"footprint": [ln + 0.9, wd + 0.4], "height": z0 + 0.9}
