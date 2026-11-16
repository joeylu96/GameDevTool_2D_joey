"""城门：中间是方形门楼（圆拱门洞 + 向里打开的两扇包铁木门 + 顶上垛口 + 门洞上方挂两面旗），两侧各一座圆塔。
约定：总长 12 米 = 两段城墙模块，沿 X 从 -6 到 +6，两端接城墙模块（墙厚 1.6 米、走道 4.2 米，和 town_wall 一致）；
**外侧（城外）朝 -Y**（导出后 Godot +Z）；门洞宽 3.2 米（x ∈ [-1.6, 1.6]）、高 4.2 米，门洞贯穿 y ∈ [-1.7, 1.7]，
门扇向城里打开（伸到 y ≈ 2.1）。原点在门洞中心地面。"""
import math

from ..builder import MeshBuilder
from ._medieval import Wall, box, crenellations, round_tower

NAME = "城门"
CATEGORY = "landmarks"
DESC = "Blender 生成的中世纪城门：方形门楼带圆拱门洞和向里打开的包铁木门，两侧圆塔，顶上垛口，门洞上方挂着旗帜。"
VARY = "塔顶（青石板尖顶 / 红瓦尖顶 / 平顶垛口）和旗帜颜色随变体变化。"
TAGS = ["town", "medieval"]
VARIANTS = 3

GW = 1.6       # 门洞半宽
SPRING = 2.6   # 拱脚高度（拱顶 = SPRING + GW = 4.2）
HX = 2.4       # 门楼半宽
HY = 1.7       # 门楼半深
H = 7.6        # 门楼墙顶
WALK = 4.2


def _arch_pts(n=12):
    return [(math.cos(math.pi * i / n) * GW, SPRING + math.sin(math.pi * i / n) * GW) for i in range(n + 1)]


