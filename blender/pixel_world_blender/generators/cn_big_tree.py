"""村里的大树（老槐树 / 大杨树那种遮荫的大阔叶树）：粗树干（根部外扩），分出四五根大枝，每根枝头几团叶子，
整体是一个圆圆的大树冠——下层深色、上层浅色，一层层叠上去。高 9~13 米，树冠直径 8~11 米。
变体 0 中等（约 9.5 米）、1 高大（约 12.5 米）、2 偏矮但很宽（约 10 米）。原点在树干根部。plant = True（叶子随风摆）。"""
import math
import random

from ..builder import MeshBuilder

NAME = "村口大树"
CATEGORY = "trees"
DESC = "Blender 生成的村口大树：粗壮的树干分出几根大枝，圆圆的大树冠一层层叠上去，树下一大片荫凉。"
VARY = "树高 9~13 米、树冠宽窄、大枝数量和方向随变体变化；放进场景时再随机朝向、比例、色调。"
TAGS = ["cn_village", "plains", "town"]
VARIANTS = 3


def build(seed, **over):
    k = (seed - 1) % 3
    r = random.Random(seed * 211 + 13)
    mb = MeshBuilder()
    H = [9.5, 12.5, 10.0][k]
    R = [4.2, 4.8, 5.4][k]            # 树冠半径
    th = H * 0.27                      # 分叉高度
    tr = [0.42, 0.52, 0.5][k]
    mb.frustum("trunk", 0, 0, 0.0, 0.5, tr * 1.7, tr * 1.1, 12, 0, top=False)
    mb.frustum("trunk", 0, 0, 0.5, th, tr * 1.1, tr * 0.85, 12, 0, top=False)
    nb = [4, 5, 5][k]
    a0 = r.random() * math.tau
    clusters = []
    top = (0.0, 0.0, th)
    ch = H - th                        # 树冠的总高度
    for i in range(nb):                # 下层：一圈大枝，每根枝头一团深色叶子
        a = a0 + math.tau * i / nb + r.uniform(-0.25, 0.25)
        ln = R * r.uniform(0.52, 0.62)
        zc = th + ch * r.uniform(0.2, 0.3)
        end = (math.cos(a) * ln, math.sin(a) * ln, zc)
        mid = (end[0] * 0.45, end[1] * 0.45, th + (zc - th) * 0.7)
        mb.tube("trunk", top, mid, tr * 0.62, tr * 0.42, 8, caps=False)
        mb.tube("trunk", mid, end, tr * 0.42, tr * 0.2, 8, caps=False)
        clusters.append((end[0], end[1], zc + 0.2, R * r.uniform(0.44, 0.52), "leaf_dark"))
    zt = th + ch * 0.45
    mb.tube("trunk", top, (0.0, 0.0, zt), tr * 0.75, tr * 0.3, 8, caps=False)
    for i in range(4):                 # 中层：一圈四团
        a = a0 + 0.5 + math.tau * i / 4
        clusters.append((math.cos(a) * R * 0.4, math.sin(a) * R * 0.4, th + ch * r.uniform(0.48, 0.55), R * r.uniform(0.46, 0.52),
                         "leaf_dark" if i % 2 else "leaf"))
    # 顶层：一大团 + 旁边两小团（浅色）
    clusters.append((0.0, 0.0, th + ch * 0.76, R * 0.5, "leaf"))
    for i in range(2):
        a = a0 + 1.3 + math.pi * i
        clusters.append((math.cos(a) * R * 0.3, math.sin(a) * R * 0.3, th + ch * 0.66, R * 0.34, "leaf"))
    height, reach = 0.0, 0.0
    for (x, y, z, cr, key) in clusters:
        mb.blob(key, x, y, z, cr, cr * 1.5, 12, r.random())
        height = max(height, z + cr * 0.75)
        reach = max(reach, math.hypot(x, y) + cr)
    return mb, {"footprint": [round(reach * 2, 2), round(reach * 2, 2)], "height": round(height, 2), "plant": True,
                "params": {"trunk_r": round(tr * 1.1, 2)}}
