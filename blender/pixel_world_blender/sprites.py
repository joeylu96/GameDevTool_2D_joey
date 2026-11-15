"""HD-2D 像素角色（P4）：在 Blender 里用参数搭一个 Q 版低模角色（约 3.5 头身），按动作逐帧摆姿势，
从 8 个方向用正交相机渲染，再在 numpy 里做成像素画，每个动作拼成一张精灵表交给 Godot。

做法（每一帧、每个方向渲染两遍，都用 Workbench，快且稳定）：
  1. 材质 ID 遍：平光 + 每个部位一种纯色 → 每个像素属于哪个部位（皮肤、头发、上衣……）
  2. 法线遍：matcap「check_normal+y」把每个像素的法线编码成颜色，再用固定的左上主光算明暗
  合成：按明暗分三档，从这个部位的三色色阶里取色（赛璐璐式的硬分档，像手绘像素画），
  再在轮廓外描 1 像素的深色描边（用相邻部位最深的颜色压暗，不是死黑，看起来更细腻）。
  渲染时用 2 倍分辨率，再 2×2 合并（部位取多数、明暗取平均），边缘更干净、没有锯齿噪点。

角色规格、姿势和动作的定义在 blender/pw_specs/（纯 Python，生成服务也用同一份做校验）。
尺寸：每帧 128×128 像素，角色约 96 像素高（60 像素 / 米）——比同类 HD-2D 游戏的角色更精细。
坐标约定：Blender Z 向上，角色正面朝 -Y，+X 是角色自己的左手边。第 d 行方向 = 相机从角色正面逆时针（俯视）转 d×45°。
输出：<输出目录>/<角色 id>/<动作>.png（8 行方向 × N 帧）+ <输出目录>/catalog.json。
"""
import json
import math
import os
import sys
import tempfile
from pathlib import Path

import bmesh
import bpy
import numpy as np

from .builder import MeshBuilder

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # blender/：让 pw_specs 可以导入
from pw_specs import charspec, poses  # noqa: E402

VERSION = "0.3.0"
# 全像素风：精灵和场景同一个像素密度（场景贴图 32 texel/米），用和游戏镜头一样的 40° 俯角渲染。
# Godot 里公告板是竖直的，竖向拉长 1/cos(40°)，从 40° 俯视看过去正好还原、像素和屏幕像素一一对应。
FRAME = 80
SS = 2
PX_PER_M = 32.0
ELEV = math.radians(40.0)
TARGET_Z = 1.0

# 身体比例（身高系数 h = 1 时约 1.72 米、6 头身）。资产工坊动作编辑器（tools/workshop/index.html aeJoints）用同一组数
HIP_Z = 0.86
SH_Z = 1.38
HEAD_UP = 0.285     # 头部中心比肩高多少（缩放前；头的轮廓从中心往下 0.2 是下巴）
HEAD_SCALE = 0.62   # 头（连同头发、帽子、眼睛）以下巴为中心缩放
THIGH = 0.42
SHIN = 0.40
UPPER_ARM = 0.30
FORE_ARM = 0.26
DIRS = 8
INK = np.array([0x1d, 0x20, 0x30]) / 255.0

# 光照：法线遍解码后自己算，主光从左上前方照来（所有方向的帧光照一致，不会转个身就变暗）。
LIGHT_DIR = np.array([-0.5, 0.62, 0.6]) / np.linalg.norm([-0.5, 0.62, 0.6])
TONE_HI = 0.62
TONE_MID = 0.18

PARTS = charspec.PARTS
PRESETS = charspec.PRESETS
# 部位材质 ID：用 {0, 0.5, 1} 三档组合的纯色区分，渲染时不管有没有色彩空间换算都能可靠地还原
_LEVELS = [0.0, 0.5, 1.0]
_ID_RGB = [(a, b, c) for a in _LEVELS for b in _LEVELS for c in _LEVELS if (a, b, c) != (0.0, 0.0, 0.0)]
_FLAT_TONE = {"eye": 1, "glow": 0, "shine": 0}  # 这些部位不分明暗


