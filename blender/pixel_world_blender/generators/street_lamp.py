"""铸铁路灯：石墩 + 八边形灯杆（中段一道装饰箍）+ 弯臂 + 四面玻璃灯笼 + 小尖顶。
灯笼玻璃用 bulb 材质，Godot 端换成统一材质后天黑自动发光。"""
import math
import random

from ..builder import MeshBuilder

NAME = "铸铁路灯"
CATEGORY = "street"
DESC = "Blender 生成的铸铁路灯：石墩、装饰灯杆、弯臂和四面玻璃灯笼，夜里灯笼自动发光。"
VARY = "单臂 / 双臂、灯杆高度、颜色（墨绿 / 铁灰）、灯笼大小随种子变化。"
TAGS = ["roadside", "town"]


def _lantern(mb, x, y, z, s, metal):
    """灯笼：底座 + 四面玻璃 + 四根角柱 + 四棱锥顶 + 顶钮。z 是灯笼底面高度。"""
    h = s * 1.5
    mb.frustum(metal, x, y, z - 0.05, z, s * 0.55, s * 0.75, 4, math.pi / 4, top=True, bottom=True)
    mb.frustum("bulb", x, y, z, z + h, s * 0.62, s * 0.72, 4, math.pi / 4, top=False)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        cx, cy = x + math.cos(a) * s * 0.68, y + math.sin(a) * s * 0.68
        mb.box(metal, (cx - 0.018, cy - 0.018, z), (cx + 0.018, cy + 0.018, z + h))
    mb.frustum(metal, x, y, z + h, z + h + s * 0.7, s * 0.9, 0.0, 4, math.pi / 4, top=False, bottom=True)
    mb.frustum(metal, x, y, z + h + s * 0.6, z + h + s * 0.85, 0.035, 0.02, 6, 0)


def build(seed, **over):
    r = random.Random(seed)
    mb = MeshBuilder()
    metal = r.choice(["metal_green", "metal"])
    pole_h = r.uniform(3.0, 3.6)
    s = r.uniform(0.2, 0.26)
    # 石墩 + 灯杆
    mb.frustum("stone", 0, 0, 0.0, 0.35, 0.28, 0.24, 8, math.pi / 8, top=True)
    mb.frustum(metal, 0, 0, 0.35, 0.6, 0.12, 0.08, 8, math.pi / 8, top=False)
    mb.frustum(metal, 0, 0, 0.6, pole_h, 0.06, 0.045, 8, math.pi / 8, top=True)
    zr = 0.6 + (pole_h - 0.6) * 0.35
    mb.frustum(metal, 0, 0, zr, zr + 0.08, 0.085, 0.085, 8, math.pi / 8, top=True, bottom=True)
    mb.frustum(metal, 0, 0, pole_h, pole_h + 0.15, 0.07, 0.0, 8, math.pi / 8, top=False)
    arms = [1] if r.random() < 0.55 else [1, -1]
    reach = 0.0
    for side in arms:
        # 弯臂：从灯杆斜上伸出，再水平一段，末端吊灯笼
        ln = r.uniform(0.5, 0.65)
        p0 = (0.0, 0.0, pole_h - 0.25)
        p1 = (side * ln * 0.55, 0.0, pole_h + 0.05)
        p2 = (side * ln, 0.0, pole_h + 0.05)
        mb.tube(metal, p0, p1, 0.03, 0.03, 6)
        mb.tube(metal, p1, p2, 0.03, 0.025, 6)
        # 斜撑的小卷：一根细杆连回灯杆
        mb.tube(metal, (0.0, 0.0, pole_h - 0.55), (side * ln * 0.45, 0.0, pole_h - 0.05), 0.018, 0.018, 4)
        mb.tube(metal, p2, (side * ln, 0.0, pole_h - 0.1), 0.012, 0.012, 4)
        _lantern(mb, side * ln, 0.0, pole_h - 0.1 - s * 1.5 - 0.05, s, metal)
        reach = max(reach, ln + s)
    return mb, {"footprint": [reach * 2 + 0.2, 0.6], "height": pole_h + 0.3}
