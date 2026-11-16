"""中世纪小镇资产共用的部件：木构架（梁、柱、斜撑）、双坡屋顶、铅条窗、木板门、拱门 / 拱窗、城垛。
坐标（Blender）：Z 向上，正面朝 -Y（导出后 Godot +Z）。墙面用 Wall(c0, u, n) 描述：c0 = 墙面左下角，
u = 沿墙水平方向（从外面看向右），n = 外法线；墙面上的点用 (s, z) 表示（s 沿 u 的距离，z 为高度）。"""
import math

import numpy as np

UP = np.array([0.0, 0.0, 1.0])


def V(*a):
    return np.array(a if len(a) > 1 else a[0], dtype=float)


def box(mb, key, x0, y0, z0, x1, y1, z1, top=True, bottom=False):
    mb.box(key, (min(x0, x1), min(y0, y1), min(z0, z1)), (max(x0, x1), max(y0, y1), max(z0, z1)), top=top, bottom=bottom)


def prism(mb, key, base, a, b, n, depth):
    """任意四边形 base[0..3]（逆时针看向 n）沿 n 挤出 depth 的薄板（梁、斜撑、牌子）"""
    base = [V(p) for p in base]
    n = V(n)
    top = [p + n * depth for p in base]
    mb.face(key, top, n)
    for i in range(len(base)):
        j = (i + 1) % len(base)
        mid = (base[i] + base[j]) * 0.5 - sum(base) / len(base)
        mb.face(key, [base[i], base[j], top[j], top[i]], mid)


class Wall:
    def __init__(self, c0, u, n):
        self.c0, self.u, self.n = V(c0), V(u), V(n)

    def p(self, s, z, d=0.0):
        return self.c0 + self.u * s + UP * z + self.n * d

    def rect(self, key, s0, z0, s1, z1, d0=0.0, d1=0.06, top=True):
        """墙面上的方块（梁 / 柱 / 窗框）：s、z 范围，从墙面向外 d0..d1"""
        a, b = self.p(s0, z0, d0), self.p(s1, z1, d1)
        mb_box = (np.minimum(a, b), np.maximum(a, b))
        return mb_box

    def beam(self, mb, key, s0, z0, s1, z1, w=0.18, d=0.06):
        """两点之间的梁（可斜）：宽 w，凸出墙面 d"""
        p0, p1 = V(s0, z0), V(s1, z1)
        t = p1 - p0
        ln = np.linalg.norm(t)
        if ln < 1e-6:
            return
        t /= ln
        q = V(-t[1], t[0]) * w * 0.5
        pts = [p0 - q, p1 - q, p1 + q, p0 + q]
        base = [self.p(x, z, 0.004) for x, z in pts]
        e1, e2 = base[1] - base[0], base[3] - base[0]
        if np.dot(np.cross(e1, e2), self.n) < 0:
            base = base[::-1]
        prism(mb, key, base, None, None, self.n, d)

    def box(self, mb, key, s0, z0, s1, z1, d0=0.0, d1=0.06, top=True):
        a, b = self.p(s0, z0, d0), self.p(s1, z1, d1)
        mb.box(key, tuple(np.minimum(a, b)), tuple(np.maximum(a, b)), top=top)

    def quad(self, mb, key, s0, z0, s1, z1, d=0.01):
        mb.face(key, [self.p(s0, z0, d), self.p(s1, z0, d), self.p(s1, z1, d), self.p(s0, z1, d)], self.n)

    def poly(self, mb, key, pts, d=0.01):
        mb.face(key, [self.p(s, z, d) for s, z in pts], self.n)


def walls_box(mb, key, x0, y0, z0, x1, y1, z1):
    """四面墙（不封顶），返回四个 Wall：前（-Y）、右（+X）、后（+Y）、左（-X），每面从外面看 u 指向右"""
    box(mb, key, x0, y0, z0, x1, y1, z1, top=False)
    return {
        "front": Wall((x0, y0, z0), (1, 0, 0), (0, -1, 0)),
        "right": Wall((x1, y0, z0), (0, 1, 0), (1, 0, 0)),
        "back": Wall((x1, y1, z0), (-1, 0, 0), (0, 1, 0)),
        "left": Wall((x0, y1, z0), (0, -1, 0), (-1, 0, 0)),
    }


