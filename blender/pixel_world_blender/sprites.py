"""HD-2D 像素角色（P4）：在 Blender 里用参数搭一个 Q 版低模角色（约 3.5 头身），逐帧摆出待机 / 走路姿势，
从 8 个方向用正交相机渲染，再在 numpy 里做成像素画，拼成一张精灵表交给 Godot。

做法（每一帧、每个方向渲染两遍，都用 Workbench，快且稳定）：
  1. 材质 ID 遍：平光 + 每个部位一种纯色 → 每个像素属于哪个部位（皮肤、头发、上衣……）
  2. 法线遍：matcap「check_normal+y」把每个像素的法线编码成颜色，再用固定的左上主光算明暗
  合成：按明暗分三档，从这个部位的三色色阶里取色（赛璐璐式的硬分档，像手绘像素画），
  再在轮廓外描 1 像素的深色描边（用相邻部位最深的颜色压暗，不是死黑，看起来更细腻）。
  渲染时用 2 倍分辨率，再 2×2 合并（部位取多数、明暗取平均），边缘更干净、没有锯齿噪点。

尺寸：每帧 128×128 像素，角色约 96 像素高（60 像素 / 米）——比同类 HD-2D 游戏的角色更精细。
坐标约定：Blender Z 向上，角色正面朝 -Y。第 d 行方向 = 相机从角色正面逆时针（俯视）转 d×45°。
"""
import json
import math
import os
import tempfile
from pathlib import Path

import bmesh
import bpy
import numpy as np

from .builder import MeshBuilder

VERSION = "0.1.0"
FRAME = 128
SS = 2
PX_PER_M = 60.0
ELEV = math.radians(12.0)   # 相机俯角：接近平视，和 HD-2D 的角色立绘角度一致
TARGET_Z = 0.95
DIRS = 8
IDLE_FRAMES = 4
WALK_FRAMES = 6
INK = np.array([0x1d, 0x20, 0x30]) / 255.0

# 光照：法线遍（matcap「check_normal+y」把视角空间法线编码成颜色）解码后自己算，
# 主光从左上前方照来（和场景里的太阳大致一致，所有方向的帧光照一致，不会转个身就变暗）。
# 明暗按 N·L 分档：亮 / 中 / 暗
LIGHT_DIR = np.array([-0.5, 0.62, 0.6]) / np.linalg.norm([-0.5, 0.62, 0.6])
TONE_HI = 0.62
TONE_MID = 0.18