def _hex(h):
    return np.array(charspec.hex_to_rgb(h))


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

    def rotate(self, start, end, axis, angle, pivot):
        """把 [start, end) 这段顶点绕 pivot、沿坐标轴 axis（"x" / "z"）旋转 angle 弧度"""
        if abs(angle) < 1e-6:
            return
        c, s = math.cos(angle), math.sin(angle)
        p = np.asarray(pivot, dtype=float)
        for i in range(start, end):
            v = self.verts[i] - p
            if axis == "x":
                v = np.array([v[0], v[1] * c - v[2] * s, v[1] * s + v[2] * c])
            else:
                v = np.array([v[0] * c - v[1] * s, v[0] * s + v[1] * c, v[2]])
            self.verts[i] = v + p

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


def _dir(theta, sx=0.0):
    """竖直平面里的方向：theta = 0 朝下，正值往前（-Y）摆；sx 是向外撇的分量"""
    v = np.array([sx, -math.sin(theta), -math.cos(theta)])
    return v / np.linalg.norm(v)


# ---------------------------------------------------------------- 角色几何

def build_character(spec, pose):
    """按规格和姿势搭出一帧的角色。先搭下半身（不随上身转），再搭上半身和头，最后整体做头部转动、上身扭转和前倾。"""
    mb = FlatBuilder()
    h = spec.get("height", 1.0)
    bw = spec.get("build", 1.0)
    bob, breath = pose["bob"], pose["breath"]
    hip_z = HIP_Z * h + bob
    sh_z = SH_Z * h + bob + breath
    head_z = sh_z + HEAD_UP + breath * 0.5
    weapon = spec.get("weapon")
    in_hand = pose.get("weapon") == "hand"

    # ---- 下半身：腿、骨盆、裙摆、腰带、挂在腰上的武器
    for side, key in ((1, "leg_l"), (-1, "leg_r")):
        th, kn = pose[key]
        hip = np.array([side * 0.085 * bw, 0.0, hip_z])
        kneep = hip + _dir(th) * THIGH * h
        ankle = kneep + _dir(th - kn) * SHIN * h
        mid = kneep + _dir(th - kn) * 0.17 * h
        mb.tube("bottom", hip, kneep, 0.075 * bw, 0.064 * bw, 8)
        mb.tube("bottom", kneep, mid, 0.064 * bw, 0.06 * bw, 8)
        mb.tube("boots", mid - _dir(th - kn) * 0.02, ankle, 0.068 * bw, 0.062 * bw, 8)
        foot = _dir(th - kn + math.pi / 2)  # 脚背方向：垂直于小腿向前
        mb.tube("boots", ankle - foot * 0.04 + np.array([0, 0, -0.012]), ankle + foot * 0.13 + np.array([0, 0, -0.03]),
                0.058, 0.05, 6, rot=math.pi / 6)
    mb.stack("bottom", 0, 0, [(hip_z - 0.07, 0.12 * bw), (hip_z + 0.02, 0.155 * bw), (hip_z + 0.08, 0.155 * bw)], 10, sy=0.8)
    sk = spec.get("skirt", 0.0) * h
    if sk > 0.01:
        flare = 0.07 + sk * 0.25
        rings = [(hip_z + 0.1, 0.162 * bw), (hip_z - 0.05, 0.175 * bw)]
        for i in range(1, 5):
            f = i / 4
            rings.append((hip_z - 0.05 - sk * f, 0.175 * bw + flare * (f ** 0.8)))
        # 下摆跟着腿的动作往前 / 后摆一点
        swing = (pose["leg_l"][0] + pose["leg_r"][0]) * -0.05
        mb.stack("skirt", 0, swing + pose["cape"] * 0.02, rings, 12, sy=0.85, cap_top=False, cap_bottom=True)
    mb.stack("trim", 0, 0, [(hip_z + 0.07, 0.168 * bw), (hip_z + 0.12, 0.168 * bw)], 10, sy=0.78)
    mb.box("metal", (-0.035, -0.142 * bw, hip_z + 0.065), (0.035, -0.125 * bw, hip_z + 0.125))
    if not in_hand:
        if weapon == "sword":  # 左腰挂剑：剑鞘斜向后下，剑柄和护手在前上
            p0 = np.array([0.2 * bw, -0.05, hip_z + 0.05])
            mb.tube("trim", p0, p0 + np.array([0.04, 0.36, -0.42]), 0.035, 0.03, 6)
            mb.tube("metal", p0 + np.array([0.0, -0.01, 0.0]), p0 + np.array([0.0, -0.08, 0.08]), 0.02, 0.02, 6)
            mb.box("metal", (0.17 * bw, -0.06, hip_z + 0.04), (0.23 * bw, -0.03, hip_z + 0.07))
        elif weapon == "axe":  # 右腰挂斧：斧柄朝下
            p0 = np.array([-0.2 * bw, -0.02, hip_z + 0.08])
            mb.tube("wood", p0, p0 + np.array([-0.03, 0.05, -0.45]), 0.022, 0.022, 6)
            mb.box("metal", (-0.24 * bw - 0.03, -0.1, hip_z + 0.0), (-0.24 * bw + 0.01, 0.04, hip_z + 0.14))
    if weapon == "bag":
        mb.box("wood", (0.17 * bw, -0.08, hip_z - 0.12), (0.27 * bw, 0.12, hip_z + 0.06))
    lower_end = len(mb.verts)

    # ---- 上半身：躯干、背心、脖子、手臂、围巾、披风、手上的武器
    mb.stack("top", 0, 0, [(hip_z + 0.08, 0.155 * bw), (hip_z + 0.2, 0.16 * bw), (sh_z - 0.12, 0.18 * bw),
                           (sh_z - 0.02, 0.165 * bw), (sh_z + 0.04, 0.09)], 10, sy=0.75)
    if spec.get("vest"):  # 背心 / 皮甲：比上衣大一圈，两条肩带
        mb.stack("vest", 0, 0, [(hip_z + 0.1, 0.168 * bw), (hip_z + 0.22, 0.172 * bw), (sh_z - 0.12, 0.192 * bw),
                                (sh_z - 0.04, 0.175 * bw)], 10, sy=0.77, cap_bottom=False, cap_top=False)
        for sx in (-1, 1):
            mb.box("metal", (sx * 0.1 * bw - 0.025, -0.14 * bw, sh_z - 0.08), (sx * 0.1 * bw + 0.025, -0.125 * bw, sh_z - 0.04))
    mb.tube("skin", (0, 0, sh_z), (0, 0, head_z - 0.15), 0.055, 0.05, 8)
    hands = {}
    fore_dirs = {}
    for side, key in ((1, "arm_l"), (-1, "arm_r")):
        a, e, spread = pose[key]
        sh = np.array([side * 0.19 * bw, 0.0, sh_z - 0.04])
        elbow = sh + _dir(a, side * (0.05 + spread)) * UPPER_ARM * h
        d2 = _dir(a + e, side * (0.02 + spread * 0.4))
        hand = elbow + d2 * FORE_ARM * h
        mb.tube("top", sh, elbow, 0.062 * bw, 0.055 * bw, 8)
        if spec.get("sleeve_band"):
            d1 = (elbow - sh) / np.linalg.norm(elbow - sh)
            mb.tube("band", sh + d1 * 0.15, sh + d1 * 0.22, 0.066 * bw, 0.062 * bw, 8)
        long_sleeve = spec.get("sleeves") == "long"
        mb.tube("top" if long_sleeve else "skin", elbow, hand, 0.052 * bw, 0.046 * bw, 8)
        if long_sleeve:
            mb.tube("trim", hand - d2 * 0.04, hand - d2 * 0.015, 0.056 * bw, 0.056 * bw, 8)
        mb.stack("skin", hand[0], hand[1], [(hand[2] - 0.06, 0.0), (hand[2] - 0.045, 0.04), (hand[2], 0.048),
                                            (hand[2] + 0.02, 0.03)], 8)
        hands[side] = hand
        fore_dirs[side] = d2
        g = pose.get("hand_glow", 0.0)
        if g > 0.05:
            r = 0.04 + 0.07 * g
            c = hand + d2 * 0.05
            mb.stack("glow", c[0], c[1], [(c[2] - r, 0.0), (c[2] - r * 0.5, r * 0.85), (c[2] + r * 0.5, r * 0.85), (c[2] + r, 0.0)], 8)
    if spec.get("scarf"):
        mb.stack("scarf", 0, 0, [(sh_z - 0.03, 0.17 * bw), (sh_z + 0.01, 0.145 * bw), (sh_z + 0.04, 0.085)], 10, sy=0.8)
        mb.box("scarf", (0.04, -0.17 * bw, sh_z - 0.24), (0.11, -0.13 * bw, sh_z))
    if spec.get("cape"):
        top_y = 0.1
        bot_y = 0.18 + pose["cape"] * 0.3
        zb = hip_z - 0.3 * h + pose["cape"] * 0.12
        pts = [(-0.2 * bw, top_y, sh_z + 0.02), (0.2 * bw, top_y, sh_z + 0.02), (0.28 * bw, bot_y, zb), (-0.28 * bw, bot_y, zb)]
        mb.face("cape", pts, (0, 1, 0))
        mb.face("cape", [(x, y - 0.012, z) for (x, y, z) in pts][::-1], (0, -1, 0))
        mb.stack("cape", 0, 0.02, [(sh_z - 0.02, 0.19 * bw), (sh_z + 0.05, 0.12)], 10, sy=0.85, cap_top=False)
    if weapon == "greatsword" and not in_hand:  # 大剑斜背在背上
        p0 = np.array([0.22, 0.17, hip_z - 0.05])
        p1 = np.array([-0.25, 0.17, sh_z + 0.32])
        mb.tube("metal", p0, p1, 0.045, 0.04, 4, rot=math.pi / 4)
        mb.tube("trim", p1, p1 + (p1 - p0) / np.linalg.norm(p1 - p0) * 0.18, 0.025, 0.025, 6)
    _weapon_in_hand(mb, spec, pose, hands[-1], fore_dirs[-1], in_hand, h)
    head_start = len(mb.verts)

    # ---- 头：先按原尺寸搭（脸正面是一个平面，眼睛贴在上面），最后整体以下巴为中心缩到 HEAD_SCALE
    head = [(-0.2, 0.0), (-0.19, 0.085), (-0.15, 0.155), (-0.06, 0.2), (0.05, 0.212), (0.14, 0.192), (0.2, 0.14),
            (0.235, 0.06), (0.245, 0.0)]
    mb.stack("skin", 0, 0, [(head_z + dz, r) for dz, r in head], 12, sy=0.94)
    front = -0.2 * 0.94 * math.cos(math.pi / 12)  # 正面那个面到中心的距离（y）
    for sx in (-1, 1):
        # 眼睛：缩放后约 1~2 个像素（像素画里眼睛就是两个小点；太小的高光点不画）
        mb.box("eye", (sx * 0.08 - 0.034, front - 0.012, head_z - 0.1), (sx * 0.08 + 0.034, front + 0.02, head_z - 0.01))
    _hair(mb, spec, head_z, front, pose)
    _hat(mb, spec, head_z, front)
    if spec.get("beard"):
        # 山羊胡：只在下巴前面一小撮（太大会把整张脸盖住）
        mb.stack("hair", 0, -0.115, [(head_z - 0.29, 0.0), (head_z - 0.25, 0.05), (head_z - 0.19, 0.075), (head_z - 0.15, 0.06)], 8, sy=0.7)
        mb.box("hair", (-0.055, front - 0.012, head_z - 0.15), (0.055, front + 0.02, head_z - 0.125))  # 上唇胡
    end = len(mb.verts)
    chin = np.array([0.0, 0.0, head_z - 0.2])
    for i in range(head_start, end):
        mb.verts[i] = tuple(chin + (np.array(mb.verts[i]) - chin) * HEAD_SCALE)

    # ---- 姿势变换：头（绕脖子），再整个上半身（扭转 + 前倾，绕腰）
    neck = (0.0, 0.0, chin[2] + 0.02 * HEAD_SCALE)
    mb.rotate(head_start, end, "x", pose["head"][0], neck)
    mb.rotate(head_start, end, "z", pose["head"][1], neck)
    mb.rotate(lower_end, end, "z", pose["twist"], (0.0, 0.0, 0.0))
    mb.rotate(lower_end, end, "x", pose["lean"], (0.0, 0.0, hip_z + 0.08))
    return mb


