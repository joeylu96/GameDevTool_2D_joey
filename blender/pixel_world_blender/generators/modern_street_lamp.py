"""现代路灯：细钢杆 + 扁平的 LED 灯头（底面发光，bulb）。变体 0 单臂、1 双臂、2 柱顶灯、3 矮柱灯（庭院 / 步道）。
灯臂伸向 -Y（导出后 Godot +Z，朝路）；原点在杆脚中心地面。info.light = 光斑中心（Blender 坐标）。"""
import math

from ..builder import MeshBuilder
from ._medieval import box

NAME = "现代路灯"
CATEGORY = "street"
DESC = "Blender 生成的现代路灯：细钢杆配扁平 LED 灯头，夜里灯头底面发光；有单臂、双臂、柱顶灯和矮柱步道灯四种。"
VARY = "变体 0 单臂、1 双臂、2 柱顶灯、3 矮柱灯；杆高和灯臂长度随款式不同。"
TAGS = ["town", "modern", "roadside"]
VARIANTS = 4


def _head(mb, x, y, z, lx=0.22, ly=0.55):
    """扁平 LED 灯头：顶面钢板 + 底面发光板，长边沿 Y"""
    box(mb, "steel", x - lx * 0.5, y - ly * 0.5, z, x + lx * 0.5, y + ly * 0.5, z + 0.09)
    box(mb, "bulb", x - lx * 0.5 + 0.03, y - ly * 0.5 + 0.03, z - 0.02, x + lx * 0.5 - 0.03, y + ly * 0.5 - 0.03, z)


def build(seed, **over):
    k = (seed - 1) % 4
    mb = MeshBuilder()
    # 底座：混凝土墩 + 钢法兰
    if k == 3:
        box(mb, "concrete", -0.14, -0.14, 0.0, 0.14, 0.14, 0.06)
        mb.tube("steel", (0, 0, 0.06), (0, 0, 0.9), 0.08, 0.08, 8, math.pi / 8)
        mb.frustum("bulb", 0.0, 0.0, 0.72, 0.86, 0.083, 0.083, 8, math.pi / 8, top=False)
        mb.frustum("steel", 0.0, 0.0, 0.9, 0.96, 0.1, 0.07, 8, math.pi / 8)
        return mb, {"footprint": [0.3, 0.3], "height": 0.96, "light": [0.0, 0.0, 0.8], "params": {"style": "bollard"}}
    box(mb, "concrete", -0.25, -0.25, 0.0, 0.25, 0.25, 0.12)
    box(mb, "steel", -0.13, -0.13, 0.12, 0.13, 0.13, 0.16)
    h = [6.0, 7.0, 4.2][k]
    mb.tube("steel", (0, 0, 0.16), (0, 0, h), 0.075, 0.05, 8, math.pi / 8)
    box(mb, "steel", -0.08, -0.06, 0.6, 0.08, 0.06, 1.0)  # 检修门
    if k == 2:  # 柱顶灯：圆柱形灯头，周圈发光
        mb.frustum("steel", 0.0, 0.0, h, h + 0.08, 0.16, 0.16, 12, top=False, bottom=True)
        mb.frustum("bulb", 0.0, 0.0, h + 0.08, h + 0.42, 0.14, 0.14, 12, top=False)
        mb.frustum("steel", 0.0, 0.0, h + 0.42, h + 0.52, 0.2, 0.06, 12)
        return mb, {"footprint": [0.5, 0.5], "height": round(h + 0.52, 2), "light": [0.0, 0.0, h],
                    "params": {"style": "post_top", "height": h}}
    arm = [1.4, 1.2][k]
    dirs = [-1] if k == 0 else [-1, 1]
    for sy in dirs:
        # 灯臂：从杆顶斜伸出去再水平
        p0, p1, p2 = (0.0, 0.0, h - 0.3), (0.0, sy * arm * 0.35, h), (0.0, sy * arm, h + 0.05)
        mb.tube("steel", p0, p1, 0.04, 0.035, 6)
        mb.tube("steel", p1, p2, 0.035, 0.03, 6)
        _head(mb, 0.0, sy * (arm + 0.15), h - 0.04)
    return mb, {"footprint": [0.5, round(0.5 + arm * len(dirs) + 0.3, 2)], "height": round(h + 0.1, 2),
                "light": [0.0, -(arm + 0.15), h - 0.06], "params": {"style": ["single", "double"][k], "height": h, "arm": arm}}