def timber_frame(mb, wall, length, h, skip=(), key="timber", post_every=1.3, braces=True, rng=None):
    """半木构墙面：上下横梁、角柱、等距立柱、腰梁、斜撑（避开 skip 里的 (s0, s1) 区间，那里是门窗）"""
    w = 0.18
    wall.beam(mb, key, 0, w * 0.5, length, w * 0.5, w, 0.07)
    wall.beam(mb, key, 0, h - w * 0.5, length, h - w * 0.5, w, 0.07)
    n = max(2, int(round(length / post_every)))
    xs = [length * i / n for i in range(n + 1)]
    xs[0], xs[-1] = w * 0.5, length - w * 0.5
    for x in xs:
        wall.beam(mb, key, x, w, x, h - w, 0.16 if 0 < xs.index(x) < n else w, 0.06)
    mid = h * 0.42
    for i in range(n):
        a, b = xs[i], xs[i + 1]
        blocked = any(not (b <= s0 or a >= s1) for s0, s1 in skip)
        if not blocked:
            wall.beam(mb, key, a, mid, b, mid, 0.14, 0.05)
            if braces:
                # 交替方向的斜撑：靠两端的格子朝外撑（像真实的木构架）
                if (i < n / 2) == (i % 2 == 0):
                    wall.beam(mb, key, a + 0.05, w, b - 0.05, mid - 0.05, 0.13, 0.05)
                else:
                    wall.beam(mb, key, a + 0.05, mid - 0.05, b - 0.05, w, 0.13, 0.05)
                if rng is not None and rng.random() < 0.5:
                    wall.beam(mb, key, a + 0.05, mid + 0.05, b - 0.05, h - w - 0.05, 0.12, 0.05)
                    wall.beam(mb, key, a + 0.05, h - w - 0.05, b - 0.05, mid + 0.05, 0.12, 0.05)
        else:
            # 门窗所在的格子：只画窗下的短腰梁
            pass
    return xs


def window_m(mb, wall, s, z, hw=0.38, h=0.95, shutters="door_wood", frame="timber", arched=False):
    """铅条窗：深色窗洞框（木或石）+ 铅条玻璃 + 窗台 + 可选木百叶窗。s = 窗中心沿墙位置，z = 窗底高度"""
    if arched:
        pts = [(s + hw, z), (s + hw, z + h - hw)]
        for i in range(1, 8):
            a = math.pi * i / 8
            pts.append((s + math.cos(a) * hw, z + h - hw + math.sin(a) * hw))
        pts += [(s - hw, z + h - hw), (s - hw, z)]
        wall.poly(mb, "glass_lead", pts, 0.012)
        # 石拱圈
        for i in range(8):
            a0, a1 = math.pi * i / 8, math.pi * (i + 1) / 8
            r = hw + 0.06
            wall.beam(mb, frame, s + math.cos(a0) * r, z + h - hw + math.sin(a0) * r,
                      s + math.cos(a1) * r, z + h - hw + math.sin(a1) * r, 0.14, 0.06)
        wall.beam(mb, frame, s - hw - 0.06, z, s - hw - 0.06, z + h - hw, 0.14, 0.06)
        wall.beam(mb, frame, s + hw + 0.06, z, s + hw + 0.06, z + h - hw, 0.14, 0.06)
    else:
        wall.quad(mb, "glass_lead", s - hw, z, s + hw, z + h, 0.012)
        f = 0.09
        wall.box(mb, frame, s - hw - f, z + h, s + hw + f, z + h + f, 0.0, 0.08)
        wall.box(mb, frame, s - hw - f, z - f, s - hw, z + h, 0.0, 0.07)
        wall.box(mb, frame, s + hw, z - f, s + hw + f, z + h, 0.0, 0.07)
        wall.box(mb, frame, s - hw, z + h * 0.5 - 0.025, s + hw, z + h * 0.5 + 0.025, 0.0, 0.04)
        if shutters:
            for side in (-1, 1):
                a0 = s + side * (hw + f + 0.02)
                a1 = s + side * (hw + f + 0.02 + hw)
                wall.box(mb, shutters, min(a0, a1), z - 0.02, max(a0, a1), z + h + 0.02, 0.02, 0.06)
                for zz in (z + h * 0.2, z + h * 0.8):
                    wall.box(mb, "iron", min(a0, a1) + 0.04, zz - 0.03, max(a0, a1) - 0.04, zz + 0.03, 0.06, 0.08)
    wall.box(mb, frame if frame != "timber" else "timber", s - hw - 0.14, z - 0.16, s + hw + 0.14, z - 0.04, 0.0, 0.16)


