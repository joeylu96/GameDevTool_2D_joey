"""晾衣杆：两根木杆中间拉一根粗绳（铁丝），挂着几件衣服——床单、衬衫、裤子（双面薄片），颜色随变体变化。
绳子沿 X，原点在两杆中间地面；衣服正面朝 -Y（导出后 Godot +Z）。"""
from ..builder import MeshBuilder
from ._medieval import box

NAME = "晾衣杆"
CATEGORY = "props"
DESC = "Blender 生成的晾衣杆：两根木杆拉一根绳，挂着床单、衬衫和裤子。"
VARY = "衣服的件数、颜色和顺序随变体变化。"
TAGS = ["cn_village", "yard"]
VARIANTS = 3

COLORS = ["cloth_red", "cloth_blue", "paint_white", "cloth_green", "cloth_gold"]


def _cloth(mb, key, pts):
    """两面的布片"""
    mb.face(key, pts, (0, -1, 0))
    mb.face(key, [(x, y + 0.01, z) for x, y, z in pts][::-1], (0, 1, 0))


def build(seed, **over):
    k = (seed - 1) % 3
    L = 3.2
    hl = L * 0.5
    zl = 1.85
    mb = MeshBuilder()
    for sx in (-1, 1):
        box(mb, "trunk", sx * hl - 0.05, -0.05, 0.0, sx * hl + 0.05, 0.05, zl + 0.15)
        box(mb, "trunk", sx * hl - 0.05, -0.2, zl, sx * hl + 0.05, 0.2, zl + 0.06)
    mb.tube("iron", (-hl, 0.0, zl + 0.03), (hl, 0.0, zl + 0.03), 0.015, 0.015, 4)
    x = -hl + 0.25
    kinds = [["sheet", "shirt", "pants"], ["shirt", "shirt", "sheet"], ["pants", "sheet", "shirt", "shirt"]][k]
    for i, kind in enumerate(kinds):
        col = COLORS[(i * 2 + k) % len(COLORS)]
        if kind == "sheet":
            w, h = 1.0, 1.1
            _cloth(mb, col, [(x, 0.0, zl), (x + w, 0.0, zl), (x + w, 0.0, zl - h), (x, 0.0, zl - h)])
        elif kind == "shirt":
            w, h = 0.55, 0.65
            _cloth(mb, col, [(x + 0.1, 0.0, zl), (x + w - 0.1, 0.0, zl), (x + w - 0.1, 0.0, zl - h), (x + 0.1, 0.0, zl - h)])
            _cloth(mb, col, [(x, 0.0, zl), (x + 0.1, 0.0, zl), (x + 0.1, 0.0, zl - 0.25), (x, 0.0, zl - 0.2)])
            _cloth(mb, col, [(x + w - 0.1, 0.0, zl), (x + w, 0.0, zl), (x + w, 0.0, zl - 0.2), (x + w - 0.1, 0.0, zl - 0.25)])
        else:
            w, h = 0.45, 0.9
            _cloth(mb, col, [(x, 0.0, zl), (x + w, 0.0, zl), (x + w, 0.0, zl - 0.3), (x, 0.0, zl - 0.3)])
            _cloth(mb, col, [(x, 0.0, zl - 0.3), (x + 0.2, 0.0, zl - 0.3), (x + 0.2, 0.0, zl - h), (x, 0.0, zl - h)])
            _cloth(mb, col, [(x + 0.25, 0.0, zl - 0.3), (x + w, 0.0, zl - 0.3), (x + w, 0.0, zl - h), (x + 0.25, 0.0, zl - h)])
        for cx in (x + 0.05, x + w - 0.05):  # 夹子
            box(mb, "wall_wood", cx - 0.02, -0.03, zl - 0.04, cx + 0.02, 0.03, zl + 0.06)
        x += w + 0.12
        if x > hl - 0.4:
            break
    return mb, {"footprint": [round(L + 0.2, 2), 0.5], "height": round(zl + 0.15, 2), "params": {"items": kinds}}