def _weapon_in_hand(mb, spec, pose, hand, d2, in_hand, h):
    w = spec.get("weapon")
    if w is None or w == "bag":
        return
    if not in_hand:
        if w in ("staff", "spear", "cane"):  # 平时竖着拿在右手
            top = {"staff": 0.8, "spear": 1.05, "cane": 0.15}[w] * h
            bot = np.array([hand[0], hand[1] - 0.02, 0.02 if w != "spear" else 0.05])
            tp = np.array([hand[0], hand[1] - 0.02, hand[2] + top])
            mb.tube("wood", bot, tp, 0.022, 0.022, 6)
            _shaft_tip(mb, w, tp, np.array([0.0, 0.0, 1.0]))
        return
    # 握在手里：沿前臂方向再往前转 weapon_angle
    wa = pose.get("weapon_angle", 0.0)
    ang = math.atan2(-d2[1], -d2[2]) + wa  # 前臂在竖直平面里的角度，再加 weapon_angle
    d = np.array([d2[0] * 0.5, -math.sin(ang), -math.cos(ang)])
    d /= np.linalg.norm(d)
    if w in ("sword", "greatsword"):
        ln = 0.75 if w == "sword" else 1.05
        rr = 0.028 if w == "sword" else 0.04
        mb.tube("trim", hand - d * 0.07, hand + d * 0.06, 0.022, 0.022, 6)               # 剑柄
        side = np.cross(d, np.array([0.0, 0.0, 1.0]) if abs(d[2]) < 0.9 else np.array([1.0, 0.0, 0.0]))
        side /= np.linalg.norm(side)
        g = hand + d * 0.07
        mb.tube("metal", g - side * 0.09, g + side * 0.09, 0.02, 0.02, 4)                   # 护手
        mb.tube("metal", hand + d * 0.08, hand + d * (0.08 + ln), rr, rr * 0.8, 4, rot=math.pi / 4)  # 剑身
        mb.tube("metal", hand + d * (0.08 + ln), hand + d * (0.2 + ln), rr * 0.8, 0.0, 4, rot=math.pi / 4)
    elif w == "axe":
        mb.tube("wood", hand - d * 0.1, hand + d * 0.5, 0.022, 0.022, 6)
        tip = hand + d * 0.45
        side = np.cross(d, np.array([1.0, 0.0, 0.0]))
        side /= max(1e-6, np.linalg.norm(side))
        mb.tube("metal", tip, tip + side * 0.16, 0.06, 0.03, 4)
    else:  # 杖 / 枪 / 拐杖：手握在杆子三分之一处
        below = {"staff": 0.45, "spear": 0.5, "cane": 0.6}[w]
        above = {"staff": 0.8, "spear": 1.0, "cane": 0.15}[w]
        mb.tube("wood", hand - d * below, hand + d * above, 0.022, 0.022, 6)
        _shaft_tip(mb, w, hand + d * above, d)