def door_m(mb, wall, s, z, w=1.1, h=2.15, mat="door_wood", frame="timber", arched=False, double=False):
    """木板门（竖板 + 两道铁合页 + 门环），平顶或圆拱顶；门框木或石"""
    hw = w * 0.5
    if arched:
        r = hw
        pts = [(s + hw, z), (s + hw, z + h - r)]
        for i in range(1, 10):
            a = math.pi * i / 10
            pts.append((s + math.cos(a) * r, z + h - r + math.sin(a) * r))
        pts += [(s - hw, z + h - r), (s - hw, z)]
        wall.poly(mb, mat, pts, 0.03)
        for i in range(10):
            a0, a1 = math.pi * i / 10, math.pi * (i + 1) / 10
            rr = r + 0.1
            wall.beam(mb, frame, s + math.cos(a0) * rr, z + h - r + math.sin(a0) * rr,
                      s + math.cos(a1) * rr, z + h - r + math.sin(a1) * rr, 0.22, 0.1)
        wall.beam(mb, frame, s - hw - 0.1, z, s - hw - 0.1, z + h - r, 0.22, 0.1)
        wall.beam(mb, frame, s + hw + 0.1, z, s + hw + 0.1, z + h - r, 0.22, 0.1)
        top = h - r
    else:
        wall.box(mb, mat, s - hw, z, s + hw, z + h, 0.0, 0.035)
        f = 0.14
        wall.box(mb, frame, s - hw - f, z, s - hw, z + h + f, 0.0, 0.1)
        wall.box(mb, frame, s + hw, z, s + hw + f, z + h + f, 0.0, 0.1)
        wall.box(mb, frame, s - hw - f - 0.06, z + h, s + hw + f + 0.06, z + h + f + 0.04, 0.0, 0.13)
        top = h
    # 竖板缝（浅凸条）+ 铁合页 + 门环
    nb = 4 if not double else 6
    for i in range(1, nb):
        x = s - hw + w * i / nb
        wall.box(mb, mat, x - 0.02, z + 0.04, x + 0.02, z + top - 0.04, 0.035, 0.05)
    for zz in (z + 0.35, z + top - 0.35):
        if double:
            wall.box(mb, "iron", s - hw + 0.05, zz - 0.04, s - 0.06, zz + 0.04, 0.05, 0.07)
            wall.box(mb, "iron", s + 0.06, zz - 0.04, s + hw - 0.05, zz + 0.04, 0.05, 0.07)
        else:
            wall.box(mb, "iron", s - hw + 0.05, zz - 0.04, s + hw * 0.55, zz + 0.04, 0.05, 0.07)
    if double:
        wall.box(mb, "timber", s - 0.03, z, s + 0.03, z + top, 0.035, 0.07)
    ring_s = s + hw * 0.62 if not double else s
    wall.box(mb, "iron", ring_s - 0.05, z + 1.0, ring_s + 0.05, z + 1.12, 0.05, 0.1)