def _hex(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


# ---------------------------------------------------------------- 默认色阶（亮、中、暗）

BASE_COLORS = {
    "skin": ["#f7d6b8", "#e8b892", "#bf8466"],
    "eye": ["#2b2338", "#2b2338", "#2b2338"],
    "metal": ["#eef2f7", "#aab4c3", "#666c7c"],
    "wood": ["#9b7653", "#7a5a3e", "#5a412e"],
    "boots": ["#7a5a3e", "#5a412e", "#3d2c22"],
    "gem": ["#fff3b8", "#ffd35c", "#e0952e"],
    "shine": ["#ffffff", "#ffffff", "#ffffff"],
}

# ---------------------------------------------------------------- 原创角色预设

PRESETS = [
    {"id": "swordsman", "name": "旅人剑士", "desc": "背着红披风的年轻剑士，腰间挂一把长剑，短发翘起。",
     "hair": "spiky", "hat": None, "skirt": 0.2, "sleeves": "long", "cape": True, "scarf": False, "weapon": "sword",
     "colors": {"hair": ["#7a5434", "#5a3a24", "#3b2618"], "top": ["#6f92c6", "#4a6fa5", "#34507a"],
                "bottom": ["#6b707c", "#4c505c", "#353845"], "skirt": ["#6f92c6", "#4a6fa5", "#34507a"],
                "trim": ["#c9a36a", "#9b7653", "#6f5842"], "cape": ["#d0564a", "#a3352d", "#6e2424"]}},
    {"id": "merchant", "name": "行商", "desc": "戴宽檐帽的行商，系着白围裙，腰边挎一个货袋。",
     "hair": "short", "hat": "wide", "skirt": 0.32, "sleeves": "long", "cape": False, "scarf": True, "weapon": "bag",
     "colors": {"hair": ["#3d3a40", "#2a282e", "#1c1b20"], "top": ["#e2b25c", "#c48f3c", "#8f6230"],
                "bottom": ["#7a5a3e", "#5a412e", "#3d2c22"], "skirt": ["#f3eee3", "#d9d0bf", "#ada28c"],
                "trim": ["#6f9c94", "#4f7c78", "#3a5c5c"], "hat": ["#9b7653", "#7a5a3e", "#5a412e"],
                "scarf": ["#6f9c94", "#4f7c78", "#3a5c5c"]}},
    {"id": "maiden", "name": "村姑", "desc": "长发的村庄姑娘，青色长裙配白围裙，走路时裙摆轻轻摆动。",
     "hair": "long", "hat": None, "skirt": 0.52, "sleeves": "short", "cape": False, "scarf": False, "weapon": None,
     "colors": {"hair": ["#c2683e", "#9a4a2c", "#6b301f"], "top": ["#f3eee3", "#d9d0bf", "#ada28c"],
                "bottom": ["#4f7c78", "#3a5c5c", "#284041"], "skirt": ["#6f9c94", "#4f7c78", "#3a5c5c"],
                "trim": ["#c4473a", "#a3352d", "#7d2826"]}},
    {"id": "scholar", "name": "学者", "desc": "扎马尾的学者，紫色长袍，手持顶端嵌着宝石的木杖。",
     "hair": "ponytail", "hat": None, "skirt": 0.55, "sleeves": "long", "cape": False, "scarf": False, "weapon": "staff",
     "colors": {"hair": ["#3a3550", "#27233a", "#181626"], "top": ["#9a80b8", "#735a94", "#4f3d6a"],
                "bottom": ["#4f3d6a", "#3a2d50", "#281f38"], "skirt": ["#9a80b8", "#735a94", "#4f3d6a"],
                "trim": ["#e0b84a", "#b9843a", "#8f6230"]}},
    {"id": "guard", "name": "卫兵", "desc": "戴铁盔、穿红色罩袍的镇上卫兵，手持长枪。",
     "hair": "short", "hat": "helmet", "skirt": 0.26, "sleeves": "long", "cape": False, "scarf": False, "weapon": "spear",
     "colors": {"hair": ["#5a412e", "#3d2c22", "#2a1e17"], "top": ["#d0564a", "#a3352d", "#6e2424"],
                "bottom": ["#6b707c", "#4c505c", "#353845"], "skirt": ["#d0564a", "#a3352d", "#6e2424"],
                "trim": ["#e0b84a", "#b9843a", "#8f6230"]}},
    {"id": "elder", "name": "长者", "desc": "白发白须的村中长者，披着棕色长袍，拄一根短拐杖。",
     "hair": "bald", "hat": None, "skirt": 0.55, "sleeves": "long", "cape": False, "scarf": True, "weapon": "cane",
     "beard": True, "height": 0.94,
     "colors": {"hair": ["#f4f7fb", "#d3dae6", "#9fabbf"], "top": ["#a8835e", "#7a5a3e", "#5a412e"],
                "bottom": ["#7a5a3e", "#5a412e", "#3d2c22"], "skirt": ["#a8835e", "#7a5a3e", "#5a412e"],
                "trim": ["#6f9c94", "#4f7c78", "#3a5c5c"], "scarf": ["#c4473a", "#a3352d", "#7d2826"]}},
]

# 部位材质 ID：用 {0, 0.5, 1} 三档组合的纯色区分，渲染时不管有没有色彩空间换算都能可靠地还原
PARTS = ["skin", "eye", "hair", "top", "bottom", "skirt", "trim", "boots", "cape", "metal", "wood", "hat", "scarf", "gem", "shine"]
_LEVELS = [0.0, 0.5, 1.0]
_ID_RGB = [(a, b, c) for a in _LEVELS for b in _LEVELS for c in _LEVELS if (a, b, c) != (0.0, 0.0, 0.0)]


class FlatBuilder(MeshBuilder):
    """只要几何、不要贴图 UV 的 MeshBuilder；材质是按部位区分的纯色（给 ID 遍用）。"""

    def face(self, key, pts, outward=None):
        pts = [np.asarray(p, dtype=float) for p in pts]
        n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
        if np.linalg.norm(n) < 1e-12:
            return
        if outward is not None and np.dot(n, outward) < 0:
            pts = pts[::-1]
        base = len(self.verts)
        self.verts.extend(pts)
        self.faces.append((list(range(base, base + len(pts))), key, [(0.0, 0.0)] * len(pts)))

    def stack(self, key, cx, cy, rings, sides=12, sy=1.0, rot=None, cap_bottom=True, cap_top=True):
        """一串 (z, r) 圆环连成的回转体（椭圆截面，y 方向压扁 sy）。头、躯干、裙子都用它。"""
        if rot is None:
            rot = -math.pi / 2 + math.pi / sides  # 让一个面正对 -Y（脸 / 胸口是平的，五官贴得上去）
        ang = [rot + 2 * math.pi * i / sides for i in range(sides)]

        def ring(z, r):
            return [(cx + math.cos(a) * r, cy + math.sin(a) * r * sy, z) for a in ang]

        for k in range(len(rings) - 1):
            (z0, r0), (z1, r1) = rings[k], rings[k + 1]
            a, b = ring(z0, r0), ring(z1, r1)
            for i in range(sides):
                j = (i + 1) % sides
                out = (math.cos((ang[i] + ang[j]) * 0.5), math.sin((ang[i] + ang[j]) * 0.5), 0.0)
                if r1 < 1e-4:
                    self.face(key, [a[i], a[j], (cx, cy, z1)], out)
                elif r0 < 1e-4:
                    self.face(key, [(cx, cy, z0), b[j], b[i]], out)
                else:
                    self.face(key, [a[i], a[j], b[j], b[i]], out)
        if cap_bottom and rings[0][1] > 1e-4:
            self.face(key, ring(*rings[0])[::-1], (0, 0, -1))
        if cap_top and rings[-1][1] > 1e-4:
            self.face(key, ring(*rings[-1]), (0, 0, 1))

    def build_flat(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in self.verts], [], [f[0] for f in self.faces])
        for pi, (idx, key, uvs) in enumerate(self.faces):
            me.polygons[pi].material_index = self._mat_index(key)
        for key in self.mats:
            me.materials.append(_id_material(key))
        # 合并重合顶点并平滑着色：分档后是干净的明暗块，而不是一个个小平面
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        bm.to_mesh(me)
        bm.free()
        for p in me.polygons:
            p.use_smooth = True
        me.update()
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def _id_material(key):
    name = "id_" + key
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    rgb = _ID_RGB[PARTS.index(key)]
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    return m