def _shaft_tip(mb, w, tp, d):
    if w == "staff":
        c = tp + d * 0.05
        mb.stack("gem", c[0], c[1], [(c[2] - 0.05, 0.0), (c[2], 0.05), (c[2] + 0.06, 0.0)], 6, rot=0.0)
        mb.tube("trim", tp - d * 0.06, tp + d * 0.01, 0.035, 0.035, 6)
    elif w == "spear":
        mb.tube("metal", tp, tp + d * 0.2, 0.035, 0.0, 4)
        mb.tube("trim", tp - d * 0.04, tp + d * 0.01, 0.03, 0.03, 6)
    elif w == "cane":
        mb.tube("wood", tp, tp + np.array([0, -0.08, 0.0]), 0.022, 0.022, 6)


def _hair(mb, spec, hz, front, pose):
    style = spec.get("hair", "short")
    hat = spec.get("hat")
    if style == "bald":
        # 只剩两侧和后脑一圈短发
        mb.stack("hair", 0, 0.04, [(hz - 0.1, 0.17), (hz - 0.02, 0.2), (hz + 0.05, 0.195)], 12, sy=0.94)
        return
    # 头顶的发壳（比头大一圈，盖住额头上半）+ 后脑一大团（前半截藏在脸里，只有后面露出来）
    # 戴头盔 / 兜帽时不做发壳（贴得太近会互相穿插出条纹），只留露出来的后脑头发
    covered = hat in ("helmet", "hood")
    if not covered:
        mb.stack("hair", 0, 0.01, [(hz + 0.03, 0.222), (hz + 0.08, 0.226), (hz + 0.16, 0.205), (hz + 0.22, 0.155),
                                   (hz + 0.26, 0.07), (hz + 0.27, 0.0)], 12, sy=0.97, cap_bottom=False)
    mb.stack("hair", 0, 0.05, [(hz - 0.17, 0.12), (hz - 0.1, 0.19), (hz + 0.02, 0.21), (hz + 0.1, 0.18)], 12, sy=0.94)
    # 刘海：额前几缕（三角形发束）
    for i, x in enumerate(() if covered else (-0.12, -0.04, 0.05, 0.13)):
        ln = 0.035 + 0.025 * ((i * 7) % 3) / 2
        mb.face("hair", [(x - 0.05, front - 0.018, hz + 0.065), (x + 0.05, front - 0.018, hz + 0.065),
                         (x + 0.01, front - 0.022, hz + 0.065 - ln)], (0, -1, 0))
    if covered:
        return
    flow = pose.get("cape", 0.1)
    if style == "spiky":
        for k in range(7):
            a = -0.9 + k * 0.3
            base = np.array([math.sin(a) * 0.12, 0.06 + 0.04 * abs(math.cos(a)), hz + 0.2])
            tip = base + np.array([math.sin(a) * 0.12, 0.1 + flow * 0.04, 0.1 - abs(a) * 0.05])
            mb.tube("hair", base, tip, 0.06, 0.0, 5)
    elif style == "long":
        back = 0.07 + flow * 0.05
        mb.stack("hair", 0, back, [(hz - 0.5, 0.0), (hz - 0.46, 0.17), (hz - 0.3, 0.2), (hz - 0.1, 0.205), (hz + 0.05, 0.2)],
                 12, sy=0.85)
        for sx in (-1, 1):  # 两侧垂下的鬓发
            mb.tube("hair", (sx * 0.19, -0.06, hz + 0.02), (sx * 0.2, -0.05, hz - 0.3), 0.04, 0.025, 6)
    elif style == "ponytail":
        mb.tube("trim", (0, 0.2, hz + 0.02), (0, 0.23, hz - 0.02), 0.045, 0.045, 6)
        mb.tube("hair", (0, 0.22, hz - 0.0), (0, 0.3 + flow * 0.15, hz - 0.38 + flow * 0.1), 0.06, 0.02, 8)
    elif style == "bun":
        mb.stack("hair", 0, 0.14, [(hz + 0.08, 0.0), (hz + 0.12, 0.08), (hz + 0.2, 0.085), (hz + 0.26, 0.0)], 10)