def gable_roof(mb, key, a0, a1, b0, b1, z0, pitch_deg, axis="x", eave=0.45, gable=0.35, t=0.16,
               fascia="timber", thatch=False):
    """双坡屋顶：屋脊沿 axis（"x" 或 "y"），覆盖 a0..a1（沿屋脊）× b0..b1（横跨）的墙顶，墙顶高 z0。
    返回 (屋脊高度, 山墙三角形 [(端点 a, 三角形三个顶点(a,b,z) )])"""
    def M(a, b, z):
        return (a, b, z) if axis == "x" else (b, a, z)

    pitch = math.radians(pitch_deg)
    bc = (b0 + b1) * 0.5
    half = (b1 - b0) * 0.5
    ridge = z0 + half * math.tan(pitch)
    ze = z0 - eave * math.tan(pitch)
    ea0, ea1 = a0 - gable, a1 + gable
    if thatch:
        t = 0.38
    for s in (-1, 1):
        be = bc + s * (half + eave)
        tl, tr = V(M(ea0, bc, ridge)), V(M(ea1, bc, ridge))
        br, bl = V(M(ea1, be, ze)), V(M(ea0, be, ze))
        n_out = V(M(0, s * math.sin(pitch), math.cos(pitch)))
        mb.face(key, [tl, tr, br, bl], n_out)
        dt = V(0, 0, t)
        mb.face("roof_under", [p - dt for p in (tl, tr, br, bl)], -n_out)
        # 檐口边（厚度）
        mb.face(key if thatch else fascia, [bl, br, br - dt, bl - dt], V(M(0, s, 0)))
        for ea, sa in ((ea0, -1), (ea1, 1)):
            p, q = V(M(ea, bc, ridge)), V(M(ea, be, ze))
            mb.face(key if thatch else fascia, [p, q, q - dt, p - dt], V(M(sa, 0, 0)))
    if thatch:
        # 圆鼓的草脊
        p0, p1 = V(M(ea0 - 0.05, bc, ridge + 0.05)), V(M(ea1 + 0.05, bc, ridge + 0.05))
        mb.tube(key, p0, p1, 0.32, 0.32, 8, rot=math.pi / 8)
    else:
        lo, hi = V(M(ea0 - 0.03, bc - 0.14, ridge - 0.05)), V(M(ea1 + 0.03, bc + 0.14, ridge + 0.1))
        mb.box("roof_cap", tuple(np.minimum(lo, hi)), tuple(np.maximum(lo, hi)))
    gables = []
    for a, sa in ((a0, -1), (a1, 1)):
        tri = [V(M(a, b0, z0)), V(M(a, b1, z0)), V(M(a, bc, ridge))]
        gables.append((sa, tri))
    return ridge, gables


def gable_wall(mb, key, tri, n):
    mb.face(key, tri, n)


def crenellations(mb, key, x0, x1, y0, y1, z, h=0.95, merlon=0.9, gap=0.6, start=None):
    """城垛：沿 X 从 x0 到 x1 的一排垛口（y0..y1 是垛墙厚度）"""
    period = merlon + gap
    x = x0 + gap * 0.5 if start is None else start
    while x + merlon <= x1 + 1e-6:
        box(mb, key, x, y0, z, x + merlon, y1, z + h)
        x += period


def chimney(mb, x, y, z0, z1, s=0.36, key="cobble_wall"):
    box(mb, key, x - s, y - s, z0, x + s, y + s, z1)
    box(mb, "castle_stone", x - s - 0.07, y - s - 0.07, z1, x + s + 0.07, y + s + 0.07, z1 + 0.14)
    box(mb, "coal", x - s + 0.1, y - s + 0.1, z1 + 0.14, x + s - 0.1, y + s - 0.1, z1 + 0.16)


def recenter_y(mb, y_front, y_back):
    """整体沿 Y 平移，让外廓 [y_front, y_back] 的中点落在原点（场景按 footprint 居中摆放）；返回平移量"""
    dy = -(y_front + y_back) * 0.5
    mb.verts = [np.asarray(v, dtype=float) + np.array([0.0, dy, 0.0]) for v in mb.verts]
    return dy


