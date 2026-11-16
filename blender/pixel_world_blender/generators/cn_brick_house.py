"""八九十年代的中国农村平房：一层，红砖 / 青砖 / 土坯墙（部分正面刷白灰、下面留砖墙裙），小青瓦双坡顶（土坯房有的是草顶），
正中一樘木板双开门，门两边贴红纸对联、门楣贴横批（只是红纸，不写字），两边各一两扇木框玻璃窗，屋脊两端微翘，
山墙一侧有砖砌烟囱，门前一级石阶。正面朝 -Y（导出后 Godot +Z），原点在占地中心地面。info.params 有 width / depth。"""
import math
import random

from ..builder import MeshBuilder
from ._medieval import box, gable_roof, walls_box
from ._modern import cn_roof

NAME = "农村平房"
CATEGORY = "buildings"
DESC = "Blender 生成的八九十年代农村平房：红砖 / 青砖 / 土坯墙，小青瓦双坡顶，木板双开门贴着红纸对联和横批，木框玻璃窗，砖烟囱。"
VARY = "宽 8~12 米、深 5~6.5 米、墙（红砖 / 青砖 / 白灰墙裙 / 土坯）、屋顶（小青瓦 / 草顶）、窗户数量、烟囱位置随变体变化。"
TAGS = ["cn_village", "town", "yard"]
VARIANTS = 8

WALL_H = 3.0


def params(seed):
    r = random.Random(seed * 97 + 5)
    k = seed - 1
    wall = ["brick_red_cn", "brick_grey", "whitewash", "brick_red_cn", "mudbrick", "brick_grey", "whitewash", "mudbrick"][k % 8]
    return {
        "width": round(r.uniform(8.0, 12.0) * 2) / 2,
        "depth": round(r.uniform(5.0, 6.5) * 2) / 2,
        "wall": wall,
        "roof": "thatch" if wall == "mudbrick" and k % 2 == 0 else "tile_cn",
        "windows": 2 if r.random() < 0.6 else 1,
        "chimney": 1 if r.random() < 0.5 else -1,
        "door": ["door_wood", "door_red", "door_teal"][r.randrange(3)],
    }


def _cn_window(mb, wall, s, z, w=1.3, h=1.25, frame="door_wood"):
    """木框玻璃窗：外框 + 十字 / 井字窗棂 + 窗台砖"""
    hw = w * 0.5
    wall.quad(mb, "glass", s - hw, z, s + hw, z + h, 0.012)
    f = 0.07
    wall.box(mb, frame, s - hw - f, z - f, s + hw + f, z, 0.0, 0.07)
    wall.box(mb, frame, s - hw - f, z + h, s + hw + f, z + h + f, 0.0, 0.07)
    wall.box(mb, frame, s - hw - f, z, s - hw, z + h, 0.0, 0.07)
    wall.box(mb, frame, s + hw, z, s + hw + f, z + h, 0.0, 0.07)
    for i in (1, 2):
        x = s - hw + w * i / 3
        wall.box(mb, frame, x - 0.025, z, x + 0.025, z + h, 0.0, 0.05)
    wall.box(mb, frame, s - hw, z + h * 0.62 - 0.025, s + hw, z + h * 0.62 + 0.025, 0.0, 0.05)
    wall.box(mb, "brick_grey", s - hw - 0.12, z - 0.14, s + hw + 0.12, z - f, 0.0, 0.12)


def _cn_door(mb, wall, s, door="door_wood", w=1.6, h=2.2):
    """木板双开门 + 门框 + 门楣；两边红纸对联、上面横批，门上一对铁门环"""
    hw = w * 0.5
    wall.box(mb, door, s - hw, 0.0, s + hw, h, 0.0, 0.04)
    wall.box(mb, "wall_wood", s - 0.025, 0.0, s + 0.025, h, 0.04, 0.06)
    for i in (-2, -1, 1, 2):  # 门板竖缝
        x = s + i * hw / 2.6
        wall.box(mb, door, x - 0.015, 0.05, x + 0.015, h - 0.05, 0.04, 0.05)
    f = 0.12
    wall.box(mb, "wall_wood", s - hw - f, 0.0, s - hw, h + f, 0.0, 0.1)
    wall.box(mb, "wall_wood", s + hw, 0.0, s + hw + f, h + f, 0.0, 0.1)
    wall.box(mb, "wall_wood", s - hw - f - 0.1, h, s + hw + f + 0.1, h + f + 0.06, 0.0, 0.14)
    for sx in (-1, 1):
        wall.box(mb, "iron", s + sx * 0.18 - 0.05, 1.05, s + sx * 0.18 + 0.05, 1.15, 0.04, 0.09)
        # 对联：门框外侧一条竖红纸
        x0 = s + sx * (hw + f + 0.08)
        x1 = x0 + sx * 0.3
        wall.box(mb, "red_paper", min(x0, x1), 0.45, max(x0, x1), 2.15, 0.0, 0.015)
    wall.box(mb, "red_paper", s - 0.7, h + f + 0.12, s + 0.7, h + f + 0.42, 0.0, 0.015)  # 横批
    # 门上的「福」字位置：一块斜放的红纸方块（不写字）
    wall.box(mb, "red_paper", s - 0.12 - hw * 0.5, 1.45, s + 0.12 - hw * 0.5, 1.69, 0.04, 0.055)
    wall.box(mb, "red_paper", s - 0.12 + hw * 0.5, 1.45, s + 0.12 + hw * 0.5, 1.69, 0.04, 0.055)