def _hat(mb, spec, hz, front):
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
    elif hat == "hood":  # 兜帽：盖住头顶和后脑，脸露出来；后面垂到肩上
        mb.stack("hat", 0, 0.015, [(hz - 0.0, 0.236), (hz + 0.1, 0.24), (hz + 0.2, 0.2), (hz + 0.27, 0.1), (hz + 0.3, 0.0)],
                 12, sy=0.98, cap_bottom=False)
        mb.stack("hat", 0, 0.08, [(hz - 0.3, 0.2), (hz - 0.18, 0.2), (hz - 0.02, 0.22)], 12, sy=0.8, cap_bottom=True, cap_top=False)
    elif hat == "cap":  # 小布帽 + 帽檐
        mb.stack("hat", 0, 0.01, [(hz + 0.07, 0.228), (hz + 0.16, 0.215), (hz + 0.23, 0.15), (hz + 0.27, 0.0)], 12, sy=0.97)
        mb.box("hat", (-0.13, front - 0.11, hz + 0.07), (0.13, front + 0.02, hz + 0.095))


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


def _compose(idimg, nrm, pal):
    """两遍渲染 → 一帧像素画（FRAME×FRAME，RGBA 0..1）"""
    n = FRAME
    k = len(PARTS)
    q = np.where(idimg[..., :3] >= 0.85, 1.0, np.where(idimg[..., :3] <= 0.15, 0.0, 0.5))
    ids = np.full(idimg.shape[:2], -1, dtype=np.int32)
    opaque = idimg[..., 3] > 0.5
    for i in range(k):
        r, g, b = _ID_RGB[i]
        ids[opaque & (q[..., 0] == r) & (q[..., 1] == g) & (q[..., 2] == b)] = i
    a = ids >= 0
    # 2×2 合并：不透明像素数 ≥ 2 才算不透明；部位取多数；亮度取不透明像素的平均
    cnt = a.reshape(n, SS, n, SS).sum(axis=(1, 3))
    alpha = cnt >= (SS * SS) // 2
    votes = np.zeros((n, n, k), dtype=np.int32)
    for i in range(k):
        votes[..., i] = (ids == i).reshape(n, SS, n, SS).sum(axis=(1, 3))
    pid = votes.argmax(axis=2)
    # 眼睛这类很小的部位：2×2 里只要有一个子像素就保留（否则 1 个多像素宽的眼睛会被投票投掉）
    for part in ("eye", "gem"):
        if part in PARTS:
            pi = PARTS.index(part)
            pid[votes[..., pi] >= 1] = pi
    nv = nrm[..., :3] * 2.0 - 1.0
    lum = np.clip((nv * LIGHT_DIR).sum(axis=2), -1.0, 1.0)
    lm = (lum * a).reshape(n, SS, n, SS).sum(axis=(1, 3)) / np.maximum(cnt, 1)
    tone = np.where(lm > TONE_HI, 0, np.where(lm > TONE_MID, 1, 2))
    for part, t in _FLAT_TONE.items():
        tone[pid == PARTS.index(part)] = t
    out = np.zeros((n, n, 4))
    out[..., :3] = pal[pid, tone]
    out[..., 3] = alpha
    # 外描边：透明像素只要上下左右挨着角色，就涂成相邻部位最深色再压暗一半
    edge = np.zeros((n, n), dtype=bool)
    edge_col = np.zeros((n, n, 3))
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        na = np.roll(np.roll(alpha, dy, 0), dx, 1)
        npid = np.roll(np.roll(pid, dy, 0), dx, 1)
        m = ~alpha & na & ~edge
        edge_col[m] = pal[npid[m], 2] * 0.7 + INK * 0.3  # 描边用部位自己的暗色（偏一点墨色），不是近黑
        edge |= m
    out[edge, :3] = edge_col[edge]
    out[edge, 3] = 1.0
    return out


