"""现代住宅：一到两层，抹灰外墙（白 / 灰 / 沙色）配木挂板或深色挂板的体块，平屋顶（女儿墙）或单坡金属屋面，
落地大玻璃窗和玻璃入户门，入口雨棚，部分二层带玻璃栏板的阳台；空调外机、落水管、门边壁灯。
正面朝 -Y（导出后 Godot +Z），原点在占地中心地面。info.params 里有 width / depth / floors。"""
import random

from ..builder import MeshBuilder
from ._medieval import box, walls_box
from ._modern import downpipe, pane, parapet, sill

NAME = "现代住宅"
CATEGORY = "buildings"
DESC = "Blender 生成的现代住宅：抹灰外墙配木或深色挂板，平屋顶或单坡金属屋面，落地大玻璃窗、玻璃入户门、入口雨棚，部分带玻璃栏板阳台。"
VARY = "宽 7.5~11 米、深 6~9 米、一层或两层、墙色（白 / 灰 / 沙）、挂板（木 / 深色）、屋顶（平顶女儿墙 / 单坡）、阳台、窗型随变体变化。"
TAGS = ["town", "modern"]
VARIANTS = 8

PLINTH = 0.25
FLOOR_H = 3.0


def params(seed):
    r = random.Random(seed * 131 + 17)
    k = seed - 1
    p = {
        "width": round(r.uniform(7.5, 11.0) * 2) / 2,
        "depth": round(r.uniform(6.0, 9.0) * 2) / 2,
        "floors": 1 if k % 4 == 3 else 2,
        "wall": ["render_white", "render_grey", "render_sand", "render_white"][k % 4],
        "accent": ["clad_wood", "clad_dark"][(k // 2) % 2],
        "roof": "flat" if k % 3 != 1 else "mono",
        "balcony": k % 2 == 0,
        "accent_side": 1 if r.random() < 0.5 else -1,
    }
    return p


def build(seed, **over):
    p = params(seed)
    p.update(over)
    r = random.Random(seed * 7 + 3)
    mb = MeshBuilder()
    w, d, nf = p["width"], p["depth"], p["floors"]
    hw, hd = w * 0.5, d * 0.5
    wall_key, accent = p["wall"], p["accent"]
    top = PLINTH + FLOOR_H * nf
    # 混凝土基座 + 入口台阶
    box(mb, "concrete", -hw - 0.06, -hd - 0.06, 0.0, hw + 0.06, hd + 0.06, PLINTH)
    W = walls_box(mb, wall_key, -hw, -hd, PLINTH, hw, hd, top)
    f = W["front"]
    # 挂板体块：正面一侧（约 35% 宽）整面贴挂板，并在侧墙上包过去 1.2 米
    a_w = round(w * 0.36, 2)
    a0, a1 = (w - a_w, w) if p["accent_side"] > 0 else (0.0, a_w)
    f.box(mb, accent, a0, 0.0, a1, top - PLINTH, 0.0, 0.05)
    side = W["right"] if p["accent_side"] > 0 else W["left"]
    side.box(mb, accent, 0.0 if p["accent_side"] > 0 else d - 1.2, 0.0, 1.2 if p["accent_side"] > 0 else d, top - PLINTH, 0.0, 0.05)
    # 层间混凝土线脚
    if nf == 2:
        box(mb, "concrete", -hw - 0.05, -hd - 0.05, PLINTH + FLOOR_H - 0.08, hw + 0.05, hd + 0.05, PLINTH + FLOOR_H + 0.08)
    # 入户门（玻璃门，在挂板体块的另一侧靠中间）
    door_s = (a0 - 1.4) if p["accent_side"] > 0 else (a1 + 0.6)
    door_s = min(max(door_s, 0.5), w - 1.6)
    pane(mb, f, door_s, 0.0, door_s + 1.0, 2.3, frame="metal", mullions=0, transom=2.0)
    f.box(mb, "steel", door_s + 0.75, 0.9, door_s + 0.8, 1.6, 0.06, 0.14)  # 竖拉手
    f.box(mb, "bulb", door_s - 0.32, 1.9, door_s - 0.18, 2.1, 0.0, 0.08)    # 门边壁灯（夜里亮）
    # 入口雨棚（悬挑的薄板）+ 台阶
    cx0, cx1 = -hw + door_s - 0.5, -hw + door_s + 1.5
    box(mb, "concrete", cx0, -hd - 1.25, PLINTH + 2.55, cx1, -hd, PLINTH + 2.72)
    box(mb, "steel", cx0, -hd - 1.27, PLINTH + 2.5, cx1, -hd - 1.2, PLINTH + 2.75)
    box(mb, "concrete", cx0 + 0.2, -hd - 0.9, 0.0, cx1 - 0.2, -hd, PLINTH)
    # 一层大窗：门的另一边一整块落地窗（分 2~3 格），挂板上开一扇竖条窗
    if p["accent_side"] > 0:
        g0, g1 = 0.6, max(door_s - 0.6, 1.6)
    else:
        g0, g1 = min(door_s + 1.6, w - 1.6), w - 0.6
    if g1 - g0 > 1.0:
        pane(mb, f, g0, 0.25, g1, 2.4, mullions=2 if g1 - g0 > 3 else 1)
        sill(mb, f, g0, g1, 0.25)
    acc_mid = (a0 + a1) * 0.5
    pane(mb, f, acc_mid - 0.35, 0.6, acc_mid + 0.35, 2.4, frame="metal")
    # 二层：横向长窗 / 阳台门
    if nf == 2:
        z2 = FLOOR_H
        if p["balcony"]:
            bs0, bs1 = (0.6, min(w * 0.55, w - a_w - 0.3)) if p["accent_side"] > 0 else (max(a_w + 0.3, w * 0.45), w - 0.6)
            pane(mb, f, bs0 + 0.2, z2 + 0.1, bs1 - 0.2, z2 + 2.4, mullions=2)
            # 阳台：悬挑楼板 + 玻璃栏板 + 钢扶手
            x0b, x1b = -hw + bs0, -hw + bs1
            box(mb, "concrete", x0b, -hd - 1.2, PLINTH + z2 - 0.05, x1b, -hd, PLINTH + z2 + 0.12)
            yb = -hd - 1.14
            mb.face("glass_car", [(x0b + 0.05, yb, PLINTH + z2 + 0.12), (x1b - 0.05, yb, PLINTH + z2 + 0.12),
                                  (x1b - 0.05, yb, PLINTH + z2 + 1.05), (x0b + 0.05, yb, PLINTH + z2 + 1.05)], (0, -1, 0))
            mb.face("glass_car", [(x1b - 0.05, yb + 0.01, PLINTH + z2 + 0.12), (x0b + 0.05, yb + 0.01, PLINTH + z2 + 0.12),
                                  (x0b + 0.05, yb + 0.01, PLINTH + z2 + 1.05), (x1b - 0.05, yb + 0.01, PLINTH + z2 + 1.05)], (0, 1, 0))
            box(mb, "steel", x0b, yb - 0.04, PLINTH + z2 + 1.05, x1b, yb + 0.04, PLINTH + z2 + 1.12)
            for xx in (x0b + 0.03, x1b - 0.03):
                box(mb, "steel", xx - 0.03, -hd - 1.18, PLINTH + z2 + 0.12, xx + 0.03, -hd, PLINTH + z2 + 1.12)
        else:
            pane(mb, f, 0.8, z2 + 0.9, w - 0.8, z2 + 2.2, mullions=3)
            sill(mb, f, 0.8, w - 0.8, z2 + 0.9)
    # 侧墙、后墙的窗
    for key, ln in (("left", d), ("right", d), ("back", w)):
        wl = W[key]
        n_win = 1 if ln < 7.5 else 2
        for i in range(n_win):
            s = ln * (i + 1) / (n_win + 1)
            for fl in range(nf):
                zz = fl * FLOOR_H + 0.9
                pane(mb, wl, s - 0.5, zz, s + 0.5, zz + 1.4)
                sill(mb, wl, s - 0.5, s + 0.5, zz)
    # 屋顶
    if p["roof"] == "flat":
        box(mb, "concrete", -hw, -hd, top, hw, hd, top + 0.08)
        parapet(mb, wall_key, -hw, -hd, hw, hd, top, h=0.55, t=0.2)
        roof_top = top + 0.61
        # 平屋顶上的太阳能板（部分变体）
        if r.random() < 0.5:
            for i in range(3):
                x = -hw + 1.0 + i * 1.3
                mb.face("glass_car", [(x, -0.4, top + 0.25), (x + 1.1, -0.4, top + 0.25), (x + 1.1, 0.6, top + 0.65),
                                      (x, 0.6, top + 0.65)], (0, -0.4, 1))
                box(mb, "steel", x + 0.1, 0.5, top + 0.08, x + 0.18, 0.58, top + 0.62)
                box(mb, "steel", x + 0.92, 0.5, top + 0.08, x + 1.0, 0.58, top + 0.62)
    else:
        # 单坡金属屋面：前高后低；侧墙补成梯形
        rise = 1.0
        zf, zb = top + rise, top
        for s in (-1, 1):
            x = s * hw
            mb.face(wall_key, [(x, -hd, top), (x, hd, top), (x, -hd, zf)], (s, 0, 0))
        mb.face(wall_key, [(-hw, -hd, top), (hw, -hd, top), (hw, -hd, zf), (-hw, -hd, zf)], (0, -1, 0))
        e = 0.4
        pts = [(-hw - e, -hd - e, zf + 0.12), (hw + e, -hd - e, zf + 0.12), (hw + e, hd + e, zb - 0.05), (-hw - e, hd + e, zb - 0.05)]
        mb.face("metal_roof", pts, (0, -0.3, 1))
        mb.face("roof_under", [(x, y, z - 0.12) for x, y, z in pts][::-1], (0, 0.3, -1))
        for i, j, n in ((0, 1, (0, -1, 0)), (1, 2, (1, 0, 0)), (2, 3, (0, 1, 0)), (3, 0, (-1, 0, 0))):
            a, b = pts[i], pts[j]
            mb.face("steel", [a, b, (b[0], b[1], b[2] - 0.12), (a[0], a[1], a[2] - 0.12)], n)
        # 檐沟
        box(mb, "steel", -hw - e, hd + e - 0.02, zb - 0.25, hw + e, hd + e + 0.14, zb - 0.1)
        roof_top = zf + 0.12
    # 落水管、空调外机
    downpipe(mb, hw - 0.1, -hd - 0.08, top)
    downpipe(mb, -hw + 0.1, hd + 0.08, top)
    ax = -hw - 0.35 if p["accent_side"] > 0 else hw + 0.35
    box(mb, "paint_white", ax - 0.3, 0.2, PLINTH, ax + 0.3, 1.0, PLINTH + 0.6)
    mb.tube("metal", (ax - 0.31 * (1 if ax < 0 else -1), 0.6, PLINTH + 0.3), (ax - 0.33 * (1 if ax < 0 else -1), 0.6, PLINTH + 0.3),
            0.2, 0.2, 10)
    info = {
        "footprint": [round(w + 0.9, 2), round(d + 0.9, 2)],
        "height": round(roof_top, 2),
        "door": [round(-hw + door_s + 0.5, 2), -hd, PLINTH],
        "params": {k: (round(v, 3) if isinstance(v, float) else v) for k, v in p.items()},
    }
    return mb, info
