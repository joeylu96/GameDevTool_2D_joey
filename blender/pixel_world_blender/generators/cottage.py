"""农舍：石基 + 木板墙 + 双坡瓦顶（有厚度、白色封檐）+ 白色转角 + 门（门框、门板）+ 窗（窗框、窗台）+ 烟囱。
参数全部可调；按种子随机。"""
import math
import random

from ..builder import MeshBuilder

NAME = "农舍"
CATEGORY = "buildings"
DESC = "Blender 生成的农舍：石基、木板墙、双坡瓦顶、门窗和烟囱。"
VARY = "宽度、进深、墙面（红 / 赭 / 青 / 原木竖木板、白 / 黄横木板、石墙、白灰泥）、屋顶（双坡 / 四坡，灰 / 红）、坡度、窗户数量、烟囱位置随种子变化。"
TAGS = ["town", "yard"]

WALLS = ["wall_red", "wall_ochre", "wall_teal", "wall_wood", "siding_white", "siding_ochre", "stone", "plaster_white"]


def params(seed):
    r = random.Random(seed)
    return {
        "width": round(r.uniform(5.5, 8.0) * 4) / 4,
        "depth": round(r.uniform(4.5, 6.0) * 4) / 4,
        "wall": r.choice(WALLS),
        "roof": r.choice(["roof_grey", "roof_grey", "roof_red"]),
        "pitch": r.uniform(34, 44),
        "chimney_x": r.uniform(-0.6, 0.6),
        "roof_type": r.choice(["gable", "gable", "hip"]),
    }


def build(seed, **over):
    p = params(seed)
    p.update(over)
    mb = MeshBuilder()
    w, d = p["width"], p["depth"]
    hw, hd = w / 2, d / 2
    base_h, wall_h = 0.35, 2.9
    h = base_h + wall_h
    pitch = math.radians(p["pitch"])
    ridge = h + hd * math.tan(pitch)
    wall, roof = p["wall"], p["roof"]
    # 地基 + 墙 + 山墙
    mb.box("stone", (-hw - 0.1, -hd - 0.1, 0), (hw + 0.1, hd + 0.1, base_h))
    hip = p["roof_type"] == "hip"
    mb.box(wall, (-hw, -hd, base_h), (hw, hd, h), top=False)
    if not hip:  # 四坡顶没有山墙
        mb.face(wall, [(hw, -hd, h), (hw, hd, h), (hw, 0, ridge)], (1, 0, 0))
        mb.face(wall, [(-hw, hd, h), (-hw, -hd, h), (-hw, 0, ridge)], (-1, 0, 0))
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box("trim", (sx * hw - 0.1, sy * hd - 0.1, base_h), (sx * hw + 0.1, sy * hd + 0.1, h), top=False)
    # 屋顶：两片有厚度的斜板 + 封檐 + 屋脊
    ov = 0.45
    eave = h - ov * math.tan(pitch)
    ye, xe, t = hd + ov, hw + ov, 0.18
    rx = max(0.4, xe - ye) if hip else xe  # 四坡顶的屋脊短一截（四面坡度相同）
    for s in (-1, 1):
        tl, tr = (-rx, 0, ridge), (rx, 0, ridge)
        br, bl = (xe, s * ye, eave), (-xe, s * ye, eave)
        mb.face(roof, [tl, tr, br, bl], (0, s, 1))
        mb.face("wall_wood", [(x, y, z - t) for (x, y, z) in (tl, tr, br, bl)], (0, -s, -1))
        mb.face("trim", [bl, br, (br[0], br[1], br[2] - t), (bl[0], bl[1], bl[2] - t)], (0, s, 0))
        if not hip:
            for sx in (-1, 1):
                a, b = (sx * xe, 0, ridge), (sx * xe, s * ye, eave)
                mb.face("trim", [a, b, (b[0], b[1], b[2] - t), (a[0], a[1], a[2] - t)], (sx, 0, 0))
    if hip:  # 两头的三角坡面 + 下表面 + 封檐
        for sx in (-1, 1):
            a, b, c = (sx * xe, -ye, eave), (sx * xe, ye, eave), (sx * rx, 0, ridge)
            mb.face(roof, [a, b, c], (sx, 0, 1))
            mb.face("wall_wood", [(x, y, z - t) for (x, y, z) in (a, b, c)], (-sx, 0, -1))
            mb.face("trim", [a, b, (b[0], b[1], b[2] - t), (a[0], a[1], a[2] - t)], (sx, 0, 0))
    mb.box("roof_grey" if roof == "roof_red" else "brick", (-rx - 0.03, -0.14, ridge - 0.06), (rx + 0.03, 0.14, ridge + 0.1))
    # 门（正面 -Y 中间）：门框 + 门板 + 门楣 + 台阶
    fy = -hd
    mb.box("trim", (-0.65, fy - 0.08, base_h), (-0.55, fy, base_h + 2.1))
    mb.box("trim", (0.55, fy - 0.08, base_h), (0.65, fy, base_h + 2.1))
    mb.box("trim", (-0.75, fy - 0.12, base_h + 2.1), (0.75, fy, base_h + 2.22))
    mb.box("door", (-0.55, fy - 0.04, base_h), (0.55, fy, base_h + 2.1))
    mb.box("stone", (-0.9, fy - 0.6, 0), (0.9, fy, 0.2))
    # 窗：前后墙
    r = random.Random(seed * 7 + 1)
    n_win = max(1, int((w - 1.0) / 2.0))
    for s in (-1, 1):
        for i in range(n_win):
            x = -hw + w * (i + 0.5) / n_win
            if s < 0 and abs(x) < 1.25:
                continue
            _window(mb, x, s * hd, s, base_h + 0.85)
    # 山墙小窗
    if ridge - h > 1.8 and not hip:
        for sx in (-1, 1):
            _window_side(mb, sx * hw, sx, h + 0.15)
    # 烟囱（后坡）
    cx = p["chimney_x"] * hw
    cy = hd * 0.4
    mb.box("brick", (cx - 0.35, cy - 0.35, h), (cx + 0.35, cy + 0.35, ridge + 0.9))
    mb.box("stone", (cx - 0.42, cy - 0.42, ridge + 0.9), (cx + 0.42, cy + 0.42, ridge + 1.05))
    info = {"footprint": [w + 2 * ov, d + 2 * ov], "height": ridge + 1.05, "params": p}
    return mb, info