def _palette(spec):
    r = charspec.ramps(spec)
    pal = np.zeros((len(PARTS), 3, 3))
    for i, key in enumerate(PARTS):
        pal[i] = np.array([_hex(c) for c in r[key]])
    return pal


def _save_png(arr, path):
    h, w = arr.shape[:2]
    img = bpy.data.images.new("pw_sheet_tmp", width=w, height=h, alpha=True)
    img.pixels.foreach_set(arr[::-1].astype(np.float32).ravel())
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def render_anim(spec, anim, out_png, tmpdir, cam, actions=None):
    """渲染一个动作的精灵表：8 行方向 × N 帧"""
    a = poses.info(anim, actions)
    n = a["frames"]
    pal = _palette(spec)
    sheet = np.zeros((DIRS * FRAME, n * FRAME, 4), dtype=np.float32)
    for f in range(n):
        pose = poses.sample(anim, f, actions)
        obj = build_character(spec, pose).build_flat("pw_char_%s_%s_%d" % (spec["id"], anim, f))
        for d in range(DIRS):
            _place_camera(cam, d)
            idimg = _render(os.path.join(tmpdir, "id.png"), True)
            nrm = _render(os.path.join(tmpdir, "nrm.png"), False)
            sheet[d * FRAME:(d + 1) * FRAME, f * FRAME:(f + 1) * FRAME] = _compose(idimg, nrm, pal)
        me = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(me)
    _save_png(sheet, out_png)
    return {"file": "%s/%s.png" % (spec["id"], anim), "count": n, "fps": a["fps"], "loop": bool(a.get("loop")),
            "name": a.get("name", anim)}, sheet


