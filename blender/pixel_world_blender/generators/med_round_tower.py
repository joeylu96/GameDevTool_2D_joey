"""圆塔楼（参考 res/中世纪海边小镇.jpg 里一座座红尖顶圆塔）：米白石砌的高圆塔，斜面勒脚、几道石腰线、一圈圈圆拱窗，
靠近塔顶挑出一圈拱廊观景层，上面是高高的红瓦圆锥尖顶和小旗；最高的变体在观景层上面再收一节小塔身（两段式）。
塔身 16 边形，正面（-Y，导出后 Godot +Z）底部一扇圆拱木门；原点在塔中心地面。"""
import math

from ..builder import MeshBuilder
from ._medieval import Wall, arcade_ring, cone_roof, door_m, window_m

NAME = "红顶圆塔楼"
CATEGORY = "landmarks"
DESC = "Blender 生成的中世纪圆塔楼：米白石砌高塔、石腰线、一圈圈圆拱窗，塔顶挑出拱廊观景层，红瓦圆锥高尖顶上飘着小旗。"
VARY = "塔高 14~24 米、半径 3~3.8 米、窗的圈数、尖顶高度随变体变化；变体 3 是两段式（观景层上再收一节小塔）。"
TAGS = ["town", "medieval", "plaza"]
VARIANTS = 4
SIDES = 16
ROT = math.pi / SIDES  # 顶点错开半格，让一个面正对 -Y


def _wall(cx, cy, r, i, z0):
    a = 2 * math.pi * i / SIDES
    n = (math.cos(a), math.sin(a), 0.0)
    u = (-n[1], n[0], 0.0)
    fw = 2 * r * math.sin(math.pi / SIDES)
    apo = r * math.cos(math.pi / SIDES)
    c0 = (cx + n[0] * apo - u[0] * fw * 0.5, cy + n[1] * apo - u[1] * fw * 0.5, z0)
    return Wall(c0, u, n), fw


def _drum(mb, r, z0, z1, wall="castle_stone", rows=(), every=2, phase=0):
    mb.frustum(wall, 0.0, 0.0, z0, z1, r, r * 0.97, SIDES, ROT, top=False)
    for zz in rows:
        rz = r * (1 - 0.03 * (zz - z0) / max(z1 - z0, 0.1))
        mb.frustum("cobble_wall", 0.0, 0.0, zz - 0.5, zz - 0.32, rz + 0.07, rz + 0.07, SIDES, ROT, top=True, bottom=True)
        for i in range(phase, SIDES, every):
            w, fw = _wall(0.0, 0.0, rz, i, zz)
            window_m(mb, w, fw * 0.5, 0.0, min(0.38, fw * 0.34), 1.6, shutters="", frame="cobble_wall", arched=True)


def build(seed, **over):
    k = (seed - 1) % 4
    r = [3.0, 3.4, 3.2, 3.8][k]
    h = [8.0, 10.5, 9.5, 11.0][k]
    mb = MeshBuilder()
    mb.frustum("cobble_wall", 0.0, 0.0, 0.0, 1.0, r + 0.35, r + 0.05, SIDES, ROT, top=False)
    rows = [z for z in (4.0, 7.0, 10.0) if z < h - 1.2]
    _drum(mb, r, 1.0, h, rows=rows, every=2, phase=k % 2)
    front_i = SIDES * 3 // 4  # 朝 -Y 的面
    w, fw = _wall(0.0, 0.0, r * 0.995, front_i, 0.0)
    door_m(mb, w, fw * 0.5, 0.15, min(1.1, fw * 0.85), 2.4, mat="door_wood", frame="cobble_wall", arched=True)
    # 观景层：托座挑出 → 一圈拱廊 → 檐口
    rb = r + 0.55
    mb.frustum("cobble_wall", 0.0, 0.0, h, h + 0.6, r * 0.97, rb, SIDES, ROT, top=False, bottom=True)
    bh = 2.6
    mb.frustum("castle_stone", 0.0, 0.0, h + 0.6, h + 0.6 + bh, rb, rb, SIDES, ROT, top=False)
    arcade_ring(mb, 0.0, 0.0, rb, h + 1.1, bh - 0.9, SIDES, key="glass_lead" if k % 2 else "coal", rot=ROT)
    zt = h + 0.6 + bh
    mb.frustum("cobble_wall", 0.0, 0.0, zt, zt + 0.25, rb + 0.12, rb + 0.2, SIDES, ROT, top=True, bottom=True)
    zt += 0.25
    if k == 3:  # 两段式：再收一节小塔身
        r2 = r * 0.62
        mb.frustum("tile_red", 0.0, 0.0, zt, zt + 0.9, rb + 0.25, r2 + 0.1, SIDES, ROT, top=False)
        _drum(mb, r2, zt + 0.9, zt + 4.4, rows=[zt + 2.2], every=2)
        mb.frustum("cobble_wall", 0.0, 0.0, zt + 4.4, zt + 4.65, r2, r2 + 0.3, SIDES, ROT, top=True, bottom=True)
        top = cone_roof(mb, 0.0, 0.0, zt + 4.65, r2 + 0.45, 5.0)
    else:
        top = cone_roof(mb, 0.0, 0.0, zt, rb + 0.4, [5.5, 6.5, 6.0][k])
    d = (rb + 0.5) * 2
    return mb, {"footprint": [round(d, 2), round(d, 2)], "height": round(top, 2),
                "params": {"radius": r, "width": round(d, 2), "depth": round(d, 2)}}
