"""旗杆：石墩上一根 5 米的木杆，顶上一根横杆挂着一面燕尾长旗（中间一个金色菱形纹章），杆顶一个铁尖。
旗面在 XZ 平面（正反两面），朝 -Y（导出后 Godot +Z）。原点在石墩中心地面。"""
from ..builder import MeshBuilder
from ._medieval import box

NAME = "旗杆"
CATEGORY = "street"
DESC = "Blender 生成的中世纪旗杆：石墩上的木杆、横杆挂着燕尾长旗，旗面有金色菱形纹章，适合城门、广场和集市。"
VARY = "旗帜颜色（红 / 蓝 / 绿）随变体变化。"
TAGS = ["town", "medieval", "plaza"]
VARIANTS = 3


def build(seed, **over):
    k = seed - 1
    cloth = ["cloth_red", "cloth_blue", "cloth_green"][k % 3]
    mb = MeshBuilder()
    mb.frustum("castle_stone", 0.0, 0.0, 0.0, 0.45, 0.42, 0.34, 8, 0.39, top=True)
    mb.frustum("timber", 0.0, 0.0, 0.45, 5.2, 0.08, 0.06, 8, 0.0, top=True)
    mb.frustum("iron", 0.0, 0.0, 5.2, 5.5, 0.06, 0.0, 6, 0.0)
    box(mb, "timber", -0.05, -0.05, 4.85, 0.95, 0.05, 4.95)
    for x in (0.12, 0.85):
        box(mb, "iron", x - 0.015, -0.015, 4.7, x + 0.015, 0.015, 4.85)
    # 燕尾旗：正反两面
    x0, x1 = 0.1, 0.88
    z0, z1 = 4.72, 2.4
    pts = [(x0, z0), (x1, z0), (x1, z1), ((x0 + x1) * 0.5, z1 + 0.35), (x0, z1)]
    for y, n in ((-0.012, (0, -1, 0)), (0.012, (0, 1, 0))):
        mb.face(cloth, [(x, y, z) for x, z in pts], n)
        cx, cz = (x0 + x1) * 0.5, 3.75
        dy = -0.004 if y < 0 else 0.004
        mb.face("cloth_gold", [(cx, y + dy, cz + 0.3), (cx + 0.2, y + dy, cz), (cx, y + dy, cz - 0.3), (cx - 0.2, y + dy, cz)], n)
        mb.face("cloth_gold", [(x0 + 0.05, y + dy, z0 - 0.12), (x1 - 0.05, y + dy, z0 - 0.12), (x1 - 0.05, y + dy, z0 - 0.18), (x0 + 0.05, y + dy, z0 - 0.18)], n)
    return mb, {"footprint": [1.4, 0.9], "height": 5.5, "params": {"color": cloth}}