def render_character(spec, out_dir, anims=None, actions=None, tmpdir=None, preview=None):
    """渲染一个角色的全部（或指定）动作，返回目录条目。preview：预览图路径（正面、侧前、侧面、背面 + 每个动作一帧）"""
    spec, _ = charspec.validate(spec)
    out = Path(out_dir) / spec["id"]
    out.mkdir(parents=True, exist_ok=True)
    tmp = tmpdir or tempfile.mkdtemp(prefix="pw_sprites_")
    cam = _setup_scene()
    entry = {"id": spec["id"], "name": spec["name"], "desc": spec["desc"], "anims": {}}
    sheets = {}
    for anim in anims or (poses.DEFAULT_ANIMS + [x for x in spec.get("extra_anims", []) if x in (actions or {})]):
        entry["anims"][anim], sheets[anim] = render_anim(spec, anim, out / ("%s.png" % anim), tmp, cam, actions)
    (out / "spec.json").write_text(json.dumps(spec, ensure_ascii=False, indent=2), encoding="utf-8")
    if preview:
        _preview(sheets, preview)
    return entry


def _preview(sheets, path):
    """预览图：待机的 4 个方向 + 其余每个动作中间一帧（侧前方），透明底，一行排开"""
    cells = []
    if "idle" in sheets:
        for d in (0, 1, 2, 4):
            cells.append(sheets["idle"][d * FRAME:(d + 1) * FRAME, 0:FRAME])
    for anim, sh in sheets.items():
        if anim == "idle":
            continue
        n = sh.shape[1] // FRAME
        f = n // 2
        cells.append(sh[1 * FRAME:2 * FRAME, f * FRAME:(f + 1) * FRAME])
    if not cells:
        return
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    _save_png(np.concatenate(cells, axis=1), path)