# ---------------------------------------------------------------- 姿势

def poses():
    """待机 4 帧（呼吸）+ 走路 6 帧（一个完整步态周期）"""
    out = []
    for i in range(IDLE_FRAMES):
        out.append({"walk": None, "t": i / IDLE_FRAMES})
    for i in range(WALK_FRAMES):
        out.append({"walk": 2 * math.pi * i / WALK_FRAMES, "t": i / WALK_FRAMES})
    return out


def _dir(theta, sx=0.0):
    """竖直平面里的方向：theta = 0 朝下，正值往前（-Y）摆；sx 是向外撇的分量"""
    v = np.array([sx, -math.sin(theta), -math.cos(theta)])
    return v / np.linalg.norm(v)


# ---------------------------------------------------------------- 角色几何

def build_character(spec, pose):
    mb = FlatBuilder()
    h = spec.get("height", 1.0)
    phi = pose["walk"]
    walking = phi is not None
    if walking:
        bob = -0.045 * abs(math.sin(phi))
        breath = 0.0
        legs = []
        for side, ph in ((1, phi), (-1, phi + math.pi)):
            th = 0.42 * math.sin(ph)
            knee = 0.08 + 0.55 * max(0.0, math.cos(ph))
            legs.append((side, th, knee))
        arms = [(1, -0.45 * math.sin(phi), 0.25 + 0.25 * max(0.0, -math.sin(phi))),
                (-1, 0.45 * math.sin(phi), 0.25 + 0.25 * max(0.0, math.sin(phi)))]
        sway = 0.05 + 0.03 * abs(math.sin(phi))
    else:
        bob = 0.0
        breath = 0.006 * math.sin(2 * math.pi * pose["t"])
        legs = [(1, 0.0, 0.04), (-1, 0.0, 0.04)]
        arms = [(1, 0.04, 0.18 + breath * 4), (-1, 0.04, 0.18 + breath * 4)]
        sway = 0.02 + breath

    hip_z = 0.62 * h + bob
    sh_z = 1.04 * h + bob + breath
    head_z = 1.32 * h + bob + breath * 1.5

    # 腿：大腿 + 小腿（靴子包住下半截）+ 脚
    for side, th, kn in legs:
        hip = np.array([side * 0.085, 0.0, hip_z])
        kneep = hip + _dir(th) * 0.29 * h
        ankle = kneep + _dir(th - kn) * 0.28 * h
        mid = kneep + _dir(th - kn) * 0.12 * h
        mb.tube("bottom", hip, kneep, 0.075, 0.064, 8)
        mb.tube("bottom", kneep, mid, 0.064, 0.06, 8)
        mb.tube("boots", mid - _dir(th - kn) * 0.02, ankle, 0.068, 0.062, 8)
        heel = ankle + np.array([0.0, 0.035, -0.015])
        toe = ankle + np.array([0.0, -0.14, -0.03])
        mb.tube("boots", heel, toe, 0.058, 0.05, 6, rot=math.pi / 6)

    # 躯干：骨盆（裤）→ 腰 → 胸 → 肩
    mb.stack("bottom", 0, 0, [(hip_z - 0.07, 0.12), (hip_z + 0.02, 0.155), (hip_z + 0.08, 0.155)], 10, sy=0.8)
    mb.stack("top", 0, 0, [(hip_z + 0.08, 0.155), (hip_z + 0.2, 0.16), (sh_z - 0.12, 0.18), (sh_z - 0.02, 0.165),
                           (sh_z + 0.04, 0.09)], 10, sy=0.75)
    # 下摆 / 裙子：从腰往下张开，走路时前后摆
    sk = spec.get("skirt", 0.0) * h
    if sk > 0.01:
        flare = 0.07 + sk * 0.25
        rings = [(hip_z + 0.1, 0.162), (hip_z - 0.05, 0.175)]
        n = 4
        for i in range(1, n + 1):
            f = i / n
            rings.append((hip_z - 0.05 - sk * f, 0.175 + flare * (f ** 0.8)))
        mb.stack("skirt", 0, 0.02 * (1 if walking else 0), rings, 12, sy=0.85, cap_top=False, cap_bottom=True)
    # 腰带 + 扣
    mb.stack("trim", 0, 0, [(hip_z + 0.07, 0.168), (hip_z + 0.12, 0.168)], 10, sy=0.78)
    mb.box("metal", (-0.035, -0.142, hip_z + 0.065), (0.035, -0.125, hip_z + 0.125))
    # 脖子
    mb.tube("skin", (0, 0, sh_z), (0, 0, head_z - 0.15), 0.055, 0.05, 8)

    # 手臂：上臂（袖子）+ 前臂（长袖是衣服、短袖是皮肤）+ 手
    hands = {}
    for side, a, e in arms:
        sh = np.array([side * 0.19, 0.0, sh_z - 0.04])
        elbow = sh + _dir(a, side * 0.2) * 0.24 * h
        hand = elbow + _dir(a + e, side * 0.08) * 0.2 * h
        mb.tube("top", sh, elbow, 0.062, 0.055, 8)
        mb.tube("top" if spec.get("sleeves") == "long" else "skin", elbow, hand, 0.052, 0.046, 8)
        if spec.get("sleeves") == "long":
            mb.tube("trim", hand - _dir(a + e, side * 0.08) * 0.04, hand - _dir(a + e, side * 0.08) * 0.015, 0.056, 0.056, 8)
        mb.stack("skin", hand[0], hand[1], [(hand[2] - 0.06, 0.0), (hand[2] - 0.045, 0.04), (hand[2], 0.048), (hand[2] + 0.02, 0.03)], 8)
        hands[side] = hand

    # 头：大而圆（Q 版比例），脸正面是一个平面，眼睛贴在上面
    head = [(-0.2, 0.0), (-0.19, 0.085), (-0.15, 0.155), (-0.06, 0.2), (0.05, 0.212), (0.14, 0.192), (0.2, 0.14),
            (0.235, 0.06), (0.245, 0.0)]
    mb.stack("skin", 0, 0, [(head_z + dz, r) for dz, r in head], 12, sy=0.94)
    front = -0.2 * 0.94 * math.cos(math.pi / 12)  # 正面那个面到中心的距离（y）
    for sx in (-1, 1):
        mb.box("eye", (sx * 0.074 - 0.021, front - 0.012, head_z - 0.085), (sx * 0.074 + 0.021, front + 0.02, head_z - 0.01))
        # 眼睛高光：靠外上角一个像素的白点
        mb.box("shine", (sx * 0.074 + sx * 0.004 - 0.009, front - 0.016, head_z - 0.035), (sx * 0.074 + sx * 0.004 + 0.009, front - 0.01, head_z - 0.015))
    _hair(mb, spec, head_z, front, walking)
    _hat(mb, spec, head_z)
    if spec.get("beard"):
        mb.stack("hair", 0, -0.08, [(head_z - 0.32, 0.0), (head_z - 0.27, 0.07), (head_z - 0.17, 0.12), (head_z - 0.1, 0.13)], 10, sy=0.7)
    if spec.get("scarf"):
        mb.stack("scarf", 0, 0, [(sh_z - 0.02, 0.17), (sh_z + 0.03, 0.15), (sh_z + 0.07, 0.1)], 10, sy=0.8)
        mb.box("scarf", (0.04, -0.17, sh_z - 0.24), (0.11, -0.13, sh_z))

    # 披风：从肩后垂下，走路时下摆往后飘
    if spec.get("cape"):
        top_y = 0.1
        bot_y = 0.16 + sway * 2.5
        zb = hip_z - 0.3 * h
        pts = [(-0.2, top_y, sh_z + 0.02), (0.2, top_y, sh_z + 0.02), (0.28, bot_y, zb), (-0.28, bot_y, zb)]
        mb.face("cape", pts, (0, 1, 0))
        mb.face("cape", [(x, y - 0.012, z) for (x, y, z) in pts][::-1], (0, -1, 0))
        mb.stack("cape", 0, 0.02, [(sh_z - 0.02, 0.19), (sh_z + 0.05, 0.12)], 10, sy=0.85, cap_top=False)

    # 武器 / 道具
    w = spec.get("weapon")
    if w == "sword":  # 左腰挂剑：剑鞘斜向后下，剑柄和护手在前上
        p0 = np.array([0.2, -0.05, hip_z + 0.05])
        p1 = p0 + np.array([0.04, 0.36, -0.42])
        mb.tube("trim", p0, p1, 0.035, 0.03, 6)
        mb.tube("metal", p0 + np.array([0.0, -0.01, 0.0]), p0 + np.array([0.0, -0.08, 0.08]), 0.02, 0.02, 6)
        mb.box("metal", (0.17, -0.06, hip_z + 0.04), (0.23, -0.03, hip_z + 0.07))
    elif w == "bag":
        mb.box("wood", (0.17, -0.08, hip_z - 0.12), (0.27, 0.12, hip_z + 0.06))
        mb.tube("wood", (0.2, -0.05, hip_z + 0.06), (-0.12, -0.1, sh_z + 0.02), 0.015, 0.015, 4)
    elif w in ("staff", "spear", "cane"):
        hd = hands[-1]
        top = {"staff": 0.8, "spear": 1.05, "cane": 0.15}[w] * h
        bot = np.array([hd[0], hd[1] - 0.02, 0.02 if w != "spear" else 0.05])
        tp = np.array([hd[0], hd[1] - 0.02, hd[2] + top])
        mb.tube("wood", bot, tp, 0.022, 0.022, 6)
        if w == "staff":
            mb.stack("gem", tp[0], tp[1], [(tp[2] - 0.02, 0.0), (tp[2] + 0.04, 0.05), (tp[2] + 0.1, 0.0)], 6, rot=0.0)
            mb.tube("trim", tp - np.array([0, 0, 0.06]), tp + np.array([0, 0, 0.01]), 0.035, 0.035, 6)
        elif w == "spear":
            mb.tube("metal", tp, tp + np.array([0, 0, 0.2]), 0.035, 0.0, 4)
            mb.tube("trim", tp - np.array([0, 0, 0.04]), tp + np.array([0, 0, 0.01]), 0.03, 0.03, 6)
        else:
            mb.tube("wood", tp, tp + np.array([0, -0.08, 0.0]), 0.022, 0.022, 6)
    return mb


