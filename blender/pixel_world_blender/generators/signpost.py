"""路牌：一根木柱上钉 2~3 块箭头指示牌，朝向各不相同；柱顶一个小尖帽，柱脚压几块石头。"""
import math
import random

from ..builder import MeshBuilder

NAME = "路牌"
CATEGORY = "street"
DESC = "Blender 生成的路口指示牌：木柱上钉着几块朝向不同的箭头牌，柱脚压着石块。"
VARY = "指示牌数量、朝向、长度和颜色，柱子高度随种子变化。"


def _arrow(mb, z, ang, ln, key):
    """一块箭头牌：一头平一头尖的五边形板子（双面），中心钉在柱子上。"""
    h = 0.22
    t = 0.03
    c, s = math.cos(ang), math.sin(ang)

    def P(u, v, w):  # u 沿箭头方向，v 沿板厚，w 竖直
        return (c * u - s * v, s * u + c * v, z + w)

    tail = -0.18
    pts = [(tail, -h / 2), (ln - 0.16, -h / 2), (ln, 0.0), (ln - 0.16, h / 2), (tail, h / 2)]
    for side in (-1, 1):
        face = [P(u, side * t, w) for (u, w) in pts]
        mb.face(key, face if side > 0 else face[::-1], (-s * side, c * side, 0))
    # 板子的边（厚度）
    for i in range(len(pts)):
        (u0, w0), (u1, w1) = pts[i], pts[(i + 1) % len(pts)]
        du, dw = u1 - u0, w1 - w0  # 轮廓是逆时针的，(dw, -du) 指向板子外面
        mb.face("trim", [P(u0, -t, w0), P(u1, -t, w1), P(u1, t, w1), P(u0, t, w0)], (c * dw, s * dw, -du))


def build(seed, **over):
    r = random.Random(seed)
    mb = MeshBuilder()
    h = r.uniform(2.0, 2.4)
    mb.box("trunk", (-0.07, -0.07, 0.0), (0.07, 0.07, h))
    mb.frustum("roof_grey", 0, 0, h, h + 0.18, 0.12, 0.0, 4, math.pi / 4, top=False, bottom=True)
    n = r.randint(2, 3)
    used = []
    reach = 0.3
    for i in range(n):
        for _ in range(10):
            ang = r.uniform(0, math.tau)
            if all(abs((ang - u + math.pi) % math.tau - math.pi) > 0.6 for u in used):
                break
        used.append(ang)
        ln = r.uniform(0.6, 0.85)
        key = r.choice(["wall_wood", "wall_ochre", "wall_teal", "wall_red"])
        _arrow(mb, h - 0.35 - i * 0.32, ang, ln, key)
        reach = max(reach, ln)
    for k in range(r.randint(3, 5)):  # 柱脚的石块
        a = r.uniform(0, math.tau)
        d = r.uniform(0.15, 0.3)
        sz = r.uniform(0.08, 0.14)
        mb.frustum("stone", math.cos(a) * d, math.sin(a) * d, 0.0, sz, sz * 1.2, sz * 0.6, 5, r.random(), top=True)
    return mb, {"footprint": [reach * 2, reach * 2], "height": h + 0.2}