def _window(mb, x, y, s, z0, hw=0.5, wh=1.2):
    """前 / 后墙上的窗（s = -1 前墙，1 后墙）：玻璃 + 窗框 + 窗台"""
    o = y + s * 0.03
    mb.face("glass", [(x - s * hw, o, z0 + wh), (x + s * hw, o, z0 + wh), (x + s * hw, o, z0), (x - s * hw, o, z0)], (0, s, 0))
    for (x0, x1, z_0, z_1) in ((-hw - 0.06, hw + 0.06, wh, wh + 0.08), (-hw - 0.06, hw + 0.06, -0.08, 0.0),
                                (-hw - 0.06, -hw, 0, wh), (hw, hw + 0.06, 0, wh), (-0.025, 0.025, 0, wh)):
        ya, yb = sorted((y, y + s * 0.06))
        mb.box("trim", (x + x0, ya, z0 + z_0), (x + x1, yb, z0 + z_1))
    ya, yb = sorted((y, y + s * 0.16))
    mb.box("trim", (x - hw - 0.1, ya, z0 - 0.12), (x + hw + 0.1, yb, z0 - 0.04))


def _window_side(mb, x, sx, z0, hw=0.4, wh=1.0):
    o = x + sx * 0.03
    mb.face("glass", [(o, sx * hw, z0 + wh), (o, -sx * hw, z0 + wh), (o, -sx * hw, z0), (o, sx * hw, z0)], (sx, 0, 0))
    xa, xb = sorted((x, x + sx * 0.06))
    for (y0, y1, z_0, z_1) in ((-hw - 0.06, hw + 0.06, wh, wh + 0.08), (-hw - 0.06, hw + 0.06, -0.08, 0.0),
                                (-hw - 0.06, -hw, 0, wh), (hw, hw + 0.06, 0, wh)):
        mb.box("trim", (xa, y0, z0 + z_0), (xb, y1, z0 + z_1))