def _hair(mb, spec, hz, front, walking):
    style = spec.get("hair", "short")
    if style == "bald":
        # 只剩两侧和后脑一圈短发
        mb.stack("hair", 0, 0.04, [(hz - 0.1, 0.17), (hz - 0.02, 0.2), (hz + 0.05, 0.195)], 12, sy=0.94)
        return
    # 头顶的发壳（比头大一圈，盖住额头上半）+ 后脑一大团（前半截藏在脸里，只有后面露出来）
    # 戴头盔时不做发壳（和头盔贴得太近会互相穿插出条纹），只留盔下露出的后脑头发
    helmet = spec.get("hat") == "helmet"
    if not helmet:
        mb.stack("hair", 0, 0.01, [(hz + 0.03, 0.222), (hz + 0.08, 0.226), (hz + 0.16, 0.205), (hz + 0.22, 0.155),
                                   (hz + 0.26, 0.07), (hz + 0.27, 0.0)], 12, sy=0.97, cap_bottom=False)
    mb.stack("hair", 0, 0.05, [(hz - 0.17, 0.12), (hz - 0.1, 0.19), (hz + 0.02, 0.21), (hz + 0.1, 0.18)], 12, sy=0.94)
    # 刘海：额前几缕（三角形发束）
    for i, x in enumerate(() if helmet else (-0.12, -0.04, 0.05, 0.13)):
        ln = 0.035 + 0.025 * ((i * 7) % 3) / 2
        mb.face("hair", [(x - 0.05, front - 0.018, hz + 0.065), (x + 0.05, front - 0.018, hz + 0.065),
                         (x + 0.01, front - 0.022, hz + 0.065 - ln)], (0, -1, 0))
    if helmet:
        return
    if style == "spiky":
        for k in range(7):
            a = -0.9 + k * 0.3
            base = np.array([math.sin(a) * 0.12, 0.06 + 0.04 * abs(math.cos(a)), hz + 0.2])
            tip = base + np.array([math.sin(a) * 0.12, 0.1, 0.1 - abs(a) * 0.05])
            mb.tube("hair", base, tip, 0.06, 0.0, 5)
    elif style == "long":
        mb.stack("hair", 0, 0.07, [(hz - 0.5, 0.0), (hz - 0.46, 0.17), (hz - 0.3, 0.2), (hz - 0.1, 0.205), (hz + 0.05, 0.2)],
                 12, sy=0.85)
        for sx in (-1, 1):  # 两侧垂下的鬓发
            mb.tube("hair", (sx * 0.19, -0.06, hz + 0.02), (sx * 0.2, -0.05, hz - 0.3), 0.04, 0.025, 6)
    elif style == "ponytail":
        swing = 0.04 if walking else 0.0
        mb.tube("trim", (0, 0.2, hz + 0.02), (0, 0.23, hz - 0.02), 0.045, 0.045, 6)
        mb.tube("hair", (0, 0.22, hz - 0.0), (0, 0.3 + swing, hz - 0.38), 0.06, 0.02, 8)


