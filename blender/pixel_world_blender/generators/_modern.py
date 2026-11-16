"""现代风格 / 中国乡村资产共用的部件：侧面轮廓挤出（汽车车身）、带金属框的大玻璃、管子、平顶女儿墙、小青瓦双坡顶。
坐标（Blender）：Z 向上，正面朝 -Y（导出后 Godot +Z），原点在地面中心。"""
import math

import numpy as np

from ._medieval import V, Wall, box

UP = np.array([0.0, 0.0, 1.0])


def extrude_profile(mb, key, prof, x0, x1, side_key=None):
    """把 YZ 平面上的一圈轮廓（[(y, z), ...]，顺序不限）沿 X 从 x0 挤出到 x1：两个侧面 + 一圈侧边"""
    side_key = side_key or key
    pts0 = [V(x0, y, z) for y, z in prof]
    pts1 = [V(x1, y, z) for y, z in prof]
    mb.face(side_key, pts0, (-1, 0, 0))
    mb.face(side_key, pts1, (1, 0, 0))
    cy = sum(y for y, _ in prof) / len(prof)
    cz = sum(z for _, z in prof) / len(prof)
    for i in range(len(prof)):
        j = (i + 1) % len(prof)
        (y0, z0), (y1, z1) = prof[i], prof[j]
        n = V(0.0, z1 - z0, -(y1 - y0))
        mid = V(0.0, (y0 + y1) * 0.5 - cy, (z0 + z1) * 0.5 - cz)
        if np.dot(n, mid) < 0:
            n = -n
        mb.face(key, [pts0[i], pts0[j], pts1[j], pts1[i]], n)


def pane(mb, wall, s0, z0, s1, z1, glass="glass_modern", frame="metal", f=0.06, d=0.07, mullions=0, transom=None):
    """墙面上一块带金属框的大玻璃：s0..s1 × z0..z1；mullions = 竖向分隔条数，transom = 横向分隔高度"""
    wall.quad(mb, glass, s0, z0, s1, z1, 0.015)
    wall.box(mb, frame, s0 - f, z0 - f, s1 + f, z0, 0.0, d)
    wall.box(mb, frame, s0 - f, z1, s1 + f, z1 + f, 0.0, d)
    wall.box(mb, frame, s0 - f, z0, s0, z1, 0.0, d)
    wall.box(mb, frame, s1, z0, s1 + f, z1, 0.0, d)
    for i in range(1, mullions + 1):
        s = s0 + (s1 - s0) * i / (mullions + 1)
        wall.box(mb, frame, s - f * 0.4, z0, s + f * 0.4, z1, 0.0, d * 0.8)
    if transom is not None:
        wall.box(mb, frame, s0, transom - f * 0.4, s1, transom + f * 0.4, 0.0, d * 0.8)


def sill(mb, wall, s0, s1, z, key="concrete"):
    wall.box(mb, key, s0 - 0.08, z - 0.06, s1 + 0.08, z, 0.0, 0.12)


def parapet(mb, key, x0, y0, x1, y1, z, h=0.55, t=0.2, cap="concrete"):
    """平屋顶一圈女儿墙 + 压顶"""
    for a in ((x0, y0, x1, y0 + t), (x0, y1 - t, x1, y1), (x0, y0, x0 + t, y1), (x1 - t, y0, x1, y1)):
        box(mb, key, a[0], a[1], z, a[2], a[3], z + h)
        box(mb, cap, a[0] - 0.03, a[1] - 0.03, z + h, a[2] + 0.03, a[3] + 0.03, z + h + 0.06)


def downpipe(mb, x, y, z_top, key="metal"):
    mb.tube(key, (x, y, 0.05), (x, y, z_top), 0.045, 0.045, 6)
    box(mb, key, x - 0.08, y - 0.08, z_top - 0.05, x + 0.08, y + 0.08, z_top + 0.04)


def cn_roof(mb, x0, x1, y0, y1, z0, pitch_deg=26.0, eave=0.45, gable=0.3, key="tile_cn", t=0.12, ridge_ends=True):
    """中式小青瓦双坡顶：屋脊沿 X；返回 (屋脊高度, 两个山墙三角形)。屋脊是一道砌起来的脊，两端微微翘起"""
    pitch = math.radians(pitch_deg)
    yc = (y0 + y1) * 0.5
    half = (y1 - y0) * 0.5
    ridge = z0 + half * math.tan(pitch)
    ze = z0 - eave * math.tan(pitch)
    ea0, ea1 = x0 - gable, x1 + gable
    for s in (-1, 1):
        ye = yc + s * (half + eave)
        tl, tr = V(ea0, yc, ridge), V(ea1, yc, ridge)
        br, bl = V(ea1, ye, ze), V(ea0, ye, ze)
        n_out = V(0, s * math.sin(pitch), math.cos(pitch))
        mb.face(key, [tl, tr, br, bl], n_out)
        dt = V(0, 0, t)
        mb.face("roof_under", [p - dt for p in (tl, tr, br, bl)], -n_out)
        mb.face(key, [bl, br, br - dt, bl - dt], V(0, s, 0))
        for ea, sa in ((ea0, -1), (ea1, 1)):
            p, q = V(ea, yc, ridge), V(ea, ye, ze)
            mb.face(key, [p, q, q - dt, p - dt], V(sa, 0, 0))
        # 檐口一排瓦当（略厚的边）
        box(mb, "roof_cap", ea0, min(ye, ye - s * 0.06), ze - 0.06, ea1, max(ye, ye - s * 0.06), ze + 0.02)
    # 屋脊：砌起来的一道脊 + 两端翘起的脊头
    box(mb, "roof_cap", ea0 + 0.05, yc - 0.16, ridge - 0.06, ea1 - 0.05, yc + 0.16, ridge + 0.2)
    box(mb, "brick_grey", ea0 + 0.1, yc - 0.1, ridge + 0.2, ea1 - 0.1, yc + 0.1, ridge + 0.26)
    if ridge_ends:
        for xe, sx in ((ea0 + 0.05, 1), (ea1 - 0.05, -1)):
            mb.tube("roof_cap", (xe + sx * 0.35, yc, ridge + 0.12), (xe - sx * 0.05, yc, ridge + 0.42), 0.1, 0.06, 4, math.pi / 4)
    gables = []
    for a, sa in ((x0, -1), (x1, 1)):
        gables.append((sa, [V(a, y0, z0), V(a, y1, z0), V(a, yc, ridge)]))
    return ridge, gables


def wheel(mb, cx, cy, cz, r, w, tyre="tyre", hub="steel", sides=12):
    """车轮（轴沿 X）：轮胎 + 轮毂盖"""
    mb.tube(tyre, (cx - w * 0.5, cy, cz), (cx + w * 0.5, cy, cz), r, r, sides, math.pi / sides)
    for sx in (-1, 1):
        x = cx + sx * (w * 0.5 + 0.005)
        mb.tube(hub, (x - sx * 0.005, cy, cz), (x + sx * 0.012, cy, cz), r * 0.55, r * 0.5, sides, math.pi / sides)


__all__ = ["extrude_profile", "pane", "sill", "parapet", "downpipe", "cn_roof", "wheel", "Wall", "box", "V", "UP"]