def round_tower(mb, cx, cy, r, h, roof="slate", stone="castle_stone", sides=12, slits=True, door_back=True):
    """圆塔（12 边形）：斜面勒脚 + 略收分的塔身 + 腰线 + 箭窗 + 顶部挑出的檐口，再加圆锥尖顶或平顶垛口。
    roof：slate / roof_red = 圆锥尖顶；"battlement" = 平顶垛口。返回塔顶最高点"""
    rot = math.pi / sides
    mb.frustum("cobble_wall", cx, cy, 0.0, 0.9, r + 0.3, r, sides, rot, top=False)
    mb.frustum(stone, cx, cy, 0.9, h, r, r * 0.95, sides, rot, top=False)
    zz = h * 0.45
    mb.frustum("cobble_wall", cx, cy, zz, zz + 0.18, r + 0.06, r + 0.06, sides, rot, top=False, bottom=True)
    apo = math.cos(math.pi / sides)
    if slits:
        for i in range(0, sides, 3):
            a = 2 * math.pi * (i + 1) / sides  # 面的中心方向（顶点在 rot + 2πi/sides）
            n = V(math.cos(a), math.sin(a), 0.0)
            t = V(-n[1], n[0], 0.0)
            for z0 in (h * 0.25, h * 0.65):
                rz = r - (r - r * 0.95) * (z0 - 0.9) / (h - 0.9)
                c = V(cx, cy, 0.0) + n * (rz * apo + 0.015)
                pts = [c + t * 0.07 + UP * z0, c - t * 0.07 + UP * z0, c - t * 0.07 + UP * (z0 + 0.9), c + t * 0.07 + UP * (z0 + 0.9)]
                mb.face("coal", pts, n)
    if door_back:
        # 内侧（+Y）底部小拱门
        a = math.pi / 2
        yface = cy + r * apo * 0.995 + 0.03
        door_m(mb, Wall((cx + 0.55, yface, 0.9), (-1, 0, 0), (0, 1, 0)), 0.55, 0.0, 0.9, 1.9, frame="cobble_wall", arched=True)
    mb.frustum("cobble_wall", cx, cy, h, h + 0.35, r * 0.95, r + 0.25, sides, rot, top=False, bottom=True)
    if roof == "battlement":
        rr = r + 0.25
        mb.frustum(stone, cx, cy, h + 0.35, h + 0.9, rr, rr, sides, rot, top=False)
        mb.frustum("cobble_wall", cx, cy, h + 0.35, h + 0.36, rr - 0.02, rr - 0.02, sides, rot, top=True)
        for i in range(0, sides, 2):
            a0 = rot + 2 * math.pi * i / sides
            a1 = rot + 2 * math.pi * (i + 1) / sides
            c0 = V(cx, cy, 0.0)
            p0 = c0 + V(math.cos(a0), math.sin(a0), 0.0) * rr
            p1 = c0 + V(math.cos(a1), math.sin(a1), 0.0) * rr
            i0 = c0 + (p0 - c0) * (1 - 0.45 / rr)
            i1 = c0 + (p1 - c0) * (1 - 0.45 / rr)
            z0, z1 = h + 0.9, h + 1.75
            quad = [p0, p1, i1, i0]
            top = [q + UP * z1 for q in quad]
            bot = [q + UP * z0 for q in quad]
            mb.face(stone, top, (0, 0, 1))
            for a_, b_ in ((0, 1), (1, 2), (2, 3), (3, 0)):
                mid = (quad[a_] + quad[b_]) * 0.5 - c0
                if (a_, b_) == (2, 3):
                    mid = -mid
                if (a_, b_) in ((1, 2), (3, 0)):
                    e = quad[b_] - quad[a_]
                    mid = V(-e[1], e[0], 0.0) if (a_, b_) == (1, 2) else V(e[1], -e[0], 0.0)
                    mid = mid if np.dot(mid, (quad[a_] + quad[b_]) * 0.5 - (p0 + p1 + i0 + i1) / 4) > 0 else -mid
                mb.face(stone, [bot[a_], bot[b_], top[b_], top[a_]], mid)
        return h + 1.75
    rr = r + 0.45
    roof_h = r * 2.1
    mb.frustum(roof, cx, cy, h + 0.3, h + 0.3 + roof_h, rr, 0.0, sides, rot, top=False, bottom=True)
    tip = h + 0.3 + roof_h
    box(mb, "iron", cx - 0.04, cy - 0.04, tip - 0.1, cx + 0.04, cy + 0.04, tip + 0.9)
    mb.face("cloth_red", [V(cx + 0.04, cy, tip + 0.88), V(cx + 0.04, cy, tip + 0.5), V(cx + 0.75, cy, tip + 0.72)], (0, -1, 0))
    mb.face("cloth_red", [V(cx + 0.04, cy + 0.01, tip + 0.5), V(cx + 0.04, cy + 0.01, tip + 0.88), V(cx + 0.75, cy + 0.01, tip + 0.72)], (0, 1, 0))
    return tip + 0.9
