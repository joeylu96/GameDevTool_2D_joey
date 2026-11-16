"""压水井：水泥（或石板）井台上一台铸铁压水机——圆筒泵身、朝 -Y 伸出的出水嘴、斜翘的压杆，出水嘴下放着一只铁皮水桶；
井台一角有排水槽。原点在井台中心地面，出水嘴朝 -Y（导出后 Godot +Z）。"""
import math

from ..builder import MeshBuilder
from ._medieval import box

NAME = "压水井"
CATEGORY = "props"
DESC = "Blender 生成的压水井：水泥井台、铸铁泵身、出水嘴和压杆，出水嘴下放着一只铁皮水桶。"
VARY = "变体 0 水泥井台，1 石板井台；水桶位置和压杆角度不同。"
TAGS = ["cn_village", "yard"]
VARIANTS = 2


def build(seed, **over):
    k = (seed - 1) % 2
    base = ["cement", "stone"][k]
    mb = MeshBuilder()
    box(mb, base, -0.6, -0.6, 0.0, 0.6, 0.6, 0.22)
    box(mb, base, -0.25, -0.95, 0.0, 0.25, -0.6, 0.08)   # 排水槽
    box(mb, "water", -0.18, -0.9, 0.08, 0.18, -0.62, 0.09)
    # 泵身：底座法兰 + 圆筒 + 顶盖
    mb.frustum("iron", 0.0, 0.1, 0.22, 0.3, 0.16, 0.16, 10)
    mb.frustum("iron", 0.0, 0.1, 0.3, 1.05, 0.1, 0.09, 10, top=False)
    mb.frustum("iron", 0.0, 0.1, 1.05, 1.15, 0.13, 0.08, 10)
    # 出水嘴（朝 -Y，往下弯）
    mb.tube("iron", (0.0, 0.0, 0.85), (0.0, -0.3, 0.85), 0.045, 0.04, 8)
    mb.tube("iron", (0.0, -0.3, 0.85), (0.0, -0.36, 0.76), 0.04, 0.035, 8)
    # 压杆：从顶部往后上方翘起，末端一截手柄
    ang = math.radians([28.0, 18.0][k])
    p0 = (0.0, 0.15, 1.12)
    p1 = (0.0, 0.15 + 0.8 * math.cos(ang), 1.12 + 0.8 * math.sin(ang))
    mb.tube("iron", p0, p1, 0.03, 0.025, 6)
    mb.tube("iron", (0.0, 0.1, 1.15), (0.0, -0.05, 1.3), 0.025, 0.025, 6)
    mb.tube("trunk", p1, (0.0, p1[1] + 0.25 * math.cos(ang), p1[2] + 0.25 * math.sin(ang)), 0.035, 0.035, 6)
    # 铁皮水桶
    bx, by = (0.0, -0.42) if k == 0 else (0.35, -0.35)
    mb.frustum("steel", bx, by, 0.22, 0.52, 0.14, 0.17, 10, top=False, bottom=True)
    mb.frustum("water", bx, by, 0.45, 0.46, 0.16, 0.16, 10)
    mb.tube("iron", (bx - 0.16, by, 0.52), (bx, by, 0.66), 0.012 * 2, 0.012 * 2, 4)
    mb.tube("iron", (bx, by, 0.66), (bx + 0.16, by, 0.52), 0.024, 0.024, 4)
    return mb, {"footprint": [1.2, 1.6], "height": round(p1[2] + 0.2, 2), "params": {"base": base}}