def build(seed, **over):
    p = params(seed)
    p.update(over)
    mb = MeshBuilder()
    w, d = p["width"], p["depth"]
    hw, hd = w * 0.5, d * 0.5
    wall_key = p["wall"]
    # 台基（水泥 / 砖）+ 门前石阶
    box(mb, "cement", -hw - 0.15, -hd - 0.15, 0.0, hw + 0.15, hd + 0.15, 0.2)
    box(mb, "stone", -1.0, -hd - 0.7, 0.0, 1.0, -hd - 0.15, 0.12)
    W = walls_box(mb, wall_key, -hw, -hd, 0.2, hw, hd, 0.2 + WALL_H)
    f = W["front"]
    if wall_key == "whitewash":  # 白灰墙：下面一圈 0.9 米高的砖墙裙
        for key in ("front", "right", "back", "left"):
            ln = w if key in ("front", "back") else d
            W[key].box(mb, "brick_red_cn", 0.0, 0.0, ln, 0.9, 0.0, 0.03)
    _cn_door(mb, f, w * 0.5, p["door"])
    n = p["windows"]
    for i in range(n):
        off = 2.35 + i * 1.9  # 门（含对联）占中间约 ±1.6 米
        for sx in (-1, 1):
            s = w * 0.5 + sx * off
            if 0.9 < s < w - 0.9:
                _cn_window(mb, f, s, 1.0)
    # 后墙一扇小窗、山墙一扇小窗
    _cn_window(mb, W["back"], w * 0.5, 1.4, 0.9, 0.8)
    _cn_window(mb, W["left"], d * 0.5, 1.4, 0.8, 0.8)
    # 屋顶
    top = 0.2 + WALL_H
    if p["roof"] == "thatch":
        ridge, gables = gable_roof(mb, "thatch", -hw, hw, -hd, hd, top, 40.0, axis="x", eave=0.5, gable=0.35, thatch=True)
    else:
        ridge, gables = cn_roof(mb, -hw, hw, -hd, hd, top, 27.0, eave=0.5, gable=0.25)
    for sa, tri in gables:
        mb.face(wall_key if wall_key != "whitewash" else "whitewash", tri, (sa, 0, 0))
    # 檐下一条砖线脚
    if p["roof"] != "thatch":
        box(mb, "brick_grey", -hw - 0.05, -hd - 0.08, top - 0.18, hw + 0.05, -hd, top)
        box(mb, "brick_grey", -hw - 0.05, hd, top - 0.18, hw + 0.05, hd + 0.08, top)
    # 砖烟囱（山墙一侧，从屋面穿出）
    cx = p["chimney"] * (hw - 0.9)
    cy = 0.5
    z_roof = top + (hd - cy) * math.tan(math.radians(27.0 if p["roof"] != "thatch" else 40.0))
    box(mb, "brick_red_cn" if wall_key != "brick_grey" else "brick_grey", cx - 0.3, cy - 0.3, top - 0.2, cx + 0.3, cy + 0.3, max(ridge, z_roof) + 0.7)
    box(mb, "cement", cx - 0.36, cy - 0.36, max(ridge, z_roof) + 0.7, cx + 0.36, cy + 0.36, max(ridge, z_roof) + 0.8)
    info = {
        "footprint": [round(w + 1.0, 2), round(d + 1.3, 2)],
        "height": round(ridge + 0.8, 2),
        "door": [0.0, -hd, 0.2],
        "params": {k: (round(v, 3) if isinstance(v, float) else v) for k, v in p.items()},
    }
    return mb, info