def catalog_header():
    origin_y = FRAME / 2 + TARGET_Z * math.cos(ELEV) * PX_PER_M
    return {
        "version": 2, "generator": "pixel_world_blender sprites %s" % VERSION, "blender": bpy.app.version_string,
        "frame": FRAME, "px_per_m": PX_PER_M, "origin": [FRAME / 2, round(origin_y, 2)], "dirs": DIRS,
        "elev_deg": round(math.degrees(ELEV), 2),
        "dir_order": "第 d 行 = 相机从角色正面逆时针（俯视）转 d×45°",
    }


def write_catalog(out_dir, entries):
    """把新渲染的角色合并进 catalog.json（同 id 覆盖，其余保留）"""
    out = Path(out_dir)
    path = out / "catalog.json"
    chars = []
    if path.exists():
        try:
            chars = json.loads(path.read_text(encoding="utf-8")).get("characters", [])
        except ValueError:
            chars = []
    # 同 id：动作逐个合并（只重渲了某几个动作时，其余动作保留）
    old = {c.get("id"): c for c in chars if "anims" in c}
    for e in entries:
        if e["id"] in old:
            merged = dict(old[e["id"]].get("anims", {}))
            merged.update(e["anims"])
            e["anims"] = merged
    ids = {e["id"] for e in entries}
    chars = [c for c in chars if c.get("id") not in ids and "anims" in c] + entries
    cat = catalog_header()
    cat["characters"] = chars
    path.write_text(json.dumps(cat, ensure_ascii=False, indent=2), encoding="utf-8")
    return cat
