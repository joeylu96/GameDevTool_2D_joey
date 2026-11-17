"""一小片玉米（2×2 米一丛，成片铺开就是玉米地）：约 2 米高的玉米秆，每根四五片向两边弯下去的长叶子，顶上一撮天花穗，
有的秆上结着玉米棒。面数很省（场景里要铺几百丛）：秆是三棱柱、叶子和穗是双面三角形，贴整片的竖向渐变（blade_corn）。
变体 0 青玉米（没熟，全绿）、1 结棒的（带黄色玉米棒和穗）、2 稀一些矮一些的。原点在这一丛的中心地面。plant = True。"""
import math
import random

import numpy as np

from ..builder import MeshBuilder

NAME = "玉米丛"
CATEGORY = "plants"
DESC = "Blender 生成的玉米丛：两米高的玉米秆，长叶子向两边弯下去，顶上一撮穗子，成片铺开就是玉米地。"
VARY = "变体 0 青玉米、1 结棒的、2 稀矮的；每丛玉米秆的位置、高度、叶子方向不同。"
TAGS = ["cn_village", "plains"]
VARIANTS = 3


def _tri2(mb, key, a, b, tip):
    """双面三角形；尖端拿到渐变的浅色端"""
    a, b, tip = (np.asarray(p, dtype=float) for p in (a, b, tip))
    n = np.cross(b - a, tip - a)
    n = n / max(np.linalg.norm(n), 1e-9) * 0.003
    mb.face(key, [a + n, b + n, tip + n])
    mb.face(key, [b - n, a - n, tip - n])   # 背面偏开几毫米：完全重合的两面在合并顶点时会被删掉一面


def build(seed, **over):
    k = (seed - 1) % 3
    r = random.Random(seed * 401 + 17)
    mb = MeshBuilder()
    n_side = 3 if k == 2 else 4
    stalks = []
    for i in range(n_side):
        for j in range(3):
            x = -0.75 + 1.5 * i / (n_side - 1) + r.uniform(-0.12, 0.12)
            y = -0.66 + 0.66 * j + r.uniform(-0.12, 0.12)
            stalks.append((x, y))
    top = 0.0
    for (x, y) in stalks:
        h = r.uniform(1.75, 2.15) * (0.85 if k == 2 else 1.0)
        yaw = r.random() * math.tau
        # 秆：三棱柱（6 个三角形，不封口），整片渐变
        ring0 = [np.array([x + math.cos(yaw + math.tau * q / 3) * 0.028, y + math.sin(yaw + math.tau * q / 3) * 0.028, 0.0]) for q in range(3)]
        ring1 = [p * np.array([1, 1, 0]) + np.array([0, 0, h]) for p in ring0]
        for q in range(3):
            q2 = (q + 1) % 3
            mb.face("blade_corn", [ring0[q], ring0[q2], ring1[q2], ring1[q]])  # 逆时针一圈，法线朝外；不给 outward，保证顶端是渐变的浅色端
        # 叶子：左右交替，从秆上斜着伸出去再垂下来
        n_leaf = 5 if k != 2 else 4
        for li in range(n_leaf):
            z = h * (0.22 + 0.62 * li / (n_leaf - 1))
            a = yaw + (math.pi if li % 2 else 0.0) + r.uniform(-0.5, 0.5)
            ln = r.uniform(0.5, 0.75)
            d = np.array([math.cos(a), math.sin(a), 0.0])
            b0 = np.array([x, y, z])
            b1 = np.array([x, y, z + 0.22])
            tip = b0 + d * ln + np.array([0.0, 0.0, r.uniform(-0.12, 0.2)])
            _tri2(mb, "blade_corn", b0, b1, tip)
        # 天花穗
        if k != 0 or r.random() < 0.5:
            s = np.array([math.cos(yaw), math.sin(yaw), 0.0]) * 0.07
            _tri2(mb, "blade_wheat_ripe", np.array([x, y, h - 0.05]) - s, np.array([x, y, h - 0.05]) + s, np.array([x, y, h + 0.28]))
        top = max(top, h + 0.28)
    if k == 1:  # 玉米棒：几根秆的腰上斜挂一个三棱锥
        for (x, y) in stalks[::3]:
            a = r.random() * math.tau
            z = r.uniform(0.85, 1.15)
            base = np.array([x + math.cos(a) * 0.04, y + math.sin(a) * 0.04, z])
            tip = base + np.array([math.cos(a) * 0.12, math.sin(a) * 0.12, 0.3])
            ring = [base + np.array([math.cos(a + math.tau * q / 3) * 0.05, math.sin(a + math.tau * q / 3) * 0.05, 0.0]) for q in range(3)]
            for q in range(3):
                mb.face("fruit_yellow", [ring[q], ring[(q + 1) % 3], tip])
    return mb, {"footprint": [2.0, 2.0], "height": round(top, 2), "plant": True, "params": {"stalks": len(stalks)}}
