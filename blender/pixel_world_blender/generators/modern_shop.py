"""街角小店 / 咖啡馆：一层，整面落地橱窗 + 玻璃门，斜挑的帆布遮阳棚，门头一块空白招牌（不写字），平屋顶女儿墙；
咖啡馆变体门口摆一张小圆桌和两把椅子，花槽里种着灌木。正面朝 -Y（导出后 Godot +Z），原点在占地中心地面。"""
import math

from ..builder import MeshBuilder
from ._medieval import box, walls_box
from ._modern import pane, parapet

NAME = "街角小店"
CATEGORY = "buildings"
DESC = "Blender 生成的现代街角小店 / 咖啡馆：整面落地橱窗、玻璃门、条纹遮阳棚、门头空白招牌，咖啡馆门口有小圆桌和椅子。"
VARY = "宽度、墙色、遮阳棚颜色、招牌颜色、门口有没有桌椅随变体变化。"
TAGS = ["town", "modern", "plaza", "roadside"]
VARIANTS = 3


def build(seed, **over):
    k = seed - 1
    p = {
        "width": [7.0, 8.0, 7.5][k % 3],
        "depth": [6.0, 6.5, 6.0][k % 3],
        "wall": ["render_white", "render_grey", "render_sand"][k % 3],
        "awning": ["canvas_teal", "canvas_red", "canvas_ochre"][k % 3],
        "sign": ["clad_dark", "paint_teal", "clad_wood"][k % 3],
        "cafe": k % 3 != 1,
    }
    p.update(over)
    mb = MeshBuilder()
    w, d = p["width"], p["depth"]
    hw, hd = w * 0.5, d * 0.5
    H = 3.8
    box(mb, "concrete", -hw - 0.05, -hd - 0.05, 0.0, hw + 0.05, hd + 0.05, 0.15)
    W = walls_box(mb, p["wall"], -hw, -hd, 0.15, hw, hd, H)
    f = W["front"]
    # 橱窗 + 门：深色金属框，整面玻璃
    door_s = w * 0.68
    pane(mb, f, 0.4, 0.35, door_s - 0.25, 2.75, frame="metal", mullions=2, transom=2.35)
    f.box(mb, "concrete", 0.3, 0.0, door_s - 0.15, 0.35, 0.0, 0.1)
    pane(mb, f, door_s, 0.0, door_s + 1.1, 2.75, frame="metal", transom=2.35)
    f.box(mb, "steel", door_s + 0.85, 0.9, door_s + 0.9, 1.7, 0.06, 0.14)
    pane(mb, f, door_s + 1.35, 0.35, w - 0.4, 2.75, frame="metal", transom=2.35)
    # 门头招牌（空白）+ 两盏射灯
    f.box(mb, p["sign"], 0.5, 2.95, w - 0.5, 3.55, 0.0, 0.12)
    f.box(mb, "steel", 0.45, 2.92, w - 0.45, 2.98, 0.0, 0.14)
    for s in (w * 0.25, w * 0.75):
        f.box(mb, "steel", s - 0.03, 3.55, s + 0.03, 3.62, 0.0, 0.3)
        f.box(mb, "bulb", s - 0.08, 3.5, s + 0.08, 3.56, 0.25, 0.4)
    # 遮阳棚：斜挑的帆布，两侧三角布 + 前沿垂边
    zt, zb, out = 2.9, 2.45, 1.4
    x0, x1 = -hw + 0.3, -hw + door_s + 1.2
    mb.face(p["awning"], [(x0, -hd, 0.15 + zt), (x1, -hd, 0.15 + zt), (x1, -hd - out, 0.15 + zb), (x0, -hd - out, 0.15 + zb)],
            (0, -0.3, 1))
    mb.face(p["awning"], [(x0, -hd - out, 0.15 + zb - 0.01), (x1, -hd - out, 0.15 + zb - 0.01), (x1, -hd, 0.15 + zt - 0.01),
                          (x0, -hd, 0.15 + zt - 0.01)], (0, 0.3, -1))
    mb.face(p["awning"], [(x0, -hd - out, 0.15 + zb), (x1, -hd - out, 0.15 + zb), (x1, -hd - out, 0.15 + zb - 0.25),
                          (x0, -hd - out, 0.15 + zb - 0.25)], (0, -1, 0))
    mb.face(p["awning"], [(x1, -hd - out + 0.01, 0.15 + zb - 0.25), (x0, -hd - out + 0.01, 0.15 + zb - 0.25),
                          (x0, -hd - out + 0.01, 0.15 + zb), (x1, -hd - out + 0.01, 0.15 + zb)], (0, 1, 0))
    for xs, sgn in ((x0, -1), (x1, 1)):
        mb.face(p["awning"], [(xs, -hd, 0.15 + zt), (xs, -hd - out, 0.15 + zb), (xs, -hd, 0.15 + zb)], (sgn, 0, 0))
        mb.face(p["awning"], [(xs, -hd, 0.15 + zb), (xs, -hd - out, 0.15 + zb), (xs, -hd, 0.15 + zt)], (-sgn, 0, 0))
        mb.tube("steel", (xs, -hd, 0.15 + zt), (xs, -hd - out, 0.15 + zb), 0.025, 0.025, 4)
    # 侧窗 + 平屋顶
    pane(mb, W["right"], 1.2, 0.9, d - 1.2, 2.5, mullions=1)
    pane(mb, W["left"], 1.5, 1.2, d - 1.5, 2.5)
    box(mb, "concrete", -hw, -hd, H, hw, hd, H + 0.08)
    parapet(mb, p["wall"], -hw, -hd, hw, hd, H, h=0.5, t=0.2)
    box(mb, "steel", -1.2, 0.5, H + 0.08, -0.2, 1.6, H + 0.75)  # 屋顶上的空调机组
    # 门口：花槽、咖啡桌椅
    for xs in (-hw + 0.3, -hw + door_s - 0.6):
        box(mb, "concrete", xs, -hd - 0.55, 0.0, xs + 0.9, -hd - 0.1, 0.45)
        mb.blob("leaf", xs + 0.45, -hd - 0.32, 0.65, 0.4, 0.5, 8)
    if p["cafe"]:
        tx, ty = -hw + 1.9, -hd - 1.9
        mb.frustum("steel", tx, ty, 0.0, 0.04, 0.25, 0.25, 10)
        mb.tube("steel", (tx, ty, 0.04), (tx, ty, 0.72), 0.03, 0.03, 6)
        mb.frustum("render_white", tx, ty, 0.72, 0.75, 0.38, 0.38, 12, top=True, bottom=True)
        for a in (0.4, math.pi + 0.4):
            cx, cy = tx + math.cos(a) * 0.65, ty + math.sin(a) * 0.65
            box(mb, "steel", cx - 0.2, cy - 0.2, 0.43, cx + 0.2, cy + 0.2, 0.47)
            for dx in (-0.17, 0.17):
                for dy in (-0.17, 0.17):
                    box(mb, "steel", cx + dx - 0.02, cy + dy - 0.02, 0.0, cx + dx + 0.02, cy + dy + 0.02, 0.43)
            bx, by = cx + math.cos(a) * 0.19, cy + math.sin(a) * 0.19
            box(mb, "steel", min(bx, cx + math.cos(a) * 0.21) - 0.2 * abs(math.sin(a)) - 0.02,
                min(by, cy + math.sin(a) * 0.21) - 0.2 * abs(math.cos(a)) - 0.02, 0.47,
                max(bx, cx + math.cos(a) * 0.21) + 0.2 * abs(math.sin(a)) + 0.02,
                max(by, cy + math.sin(a) * 0.21) + 0.2 * abs(math.cos(a)) + 0.02, 0.9)
    info = {"footprint": [round(w + 0.4, 2), round(d + 0.4, 2)], "height": round(H + 0.75, 2),
            "params": {k: (round(v, 3) if isinstance(v, float) else v) for k, v in p.items()}}
    return mb, info
