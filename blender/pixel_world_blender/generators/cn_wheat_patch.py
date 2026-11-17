"""一小片麦子（2×2 米一丛，成片铺开就是麦田）：密密的一簇簇麦子，约 0.8 米高，根部深、麦穗尖浅，随风起伏。
面数很省（场景里要铺几百丛）：每簇是一个三棱锥（3 个三角形，底面不封），7×7 簇挨在一起看不到地面，整片竖向渐变。
变体 0 青麦（绿）、1 熟麦（金黄）、2 半黄（青黄相间，矮一点）。原点在这一丛的中心地面。plant = True。"""
import math
import random

import numpy as np

from ..builder import MeshBuilder

NAME = "麦丛"
CATEGORY = "plants"
DESC = "Blender 生成的麦丛：密密的一簇簇麦子，根部深、穗尖浅，成片铺开就是随风起伏的麦田。"
VARY = "变体 0 青麦、1 金黄的熟麦、2 半青半黄；每簇的高矮和倾斜不同。"
TAGS = ["cn_village", "plains"]
VARIANTS = 3

N = 7


def build(seed, **over):
    k = (seed - 1) % 3
    r = random.Random(seed * 503 + 29)
    mb = MeshBuilder()
    step = 2.0 / N
    top = 0.0
    lean_a = r.random() * math.tau   # 整丛朝一个方向微微倒伏
    for i in range(N):
        for j in range(N):
            x = -1.0 + step * (i + 0.5) + r.uniform(-0.07, 0.07)
            y = -1.0 + step * (j + 0.5) + r.uniform(-0.07, 0.07)
            h = r.uniform(0.72, 0.9) * (0.85 if k == 2 else 1.0)
            rad = step * 0.8
            yaw = r.random() * math.tau
            key = ["blade_wheat", "blade_wheat_ripe", "blade_wheat_ripe" if (i + j) % 2 else "blade_wheat"][k]
            base = [np.array([x + math.cos(yaw + math.tau * q / 3) * rad, y + math.sin(yaw + math.tau * q / 3) * rad, 0.0]) for q in range(3)]
            la = lean_a + r.uniform(-0.6, 0.6)
            tip = np.array([x + math.cos(la) * h * 0.18, y + math.sin(la) * h * 0.18, h])
            for q in range(3):
                q2 = (q + 1) % 3
                mb.face(key, [base[q], base[q2], tip])  # 逆时针一圈，法线朝外；尖端是渐变的浅色端
            top = max(top, h)
    return mb, {"footprint": [2.0, 2.0], "height": round(top, 2), "plant": True, "params": {"tufts": N * N}}
