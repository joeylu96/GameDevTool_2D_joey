"""草丛的共用造型（对照 Godot 端 PWGrass.build_tuft）：一丛细长的双面三角草叶，随机倾斜；
叶片贴图是整面铺满的竖向渐变（根部深、尖端浅，材质 blade / blade_dry 在 builder 的 _STRETCH 里）。"""
import math
import random

import numpy as np

from ..builder import MeshBuilder


def build_tuft(seed, kind):
    """kind：grass / tall / dry / flower。原点在草丛根部中心，大约 0.35 米宽"""
    r = random.Random(seed * 7001 + {"grass": 0, "tall": 100, "dry": 200, "flower": 300}[kind])
    mb = MeshBuilder()
    tall = kind == "tall"
    mat = "blade_dry" if kind == "dry" else "blade"
    n = r.randint(10, 14) if tall else r.randint(8, 12)
    top = 0.0
    for i in range(n):
        a = r.random() * math.tau
        off = np.array([math.cos(a), math.sin(a), 0.0]) * r.uniform(0.0, 0.16)
        yaw = r.random() * math.tau
        h = r.uniform(0.45, 0.85) if tall else r.uniform(0.24, 0.5)
        wdt = r.uniform(0.04, 0.065)
        lean = r.uniform(0.08, 0.4)
        side = np.array([math.cos(yaw), math.sin(yaw), 0.0])
        fwd = np.array([-math.sin(yaw), math.cos(yaw), 0.0])
        b0, b1 = off - side * wdt, off + side * wdt
        tip = off + fwd * (h * lean) + np.array([0.0, 0.0, h])
        # 双面：两个顶点顺序相反的三角形；不给 outward，保证尖端总拿到 UV v = 0（渐变的浅色端）
        mb.face(mat, [b0, b1, tip])
        mb.face(mat, [b1, b0, tip])
        top = max(top, h)
    if kind == "flower":
        heads = ["fruit_red", "fruit_yellow", "plaster_white", "fruit_yellow", "fruit_red"]
        col = heads[r.randint(0, len(heads) - 1)]
        for k in range(r.randint(2, 4)):
            a = r.random() * math.tau
            px, py = math.cos(a) * r.uniform(0.03, 0.12), math.sin(a) * r.uniform(0.03, 0.12)
            hh = r.uniform(0.28, 0.42)
            mb.tube("leaf_dark", (px, py, 0.0), (px, py, hh), 0.008, 0.008, 3, caps=False)
            mb.frustum(col, px, py, hh - 0.02, hh + 0.025, 0.045, 0.03, 5, a, top=True, bottom=True)
            mb.frustum("brass", px, py, hh + 0.025, hh + 0.035, 0.015, 0.0, 4, a, top=False)
            top = max(top, hh + 0.035)
    return mb, {"footprint": [0.45, 0.45], "height": top, "plant": True}