def _hat(mb, spec, hz):
    hat = spec.get("hat")
    if hat == "wide":
        mb.stack("hat", 0, 0.01, [(hz + 0.13, 0.36), (hz + 0.16, 0.34)], 14, sy=0.95)
        mb.stack("hat", 0, 0.01, [(hz + 0.15, 0.2), (hz + 0.32, 0.17), (hz + 0.35, 0.0)], 12, sy=0.95)
        mb.stack("trim", 0, 0.01, [(hz + 0.16, 0.205), (hz + 0.2, 0.2)], 12, sy=0.95)
    elif hat == "helmet":
        mb.stack("metal", 0, 0.0, [(hz - 0.02, 0.232), (hz + 0.1, 0.235), (hz + 0.2, 0.19), (hz + 0.27, 0.08), (hz + 0.3, 0.0)],
                 12, sy=0.97, cap_bottom=False)
        mb.box("metal", (-0.02, -0.25, hz - 0.1), (0.02, -0.2, hz + 0.05))  # 护鼻
        mb.tube("trim", (0, 0, hz + 0.28), (0, 0.05, hz + 0.38), 0.03, 0.0, 6)


# ---------------------------------------------------------------- 渲染

def _setup_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x = FRAME * SS
    sc.render.resolution_y = FRAME * SS
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.display.render_aa = "OFF"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sh = sc.display.shading
    sh.show_cavity = False
    sh.show_shadows = False
    sh.show_object_outline = False
    sh.show_specular_highlight = False
    sh.use_dof = False
    cam_data = bpy.data.cameras.new("pw_sprite_cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = FRAME / PX_PER_M
    cam = bpy.data.objects.new("pw_sprite_cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def _place_camera(cam, d):
    from mathutils import Vector
    th = -math.pi / 2 + d * math.pi / 4
    target = Vector((0.0, 0.0, TARGET_Z))
    off = Vector((math.cos(th) * math.cos(ELEV), math.sin(th) * math.cos(ELEV), math.sin(ELEV))) * 10.0
    cam.location = target + off
    cam.rotation_euler = (-off).to_track_quat("-Z", "Y").to_euler()


def _render(path, flat):
    sc = bpy.context.scene
    sh = sc.display.shading
    if flat:
        sh.light = "FLAT"
        sh.color_type = "MATERIAL"
    else:
        sh.light = "MATCAP"
        sh.studio_light = "check_normal+y.exr"
        sh.color_type = "SINGLE"
        sh.single_color = (1.0, 1.0, 1.0)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    w, hgt = img.size
    buf = np.empty(w * hgt * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    return buf.reshape(hgt, w, 4)[::-1]  # 第 0 行在顶部


def _compose(idimg, nrm, ramps):
    """两遍渲染 → 一帧像素画（FRAME×FRAME，RGBA 0..1）"""
    n = FRAME
    a = idimg[..., 3] > 0.5
    q = np.rint(np.clip(idimg[..., :3], 0, 1) * 2) / 2  # 每个通道归到 0 / 0.5 / 1
    q[(idimg[..., :3] > 0.15) & (idimg[..., :3] < 0.85)] = 0.5
    q[idimg[..., :3] >= 0.85] = 1.0
    q[idimg[..., :3] <= 0.15] = 0.0
    k = len(PARTS)
    ids = np.full(a.shape, -1, dtype=np.int32)
    for i in range(k):
        r, g, b = _ID_RGB[i]
        m = a & (q[..., 0] == r) & (q[..., 1] == g) & (q[..., 2] == b)
        ids[m] = i
    a = ids >= 0
    # 2×2 合并：不透明像素数 ≥ 2 才算不透明；部位取多数；亮度取不透明像素的平均
    blk = a.reshape(n, SS, n, SS)
    cnt = blk.sum(axis=(1, 3))
    alpha = cnt >= (SS * SS) // 2
    votes = np.zeros((n, n, k), dtype=np.int32)
    for i in range(k):
        votes[..., i] = (ids == i).reshape(n, SS, n, SS).sum(axis=(1, 3))
    pid = votes.argmax(axis=2)
    nv = nrm[..., :3] * 2.0 - 1.0
    lum = np.clip((nv * LIGHT_DIR).sum(axis=2), -1.0, 1.0)
    lsum = (lum * a).reshape(n, SS, n, SS).sum(axis=(1, 3))
    lm = lsum / np.maximum(cnt, 1)
    tone = np.where(lm > TONE_HI, 0, np.where(lm > TONE_MID, 1, 2))
    tone[pid == PARTS.index("eye")] = 1
    out = np.zeros((n, n, 4))
    pal = np.zeros((k, 3, 3))
    for i, key in enumerate(PARTS):
        pal[i] = ramps[key]
    out[..., :3] = pal[pid, tone]
    out[..., 3] = alpha
    # 外描边：透明像素只要上下左右挨着角色，就涂成相邻部位最深色再压暗一半
    edge_col = np.zeros((n, n, 3))
    edge = np.zeros((n, n), dtype=bool)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        na = np.roll(np.roll(alpha, dy, 0), dx, 1)
        npid = np.roll(np.roll(pid, dy, 0), dx, 1)
        m = ~alpha & na & ~edge
        edge_col[m] = pal[npid[m], 2] * 0.45 + INK * 0.55
        edge |= m
    out[edge, :3] = edge_col[edge]
    out[edge, 3] = 1.0
    return out


def _ramps(spec):
    r = {}
    for key in PARTS:
        cols = spec.get("colors", {}).get(key) or BASE_COLORS.get(key)
        if cols is None:  # 没指定的部位借用相近的颜色
            cols = spec["colors"].get({"hat": "hair", "scarf": "trim", "cape": "top", "skirt": "top"}.get(key, "top"))
        r[key] = np.array([_hex(c) for c in cols])
    return r


def render_sheet(spec, out_png, tmpdir):
    cam = _setup_scene()
    ramps = _ramps(spec)
    ps = poses()
    sheet = np.zeros((DIRS * FRAME, len(ps) * FRAME, 4), dtype=np.float32)
    for col, pose in enumerate(ps):
        obj = build_character(spec, pose).build_flat("pw_char_%s_%d" % (spec["id"], col))
        for d in range(DIRS):
            _place_camera(cam, d)
            idimg = _render(os.path.join(tmpdir, "id.png"), True)
            nrm = _render(os.path.join(tmpdir, "nrm.png"), False)
            sheet[d * FRAME:(d + 1) * FRAME, col * FRAME:(col + 1) * FRAME] = _compose(idimg, nrm, ramps)
        me = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(me)
    h, w = sheet.shape[:2]
    img = bpy.data.images.new("pw_sheet_" + spec["id"], width=w, height=h, alpha=True)
    img.pixels.foreach_set(sheet[::-1].ravel())
    img.filepath_raw = str(out_png)
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def build_all(out_dir, only=None):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="pw_sprites_")
    chars = []
    for spec in PRESETS:
        if only and spec["id"] not in only:
            continue
        fn = "%s.png" % spec["id"]
        render_sheet(spec, out / fn, tmp)
        chars.append({"id": spec["id"], "name": spec["name"], "desc": spec["desc"], "file": fn})
        print("  角色 %-10s %s" % (spec["id"], spec["name"]))
    origin_y = FRAME / 2 + TARGET_Z * math.cos(ELEV) * PX_PER_M
    cat = {
        "version": 1, "generator": "pixel_world_blender sprites %s" % VERSION, "blender": bpy.app.version_string,
        "frame": FRAME, "px_per_m": PX_PER_M, "origin": [FRAME / 2, round(origin_y, 2)], "dirs": DIRS,
        "dir_order": "第 d 行 = 相机从角色正面逆时针（俯视）转 d×45°",
        "anims": {"idle": {"start": 0, "count": IDLE_FRAMES, "fps": 4},
                  "walk": {"start": IDLE_FRAMES, "count": WALK_FRAMES, "fps": 10}},
        "characters": chars,
    }
    if only:  # 只重做了部分角色：保留目录里其他角色的条目
        old = out / "catalog.json"
        if old.exists():
            prev = json.loads(old.read_text(encoding="utf-8"))
            keep = [c for c in prev.get("characters", []) if c["id"] not in only]
            cat["characters"] = keep + chars
    (out / "catalog.json").write_text(json.dumps(cat, ensure_ascii=False, indent=2), encoding="utf-8")
    return cat