def build(seed, **over):
    k = seed - 1
    roof = ["slate", "roof_red", "battlement"][k % 3]
    banner = ["cloth_red", "cloth_blue", "cloth_green"][k % 3]
    mb = MeshBuilder()
    st = "castle_stone"
    arc = _arch_pts()
    # 两侧的城墙短段（塔后面，把塔和下一段城墙接上）
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 3.6, sx * 6.0))
        box(mb, "cobble_wall", x0, -0.8 - 0.25, 0.0, x1, 0.9, 0.8)
        box(mb, st, x0, -0.8, 0.8, x1, 0.8, WALK + 0.35)
        box(mb, st, x0, -0.8, WALK + 0.35, x1, -0.35, WALK + 0.55)
    # 门楼前后两面（带拱洞的凹多边形，从凸角开始写顶点）
    for sy in (-1, 1):
        y = sy * HY
        pts = [(-HX, H), (-HX, 0.0), (-GW, 0.0), (-GW, SPRING)]
        pts += [(x, z) for x, z in arc[::-1][1:-1]]
        pts += [(GW, SPRING), (GW, 0.0), (HX, 0.0), (HX, H)]
        mb.face(st, [(x, y, z) for x, z in pts], (0, sy, 0))
        # 拱圈石（凸出）
        for (xa, za), (xb, zb) in zip(arc[:-1], arc[1:]):
            n = Wall((0.0, y, 0.0), (1, 0, 0), (0, sy, 0))
            n.beam(mb, "cobble_wall", xa * 1.12, (za - SPRING) * 1.12 + SPRING, xb * 1.12, (zb - SPRING) * 1.12 + SPRING, 0.32, 0.1)
        for sx in (-1, 1):
            box(mb, "cobble_wall", sx * GW * 1.12 - 0.16, y - (0.1 if sy < 0 else 0.0), 0.0, sx * GW * 1.12 + 0.16,
                y + (0.1 if sy > 0 else 0.0), SPRING)
    # 两侧外墙、顶面
    for sx in (-1, 1):
        x = sx * HX
        mb.face(st, [(x, -HY, 0.0), (x, HY, 0.0), (x, HY, H), (x, -HY, H)], (sx, 0, 0))
    mb.face("cobble_wall", [(-HX, -HY, H), (HX, -HY, H), (HX, HY, H), (-HX, HY, H)], (0, 0, 1))
    # 门洞内壁 + 拱顶
    for sx in (-1, 1):
        x = sx * GW
        mb.face(st, [(x, -HY, 0.0), (x, HY, 0.0), (x, HY, SPRING), (x, -HY, SPRING)], (-sx, 0, 0))
    for (xa, za), (xb, zb) in zip(arc[:-1], arc[1:]):
        mid = ((xa + xb) * 0.5, 0.0, SPRING - (za + zb) * 0.5)
        mb.face(st, [(xa, -HY, za), (xb, -HY, zb), (xb, HY, zb), (xa, HY, za)], mid)
    mb.face("cobble_wall", [(-GW, -HY - 0.4, 0.02), (GW, -HY - 0.4, 0.02), (GW, HY + 0.4, 0.02), (-GW, HY + 0.4, 0.02)], (0, 0, 1))
    # 门扇（向城里打开，贴着门洞内壁）
    for sx in (-1, 1):
        x = sx * (GW - 0.08)
        y0, y1 = 0.5, 0.5 + GW
        box(mb, "door_wood", x - 0.06, y0, 0.05, x + 0.06, y1, 3.6)
        for zz in (0.6, 1.8, 3.0):
            box(mb, "iron", x - sx * 0.08 - 0.02, y0 + 0.05, zz - 0.06, x - sx * 0.08 + 0.02, y1 - 0.05, zz + 0.06)
        for yy in (y0 + 0.4, y0 + 0.8, y0 + 1.2):
            box(mb, "door_wood", x - sx * 0.07 - 0.015, yy - 0.02, 0.1, x - sx * 0.07 + 0.015, yy + 0.02, 3.5)
    # 门洞上方：吊闸槽（深色）+ 两面旗
    box(mb, "coal", -GW - 0.05, -HY + 0.25, SPRING + GW - 0.2, GW + 0.05, -HY + 0.4, SPRING + GW + 0.05)
    front = Wall((-HX, -HY, 0.0), (1, 0, 0), (0, -1, 0))
    for s in (HX - 1.3, HX + 1.3):
        front.box(mb, "iron", s - 0.5, H - 1.0, s + 0.5, H - 0.94, 0.0, 0.25)
        front.poly(mb, banner, [(s - 0.42, H - 0.98), (s + 0.42, H - 0.98), (s + 0.42, H - 3.0), (s, H - 2.7), (s - 0.42, H - 3.0)], 0.2)
        front.poly(mb, "cloth_gold", [(s - 0.12, H - 1.6), (s, H - 1.4), (s + 0.12, H - 1.6), (s, H - 1.8)], 0.215)
    # 门楼垛口（前后两排）+ 檐口石条
    for y0, y1 in ((-HY - 0.05, -HY + 0.4), (HY - 0.4, HY + 0.05)):
        crenellations(mb, st, -HX, HX, y0, y1, H, h=0.85, merlon=0.8, gap=0.55, start=-HX + 0.1)
    box(mb, "cobble_wall", -HX - 0.15, -HY - 0.15, H - 0.3, HX + 0.15, HY + 0.15, H - 0.1)
    # 门楼正面一扇小窗
    front.quad(mb, "coal", HX - 0.12, 5.4, HX + 0.12, 6.4, 0.012)
    # 两侧圆塔
    tip = 0.0
    for sx in (-1, 1):
        tip = round_tower(mb, sx * 4.0, 0.0, 2.0, 8.6, roof=roof, door_back=True)
    info = {"footprint": [12.0, round(HY * 2 + 0.9, 2)], "height": round(tip, 2),
            "params": {"length": 12.0, "opening": GW * 2, "opening_h": SPRING + GW, "outside": "-Y"}}
    return mb, info
