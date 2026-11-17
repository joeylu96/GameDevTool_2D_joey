"""像素角色：在 Blender 里用参数搭一个约 6 头身的低模角色（分层服装：内衬、上衣、胸甲 / 背心、腰带、高领、披风），
按动作逐帧摆姿势，从 8 个方向用正交相机渲染，再在 numpy 里转成像素画，每个动作拼成一张精灵表交给 Godot。

每一帧、每个方向渲染三遍（Workbench，快且稳定），4 倍超采样：
  1. 材质 ID 遍：平光 + 每个部位一种纯色 → 每个像素属于哪个部位
  2. 法线遍：matcap「check_normal+y」把法线编码成颜色 → 用固定的左上主光分 4 档明暗（高光 / 亮 / 中 / 暗），
     金属、胸甲、皮带、靴子、头发再按高光方向点出亮点
  3. 深度遍：顶点色里写「离镜头多近」→ 前面的东西挡住后面时，在后面那一侧画 1 像素的暗色分界线（领口、袖口、手臂挡在身前）
  合成：4×4 合并（部位取多数，五官优先保留），去孤立杂点，臂章画锯齿花纹，轮廓外描 1 像素深色描边。

尺寸：每帧 144×144，64 像素 / 米（场景贴图 32 texel / 米的两倍，整数倍对齐），角色约 100 像素高。
俯角 25°（比游戏镜头的 40° 更正面，脸看得清）；Godot 公告板竖向拉长 1/cos(40°)，精灵像素和屏幕像素 1:1。
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

VERSION = "0.5.0"
FRAME = 224      # 帧高（像素）
FRAME_W = 168    # 帧宽：人物是竖长的，帧也做成竖长方形
SS = 4
PX_PER_M = 96.0
ELEV = math.radians(10.0)   # 接近正视（像立绘），脸、胸甲的塑形都看得清
VIEW_PITCH = 40.0   # 游戏镜头俯角：公告板竖向拉长 1/cos(VIEW_PITCH)
TARGET_Z = 1.12

# 身体比例：写实的 7.5 头身（参考 res/ 里的人物立绘），身高系数 h = 1 时约 1.82 米、头高 0.24 米。资产工坊动作编辑器（tools/workshop/index.html aeJoints）用同一组数
HIP_Z = 0.95
SH_Z = 1.52
HEAD_UP = 0.30      # 头部中心比肩高多少（缩放前；头的轮廓从中心往下 0.2 是下巴）
HEAD_SCALE = 0.61   # 头（连同头发、帽子、五官）以下巴为中心缩放
THIGH = 0.47
SHIN = 0.46
UPPER_ARM = 0.32
FORE_ARM = 0.29
DIRS = 8
INK = np.array([0x1a, 0x18, 0x22]) / 255.0

# 光照：法线遍解码后自己算，主光从左上前方照来（所有方向的帧光照一致，不会转个身就变暗）
LIGHT_DIR = np.array([-0.45, 0.65, 0.62]) / np.linalg.norm([-0.45, 0.65, 0.62])
SKIN_LIGHT = np.array([-0.28, 0.42, 0.86]) / np.linalg.norm([-0.28, 0.42, 0.86])  # 皮肤：光更正面，脸上明暗柔和
HALF_DIR = (LIGHT_DIR + np.array([0.0, 0.0, 1.0])) / np.linalg.norm(LIGHT_DIR + np.array([0.0, 0.0, 1.0]))
TONES = (0.8, 0.32, -0.12)   # N·L 高于这些值：高光 / 亮 / 中，其余是暗
SHINY = {"metal": 0.9, "armor": 0.962, "gem": 0.88, "belt": 0.965, "boots": 0.97, "hair": 0.93}  # 镜面高光门槛
HILITE = {"metal": 0.5, "armor": 0.3, "gem": 0.5, "skin": 0.1, "hair": 0.38, "collar": 0.08, "sclera": 0.0}  # 高光档往暖白提多少
PRIORITY = {"eye": 3, "sclera": 7, "brow": 5, "gem": 3}  # 4×4 子像素里占到几个就保留这个部位

PARTS = charspec.PARTS
PRESETS = charspec.PRESETS
# 部位材质 ID：用 {0, 0.5, 1} 三档组合的纯色区分，渲染时不管有没有色彩空间换算都能可靠地还原
_LEVELS = [0.0, 0.5, 1.0]
_ID_RGB = [(a, b, c) for a in _LEVELS for b in _LEVELS for c in _LEVELS if (a, b, c) != (0.0, 0.0, 0.0)]
_FLAT_TONE = {"eye": 2, "glow": 0, "shine": 0, "sclera": 1, "brow": 3}  # 这些部位不分明暗


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
    rgb = _ID_RGB[PARTS.index(key)]  # 只有前 26 个部位能当几何材质（charspec.PARTS 末尾几个只用来取色）
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    return m


def _dir(theta, sx=0.0):
    """竖直平面里的方向：theta = 0 朝下，正值往前（-Y）摆；sx 是向外撇的分量"""
    v = np.array([sx, -math.sin(theta), -math.cos(theta)])
    return v / np.linalg.norm(v)


# ---------------------------------------------------------------- 角色几何

def _bump(mb, key, c, rx, ry, rz, sides=8):
    """扁椭球（胸甲上的胸肌 / 腹肌块、护肩等小鼓包）"""
    cx, cy, cz = c
    rings = [(cz - rz * math.cos(t), rx * math.sin(t)) for t in np.linspace(0.0, math.pi, 7)]
    mb.stack(key, cx, cy, rings, max(sides, 12), sy=ry / rx, rot=0.0)


def build_character(spec, pose):
    """按规格和姿势搭出一帧的角色（约 6 头身，身高系数 1 时约 1.76 米）。
    先搭下半身（不随上身转），再搭上半身和头，最后整体做头部转动、上身扭转和前倾。
    服装是分层的：内衬 / 上衣 / 胸甲或背心 / 腰带 / 高领 / 披风，每层是单独的部位，像素画里各有自己的色阶和分界线。"""
    mb = FlatBuilder()
    h = spec.get("height", 1.0)
    bw = spec.get("build", 1.0)
    bob, breath = pose["bob"], pose["breath"]
    hip_z = HIP_Z * h + bob
    sh_z = SH_Z * h + bob + breath
    head_z = sh_z + HEAD_UP + breath * 0.5
    weapon = spec.get("weapon")
    in_hand = pose.get("weapon") == "hand"
    armor = spec.get("armor")
    tall_boots = spec.get("boots") == "tall"

    # ---- 下半身：腿、靴子、骨盆、下摆、腰带、挂在腰上的武器
    for side, key in ((1, "leg_l"), (-1, "leg_r")):
        th, kn = pose[key]
        hip = np.array([side * 0.09 * bw, 0.0, hip_z])
        kneep = hip + _dir(th) * THIGH * h
        sd = _dir(th - kn)
        ankle = kneep + sd * SHIN * h
        boot_top = kneep + sd * ((0.07 if tall_boots else SHIN * 0.62) * h)
        mb.tube("bottom", hip, kneep, 0.088 * bw, 0.064 * bw, 10)
        mb.tube("bottom", kneep - sd * 0.01, boot_top + sd * 0.02, 0.064 * bw, 0.056 * bw, 10)
        mb.tube("boots", boot_top, ankle, (0.07 if tall_boots else 0.062) * bw, 0.058 * bw, 10)
        if spec.get("knee_guards"):  # 靴口外面一圈深色护膝
            mb.tube("guard", boot_top - sd * 0.05, boot_top + sd * 0.1, 0.088 * bw, 0.08 * bw, 10)
        elif tall_boots:  # 靴口翻边
            mb.tube("boots", boot_top - sd * 0.012, boot_top + sd * 0.05, 0.08 * bw, 0.075 * bw, 10)
        if spec.get("knee_fur"):  # 膝盖上裹的毛皮护膝
            mb.tube("fur", kneep - _dir(th) * 0.07, kneep + sd * 0.09, 0.08 * bw, 0.074 * bw, 10)
        if spec.get("fur_trim") and not tall_boots:  # 靴口一圈毛
            mb.tube("fur", boot_top - sd * 0.03, boot_top + sd * 0.04, 0.072 * bw, 0.07 * bw, 10)
        foot = _dir(th - kn + math.pi / 2)  # 脚背方向：垂直于小腿向前
        mb.tube("boots", ankle - foot * 0.05 + np.array([0, 0, 0.012]), ankle + foot * 0.15 + np.array([0, 0, 0.0]),
                0.055, 0.042, 8, rot=math.pi / 8)
    mb.stack("bottom", 0, 0, [(hip_z - 0.09, 0.13 * bw), (hip_z + 0.02, 0.168 * bw), (hip_z + 0.1, 0.165 * bw)], 12, sy=0.76)
    sk = spec.get("skirt", 0.0) * h
    skirt_key = "armor" if armor == "cuirass" and not spec.get("skirt_cloth") else "skirt"
    if sk > 0.01:
        flare = (0.025 + sk * 0.05) if spec.get("skirt_split") else (0.06 + sk * 0.22)  # 开衩长下摆是直筒的
        rings = [(hip_z + 0.1, 0.168 * bw), (hip_z - 0.04, 0.18 * bw)]
        for i in range(1, 5):
            f = i / 4
            rings.append((hip_z - 0.04 - sk * f, 0.18 * bw + flare * (f ** 0.8)))
        swing = (pose["leg_l"][0] + pose["leg_r"][0]) * -0.05
        sy0 = swing + pose["cape"] * 0.02
        mb.stack(skirt_key, 0, sy0, rings, 14, sy=0.85, cap_top=False, cap_bottom=True)
        if spec.get("skirt_split"):  # 正面开衩：中缝露出裤子，两边各一条镶边带（参考图的长下摆）
            cf = math.cos(math.pi / 14) * 0.85
            for k2 in range(1, len(rings) - 1):
                (z0, r0), (z1, r1) = rings[k2], rings[k2 + 1]
                ya, yb = sy0 - r0 * cf - 0.012, sy0 - r1 * cf - 0.012
                for key2, xa, xb, dy in (("bottom", -0.022, 0.022, 0.0), ("panel", -0.075, -0.022, -0.004), ("panel", 0.022, 0.075, -0.004)):
                    mb.face(key2, [(xa, ya + dy, z0), (xb, ya + dy, z0), (xb, yb + dy, z1), (xa, yb + dy, z1)], (0, -1, 0))
        if (armor == "cuirass" and not spec.get("skirt_cloth")) or spec.get("trim_hem"):  # 下摆包边
            zb, rb = rings[-1]
            mb.stack("trim", 0, sy0, [(zb - 0.005, rb + 0.006), (zb + 0.035, rb - 0.004)], 14, sy=0.85, cap_top=False, cap_bottom=False)
    if spec.get("belt") or armor:
        mb.stack("belt", 0, 0, [(hip_z + 0.05, 0.178 * bw), (hip_z + 0.11, 0.178 * bw)], 12, sy=0.78)
        mb.box("metal", (-0.04, -0.148 * bw, hip_z + 0.045), (0.04, -0.13 * bw, hip_z + 0.115))   # 带扣
        mb.box("belt", (-0.018, -0.152 * bw, hip_z + 0.065), (0.018, -0.146 * bw, hip_z + 0.095))  # 扣眼里露出的皮带
    else:
        mb.stack("trim", 0, 0, [(hip_z + 0.07, 0.17 * bw), (hip_z + 0.12, 0.17 * bw)], 12, sy=0.78)
        mb.box("metal", (-0.035, -0.142 * bw, hip_z + 0.065), (0.035, -0.125 * bw, hip_z + 0.125))
    if not in_hand:
        if weapon == "sword":  # 左腰挂剑：剑鞘斜向后下，剑柄和护手在前上
            p0 = np.array([0.21 * bw, -0.05, hip_z + 0.05])
            mb.tube("trim", p0, p0 + np.array([0.04, 0.38, -0.46]), 0.036, 0.03, 8)
            mb.tube("metal", p0 + np.array([0.0, 0.0, 0.0]), p0 + np.array([0.0, -0.06, 0.07]), 0.022, 0.022, 6)
            mb.box("metal", (0.17 * bw, -0.07, hip_z + 0.035), (0.25 * bw, -0.03, hip_z + 0.065))
            mb.stack("trim", p0[0], p0[1] - 0.075, [(p0[2] + 0.07, 0.0), (p0[2] + 0.085, 0.03), (p0[2] + 0.11, 0.0)], 6)
        elif weapon == "axe":
            p0 = np.array([-0.21 * bw, -0.02, hip_z + 0.08])
            mb.tube("wood", p0, p0 + np.array([-0.03, 0.05, -0.48]), 0.024, 0.024, 6)
            mb.box("metal", (-0.25 * bw - 0.03, -0.11, hip_z + 0.0), (-0.25 * bw + 0.01, 0.05, hip_z + 0.15))
    if weapon == "bag":
        mb.box("wood", (0.18 * bw, -0.09, hip_z - 0.13), (0.29 * bw, 0.13, hip_z + 0.06))
        mb.box("trim", (0.18 * bw - 0.005, -0.095, hip_z + 0.0), (0.29 * bw + 0.005, 0.135, hip_z + 0.03))
    if spec.get("apron"):
        top_w, bot_w = 0.15 * bw, 0.2 * bw + sk * 0.12
        y0, y1 = -0.148 * bw, -0.17 * bw - sk * 0.2
        zb = hip_z - max(0.3, sk + 0.1)
        pts = [(-top_w, y0, hip_z + 0.1), (top_w, y0, hip_z + 0.1), (bot_w, y1, zb), (-bot_w, y1, zb)]
        mb.face("apron", pts, (0, -1, 0))
        mb.face("apron", [(x, y + 0.006, z) for (x, y, z) in pts][::-1], (0, 1, 0))
    lower_end = len(mb.verts)

    # ---- 上半身：躯干（胸比腰宽）、胸甲 / 背心、脖子、高领、手臂（三角肌、上衣袖、内衬袖、拳头）、围巾、披风
    torso = [(hip_z + 0.06, 0.158), (hip_z + 0.18, 0.15), (hip_z + 0.32, 0.165), (sh_z - 0.14, 0.19), (sh_z - 0.05, 0.182),
             (sh_z + 0.01, 0.13), (sh_z + 0.05, 0.07)]
    if spec.get("collar") or armor == "cuirass":  # 领口收进高领 / 胸甲里，不从领子和胸甲之间露出来
        torso[-2:] = [(sh_z - 0.0, 0.12), (sh_z + 0.03, 0.065)]
    mb.stack("top", 0, 0, [(z, r * bw) for z, r in torso], 12, sy=0.7)
    if armor == "cuirass":
        cu = [(hip_z - 0.03, 0.176), (hip_z + 0.18, 0.165), (hip_z + 0.32, 0.18), (sh_z - 0.14, 0.204), (sh_z - 0.05, 0.196),
              (sh_z - 0.0, 0.15)]
        mb.stack("armor", 0, 0, [(z, r * bw) for z, r in cu], 12, sy=0.72, cap_bottom=False)
        fy = lambda r: -r * bw * 0.72 * math.cos(math.pi / 12)  # noqa: E731  胸甲正面到中心的距离
        for sx in (-1, 1):  # 胸肌
            _bump(mb, "armor", (sx * 0.078 * bw, fy(0.2) + 0.016, sh_z - 0.15), 0.078 * bw, 0.032, 0.062)
        for row in range(3):  # 腹肌：两列三排
            z = hip_z + 0.29 - row * 0.078
            for sx in (-1, 1):
                _bump(mb, "armor", (sx * 0.04 * bw, fy(0.168) + 0.01, z), 0.034 * bw, 0.02, 0.031)
        # 包边：领口、袖窿、底边，以及肩带上的金属扣
        mb.stack("trim", 0, 0, [(sh_z - 0.012, 0.155 * bw), (sh_z + 0.012, 0.142 * bw)], 12, sy=0.74, cap_bottom=False, cap_top=False)
        mb.stack("trim", 0, 0, [(hip_z - 0.035, 0.18 * bw), (hip_z - 0.0, 0.178 * bw)], 12, sy=0.73, cap_bottom=False, cap_top=False)
        for sx in (-1, 1):
            mb.box("trim", (sx * 0.17 * bw - 0.02, -0.1, sh_z - 0.2), (sx * 0.17 * bw + 0.02, 0.1, sh_z - 0.02))
            mb.box("armor", (sx * 0.12 * bw - 0.04, -0.13 * bw, sh_z - 0.04), (sx * 0.12 * bw + 0.04, 0.13 * bw, sh_z + 0.03))
            mb.box("metal", (sx * 0.12 * bw - 0.026, -0.145 * bw, sh_z - 0.03), (sx * 0.12 * bw + 0.026, -0.128 * bw, sh_z + 0.012))
    if spec.get("apron"):  # 围裙的护胸，挂在脖子上
        mb.box("apron", (-0.105 * bw, -0.152 * bw, hip_z + 0.08), (0.105 * bw, -0.138 * bw, sh_z - 0.1))
        for sx in (-1, 1):
            mb.tube("apron", (sx * 0.095 * bw, -0.145 * bw, sh_z - 0.1), (sx * 0.05, -0.06, sh_z + 0.04), 0.012, 0.012, 4)
    if armor == "cuirass":
        pass
    elif armor == "leather" or spec.get("vest"):  # 背心 / 皮甲：比上衣大一圈，两条肩带
        mb.stack("vest", 0, 0, [(hip_z + 0.1, 0.17 * bw), (hip_z + 0.22, 0.174 * bw), (sh_z - 0.12, 0.196 * bw),
                                (sh_z - 0.04, 0.18 * bw)], 12, sy=0.74, cap_bottom=False, cap_top=False)
        for sx in (-1, 1):
            mb.box("vest", (sx * 0.11 * bw - 0.035, -0.135 * bw, sh_z - 0.08), (sx * 0.11 * bw + 0.035, 0.13 * bw, sh_z + 0.02))
            mb.box("metal", (sx * 0.1 * bw - 0.022, -0.145 * bw, sh_z - 0.085), (sx * 0.1 * bw + 0.022, -0.132 * bw, sh_z - 0.05))
    mb.tube("skin", (0, 0, sh_z), (0, 0, head_z - 0.15), 0.06, 0.054, 10)
    if spec.get("collar"):  # 高领：围住脖子，领口翻一圈
        # 领口顶在下巴下面（下巴在肩上方约 0.07 米），不然会把嘴和下半张脸盖住
        mb.stack("collar", 0, 0.0, [(sh_z - 0.02, 0.112), (sh_z + 0.02, 0.1), (sh_z + 0.05, 0.088)], 12, sy=0.92,
                 cap_bottom=False, cap_top=False)
        mb.stack("collar", 0, 0.0, [(sh_z + 0.03, 0.1), (sh_z + 0.052, 0.095)], 12, sy=0.92, cap_bottom=False, cap_top=False)
    if spec.get("fur_collar"):  # 毛领：围着脖子一圈，前面敞开一点
        mb.stack("fur", 0, 0.01, [(sh_z - 0.06, 0.15 * bw), (sh_z + 0.0, 0.135 * bw), (sh_z + 0.05, 0.1)], 12, sy=0.85, cap_bottom=False)
    if spec.get("straps"):  # 背带：两条从肩到腰，一条斜挎过胸口
        fy2 = -0.19 * bw * 0.7 * math.cos(math.pi / 12) - 0.012
        for sx in (-1, 1):
            mb.box("strap", (sx * 0.115 * bw - 0.02, fy2 - 0.006, hip_z + 0.1), (sx * 0.115 * bw + 0.02, fy2 + 0.02, sh_z - 0.02))
            mb.box("strap", (sx * 0.115 * bw - 0.02, -0.1, sh_z - 0.03), (sx * 0.115 * bw + 0.02, 0.13, sh_z + 0.0))
        mb.face("strap", [(-0.17 * bw, fy2 - 0.01, sh_z - 0.08), (-0.12 * bw, fy2 - 0.01, sh_z - 0.03),
                          (0.17 * bw, fy2 - 0.01, hip_z + 0.16), (0.12 * bw, fy2 - 0.01, hip_z + 0.1)], (0, -1, 0))
    if spec.get("satchel"):  # 腰前左侧的皮挎包
        mb.box("strap", (0.06 * bw, -0.2 * bw, hip_z - 0.16), (0.2 * bw, -0.13 * bw, hip_z + 0.06))
        mb.box("belt", (0.055 * bw, -0.207 * bw, hip_z - 0.04), (0.205 * bw, -0.19 * bw, hip_z + 0.07))
    if weapon == "rifle":  # 猎枪斜背在背上：枪托在右腰后，枪管从左肩上方伸出去
        p0 = np.array([-0.2 * bw, 0.15, hip_z + 0.02])
        p1 = np.array([0.24 * bw, 0.15, sh_z + 0.42])
        dd = (p1 - p0) / np.linalg.norm(p1 - p0)
        mb.tube("wood", p0 - dd * 0.12, p0 + dd * 0.22, 0.04, 0.03, 6)
        mb.tube("wood", p0 + dd * 0.2, p0 + dd * 0.6, 0.026, 0.022, 6)
        mb.tube("metal", p0 + dd * 0.3, p1, 0.014, 0.012, 6)
    sleeves = spec.get("sleeves", "long")
    hands = {}
    fore_dirs = {}
    for side, key in ((1, "arm_l"), (-1, "arm_r")):
        a, e, spread = pose[key]
        sh = np.array([side * 0.215 * bw, 0.0, sh_z - 0.045])
        elbow = sh + _dir(a, side * (0.05 + spread)) * UPPER_ARM * h
        d1 = (elbow - sh) / np.linalg.norm(elbow - sh)
        d2 = _dir(a + e, side * (0.02 + spread * 0.4))
        hand = elbow + d2 * FORE_ARM * h
        upper_key = "top"
        # 三角肌（肩头圆起来，袖子从这里开始）
        mb.stack(upper_key, sh[0], sh[1], [(sh[2] - 0.07, 0.0), (sh[2] - 0.04, 0.066 * bw), (sh[2] + 0.015, 0.07 * bw),
                                           (sh[2] + 0.055, 0.0)], 10)
        if sleeves == "layered":  # 内衬长袖 + 外面到肘部的短袖上衣
            mb.tube("under", sh, elbow, 0.06 * bw, 0.052 * bw, 10)
            mb.tube("under", elbow, hand, 0.052 * bw, 0.044 * bw, 10)
            send = sh + d1 * UPPER_ARM * h * 0.82
            mb.tube("top", sh, send, 0.068 * bw, 0.064 * bw, 10)
            if spec.get("sleeve_band"):
                mb.tube("band", send - d1 * 0.075, send + d1 * 0.004, 0.0695 * bw, 0.0655 * bw, 10)
            mb.tube("under", hand - d2 * 0.06, hand - d2 * 0.025, 0.05 * bw, 0.05 * bw, 10)  # 袖口
        else:
            mb.tube("top", sh, elbow, 0.064 * bw, 0.056 * bw, 10)
            if spec.get("sleeve_band"):
                mb.tube("band", sh + d1 * 0.14, sh + d1 * 0.22, 0.068 * bw, 0.064 * bw, 10)
            if sleeves == "long":
                mb.tube("top", elbow, hand, 0.056 * bw, 0.047 * bw, 10)
                mb.tube("trim", hand - d2 * 0.05, hand - d2 * 0.018, 0.058 * bw, 0.058 * bw, 10)
            else:
                mb.tube("skin", elbow, hand, 0.05 * bw, 0.043 * bw, 10)
        if spec.get("fur_trim"):
            mb.tube("fur", hand - d2 * 0.085, hand - d2 * 0.02, 0.058 * bw, 0.06 * bw, 10)
        # 拳头 + 拇指
        mb.stack("skin", hand[0], hand[1], [(hand[2] - 0.075, 0.0), (hand[2] - 0.06, 0.04), (hand[2] - 0.015, 0.05),
                                            (hand[2] + 0.02, 0.036)], 10, sy=0.85)
        mb.tube("skin", hand + np.array([0.0, -0.035, -0.0]), hand + np.array([0.0, -0.05, -0.04]), 0.017, 0.014, 6)
        hands[side] = hand
        fore_dirs[side] = d2
        g = pose.get("hand_glow", 0.0)
        if g > 0.05:
            r = 0.04 + 0.07 * g
            c = hand + d2 * 0.05
            mb.stack("glow", c[0], c[1], [(c[2] - r, 0.0), (c[2] - r * 0.5, r * 0.85), (c[2] + r * 0.5, r * 0.85), (c[2] + r, 0.0)], 8)
    if spec.get("scarf"):
        mb.stack("scarf", 0, 0, [(sh_z - 0.03, 0.178 * bw), (sh_z + 0.01, 0.15 * bw), (sh_z + 0.045, 0.09)], 12, sy=0.8)
        mb.box("scarf", (0.04, -0.175 * bw, sh_z - 0.26), (0.115, -0.135 * bw, sh_z))
    if spec.get("cape"):
        top_y = 0.11
        bot_y = 0.19 + pose["cape"] * 0.3
        zb = hip_z - 0.32 * h + pose["cape"] * 0.12
        pts = [(-0.21 * bw, top_y, sh_z + 0.02), (0.21 * bw, top_y, sh_z + 0.02), (0.3 * bw, bot_y, zb), (-0.3 * bw, bot_y, zb)]
        mb.face("cape", pts, (0, 1, 0))
        mb.face("cape", [(x, y - 0.012, z) for (x, y, z) in pts][::-1], (0, -1, 0))
        mb.stack("cape", 0, 0.02, [(sh_z - 0.02, 0.2 * bw), (sh_z + 0.05, 0.12)], 12, sy=0.85, cap_top=False)
    if weapon == "greatsword" and not in_hand:  # 大剑斜背在背上
        p0 = np.array([0.23, 0.18, hip_z - 0.05])
        p1 = np.array([-0.26, 0.18, sh_z + 0.32])
        mb.tube("metal", p0, p1, 0.045, 0.04, 4, rot=math.pi / 4)
        mb.tube("trim", p1, p1 + (p1 - p0) / np.linalg.norm(p1 - p0) * 0.18, 0.025, 0.025, 6)
    _weapon_in_hand(mb, spec, pose, hands[-1], fore_dirs[-1], in_hand, h)
    head_start = len(mb.verts)

    # ---- 头：按原尺寸搭（脸正面是一个平面，五官贴在上面），最后整体以下巴为中心缩到 HEAD_SCALE
    head = [(-0.2, 0.0), (-0.192, 0.08), (-0.155, 0.15), (-0.06, 0.198), (0.05, 0.21), (0.14, 0.192), (0.2, 0.14),
            (0.235, 0.06), (0.245, 0.0)]
    mb.stack("skin", 0, 0, [(head_z + dz, r) for dz, r in head], 16, sy=0.94)  # 16 边：脸是圆的，不是一块方板
    front = -0.2 * 0.94 * math.cos(math.pi / 16)  # 正面那个面到中心的距离（y）
    # 鼻子、耳朵：有了它们，脸上才有一两个像素的明暗（鼻梁亮、鼻底暗）
    mb.box("skin", (-0.022, front - 0.035, head_z - 0.1), (0.022, front + 0.01, head_z - 0.02))
    for sx in (-1, 1):
        mb.box("skin", (sx * 0.2 - 0.025, -0.035, head_z - 0.11), (sx * 0.2 + 0.025, 0.045, head_z - 0.01))
    _hair(mb, spec, head_z, front, pose)
    _hat(mb, spec, head_z, front)
    if spec.get("beard"):
        style = spec.get("beard_style", "goatee")
        if style in ("short", "full"):  # 络腮胡：沿下颌一圈，盖住脸的下半部
            low = 0.27 if style == "full" else 0.235
            mb.stack("hair", 0, -0.02, [(head_z - low, 0.0), (head_z - low + 0.025, 0.09), (head_z - 0.17, 0.16),
                                         (head_z - 0.115, 0.2)], 12, sy=0.95, cap_top=False)
        else:  # 山羊胡：只在下巴前面一小撮
            mb.stack("hair", 0, -0.115, [(head_z - 0.29, 0.0), (head_z - 0.25, 0.05), (head_z - 0.19, 0.075), (head_z - 0.15, 0.06)],
                     8, sy=0.7)
        mb.box("hair", (-0.06, front - 0.014, head_z - 0.15), (0.06, front + 0.02, head_z - 0.122))  # 上唇胡
    # 五官定位点：跟着头一起缩放、转动，渲染后投影到画面上，在像素层逐像素画眼睛、眉毛、鼻底、嘴（_stamp_face）
    marks = {"head": (0.0, 0.0, head_z - 0.03), "eye_l": (0.085, front - 0.004, head_z - 0.022),
             "eye_r": (-0.085, front - 0.004, head_z - 0.022), "nose": (0.0, front - 0.03, head_z - 0.092),
             "mouth": (0.0, front - 0.004, head_z - 0.14), "fwd": (0.0, front - 0.4, head_z - 0.03)}
    m0 = len(mb.verts)
    mb.verts.extend(np.array(v, dtype=float) for v in marks.values())
    end = len(mb.verts)
    chin = np.array([0.0, 0.0, head_z - 0.2])
    for i in range(head_start, end):
        mb.verts[i] = tuple(chin + (np.array(mb.verts[i]) - chin) * HEAD_SCALE * np.array([0.86, 1.0, 1.0]))  # 脸窄一点

    # ---- 姿势变换：头（绕脖子），再整个上半身（扭转 + 前倾，绕腰）
    neck = (0.0, 0.0, chin[2] + 0.02 * HEAD_SCALE)
    mb.rotate(head_start, end, "x", pose["head"][0], neck)
    mb.rotate(head_start, end, "z", pose["head"][1], neck)
    mb.rotate(lower_end, end, "z", pose["twist"], (0.0, 0.0, 0.0))
    mb.rotate(lower_end, end, "x", pose["lean"], (0.0, 0.0, hip_z + 0.08))
    mb.marks = {k: np.array(mb.verts[m0 + i], dtype=float) for i, k in enumerate(marks)}
    del mb.verts[m0:]  # 定位点不是网格的一部分
    return mb


def _weapon_in_hand(mb, spec, pose, hand, d2, in_hand, h):
    w = spec.get("weapon")
    if w is None or w == "bag":
        return
    if w == "rifle":
        return  # 猎枪一直背在背上（build_character 里画）
    if w in ("hammer", "mug", "book", "basket", "lute", "pitchfork"):
        _tool(mb, w, hand, d2, h)
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


def _tool(mb, w, hand, d2, h):
    """手艺人 / 小贩的道具（右手）：锻锤、酒杯、书、提篮、草叉；鲁特琴背在背上"""
    down = np.array([0.0, 0.0, -1.0])
    if w == "hammer":
        mb.tube("wood", hand + d2 * 0.04, hand + d2 * 0.04 + down * 0.36, 0.018, 0.018, 6)
        hp = hand + d2 * 0.04 + down * 0.36
        mb.box("metal", tuple(hp + np.array([-0.07, -0.035, -0.06])), tuple(hp + np.array([0.05, 0.035, 0.0])))
    elif w == "mug":
        c = hand + np.array([0.0, -0.06, 0.0])
        mb.stack("wood", c[0], c[1], [(c[2] - 0.06, 0.0), (c[2] - 0.06, 0.045), (c[2] + 0.07, 0.048), (c[2] + 0.07, 0.0)], 8)
        mb.stack("metal", c[0], c[1], [(c[2] - 0.02, 0.05), (c[2] + 0.0, 0.05)], 8, cap_bottom=False, cap_top=False)
        mb.stack("collar", c[0], c[1], [(c[2] + 0.07, 0.044), (c[2] + 0.1, 0.035), (c[2] + 0.11, 0.0)], 8)  # 啤酒沫
    elif w == "book":
        c = hand + np.array([0.02, -0.08, 0.06])
        mb.box("hat", tuple(c + np.array([-0.06, -0.025, -0.09])), tuple(c + np.array([0.06, 0.025, 0.09])))
        mb.box("collar", tuple(c + np.array([-0.055, -0.03, -0.085])), tuple(c + np.array([0.05, 0.03, 0.085])))
    elif w == "basket":
        c = hand + np.array([0.0, -0.02, -0.12])
        mb.stack("wood", c[0], c[1], [(c[2] - 0.08, 0.0), (c[2] - 0.08, 0.12), (c[2] + 0.04, 0.15), (c[2] + 0.05, 0.0)], 10, sy=0.7)
        for i, dx in enumerate((-0.06, 0.0, 0.06)):
            mb.stack("trim", c[0] + dx, c[1] - 0.01, [(c[2] + 0.02, 0.0), (c[2] + 0.04, 0.04), (c[2] + 0.08, 0.0)], 6)
        mb.tube("wood", c + np.array([-0.12, 0, 0.04]), hand + np.array([0, 0, 0.02]), 0.012, 0.012, 4)
        mb.tube("wood", c + np.array([0.12, 0, 0.04]), hand + np.array([0, 0, 0.02]), 0.012, 0.012, 4)
    elif w == "pitchfork":
        bot = np.array([hand[0], hand[1] - 0.02, 0.03])
        tp = np.array([hand[0], hand[1] - 0.02, hand[2] + 0.75 * h])
        mb.tube("wood", bot, tp, 0.022, 0.022, 6)
        mb.box("metal", tuple(tp + np.array([-0.08, -0.012, 0.0])), tuple(tp + np.array([0.08, 0.012, 0.025])))
        for dx in (-0.075, 0.0, 0.075):
            mb.tube("metal", tp + np.array([dx, 0, 0.02]), tp + np.array([dx, 0, 0.2]), 0.01, 0.006, 4)
    elif w == "lute":  # 斜背在背上
        c = np.array([0.08, 0.2, hand[2] + 0.35 * h])
        mb.stack("wood", c[0], c[1], [(c[2] - 0.16, 0.0), (c[2] - 0.12, 0.12), (c[2] + 0.02, 0.13), (c[2] + 0.1, 0.07),
                                     (c[2] + 0.12, 0.0)], 10, sy=0.45)
        mb.tube("hat", c + np.array([0, 0, 0.1]), c + np.array([-0.12, 0, 0.42]), 0.02, 0.018, 6)
        mb.tube("trim", (0.18, -0.12, hand[2] + 0.55 * h), (-0.18, 0.14, hand[2] + 0.15 * h), 0.012, 0.012, 4)  # 背带


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
    covered = hat in ("helmet", "hood", "fur")
    if not covered:
        if style in ("short", "spiky"):  # 短发：贴着头皮，发际线在额头上方（不像一顶头盔）
            mb.stack("hair", 0, 0.025, [(hz + 0.045, 0.214), (hz + 0.1, 0.212), (hz + 0.16, 0.196), (hz + 0.215, 0.15),
                                        (hz + 0.25, 0.075), (hz + 0.262, 0.0)], 12, sy=0.97, cap_bottom=False)
        else:
            mb.stack("hair", 0, 0.01, [(hz + 0.03, 0.222), (hz + 0.08, 0.226), (hz + 0.16, 0.205), (hz + 0.22, 0.155),
                                       (hz + 0.26, 0.07), (hz + 0.27, 0.0)], 12, sy=0.97, cap_bottom=False)
    mb.stack("hair", 0, 0.05, [(hz - 0.17, 0.12), (hz - 0.1, 0.19), (hz + 0.02, 0.21), (hz + 0.1, 0.18)], 12, sy=0.94)
    # 刘海：额前一排长短不一的发束（尖朝下，稍微往一边梳）
    bangs = (-0.15, -0.1, -0.05, 0.0, 0.05, 0.1, 0.15)
    if style == "spiky":
        bangs = ()   # 刺头往上翘，没有垂下来的刘海
    blen = 0.5 if style == "short" else 1.0  # 短发的刘海短一半
    for i, x in enumerate(() if covered else bangs):
        ln = (0.03 + 0.045 * (((i * 5) % 4) / 3.0)) * blen
        lean = 0.012
        mb.face("hair", [(x - 0.034, front - 0.018, hz + 0.07), (x + 0.034, front - 0.018, hz + 0.07),
                         (x + lean, front - 0.024, hz + 0.07 - ln)], (0, -1, 0))
    # 发际线一圈成簇的发尖：两侧和脑后往下垂的小三角，轮廓不再是光滑的「头盔」
    if not covered and style != "bald":
        for k in range(18):
            ang = math.pi * 0.25 + k * (math.pi * 1.5 / 17)   # 从右前绕到脑后再到左前
            r = 0.205
            cx, cy = math.cos(ang) * r, math.sin(ang) * r * 0.97 + 0.02
            ln = 0.05 + 0.035 * ((k * 7) % 3) / 2
            tx, ty = -math.sin(ang) * 0.028, math.cos(ang) * 0.028
            out = (math.cos(ang), math.sin(ang), 0.0)
            mb.face("hair", [(cx - tx, cy - ty, hz + 0.06), (cx + tx, cy + ty, hz + 0.06),
                             (cx * 1.02, cy * 1.02, hz + 0.06 - ln)], out)
    if covered:
        return
    flow = pose.get("cape", 0.1)
    if style == "spiky":  # 短刺头：一圈细碎的短发束朝上后方翘
        for k in range(13):
            ang = -1.15 + k * (2.3 / 12)
            r0 = 0.17 + 0.03 * ((k * 5) % 3) / 2
            base = np.array([math.sin(ang) * r0 * 0.75, 0.04 + 0.05 * abs(math.cos(ang)), hz + 0.19 + 0.02 * math.cos(ang)])
            tip = base + np.array([math.sin(ang) * 0.07, 0.06 + flow * 0.03, 0.085 - abs(ang) * 0.035])
            mb.tube("hair", base, tip, 0.045, 0.0, 5)
    elif style == "long":
        back = 0.07 + flow * 0.05
        mb.stack("hair", 0, back, [(hz - 0.5, 0.0), (hz - 0.46, 0.17), (hz - 0.3, 0.2), (hz - 0.1, 0.205), (hz + 0.05, 0.2)],
                 12, sy=0.85)
        for k in range(5):  # 背后几缕发束，发尾参差
            x = -0.14 + k * 0.07
            tip = hz - 0.5 - 0.06 * ((k * 3) % 3) / 2
            mb.tube("hair", (x, back + 0.13, hz - 0.1), (x * 1.1, back + 0.16 + flow * 0.05, tip), 0.045, 0.012, 6)
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
    elif hat == "toque":  # 面包师的白色高帽
        mb.stack("hat", 0, 0.01, [(hz + 0.08, 0.215), (hz + 0.2, 0.225), (hz + 0.36, 0.25), (hz + 0.42, 0.2), (hz + 0.44, 0.0)],
                 14, sy=0.97)
        mb.stack("hat", 0, 0.01, [(hz + 0.06, 0.222), (hz + 0.13, 0.222)], 14, sy=0.97)
    elif hat == "feather":  # 软帽 + 一根斜插的长羽毛
        mb.stack("hat", 0, 0.02, [(hz + 0.07, 0.232), (hz + 0.15, 0.24), (hz + 0.22, 0.17), (hz + 0.26, 0.0)], 12, sy=0.97)
        mb.stack("hat", 0, 0.02, [(hz + 0.06, 0.26), (hz + 0.09, 0.25)], 12, sy=0.97)
        mb.face("trim", [(0.15, 0.02, hz + 0.15), (0.2, 0.06, hz + 0.16), (0.32, 0.2, hz + 0.42), (0.26, 0.18, hz + 0.45)],
                (1, 0, 0))
        mb.face("trim", [(0.149, 0.02, hz + 0.15), (0.259, 0.18, hz + 0.45), (0.319, 0.2, hz + 0.42), (0.199, 0.06, hz + 0.16)],
                (-1, 0, 0))
    elif hat == "fur":  # 毛皮帽：蓬松的大圆顶，两侧护耳垂到下颌
        mb.stack("fur", 0, 0.02, [(hz + 0.02, 0.25), (hz + 0.1, 0.275), (hz + 0.22, 0.26), (hz + 0.31, 0.19), (hz + 0.36, 0.0)],
                 14, sy=0.97, cap_bottom=False)
        for sx in (-1, 1):
            mb.stack("fur", sx * 0.2, 0.05, [(hz - 0.2, 0.0), (hz - 0.17, 0.06), (hz - 0.02, 0.075), (hz + 0.06, 0.06)], 8)
    elif hat == "cap":  # 小布帽 + 帽檐
        mb.stack("hat", 0, 0.01, [(hz + 0.07, 0.228), (hz + 0.16, 0.215), (hz + 0.23, 0.15), (hz + 0.27, 0.0)], 12, sy=0.97)
        mb.box("hat", (-0.13, front - 0.11, hz + 0.07), (0.13, front + 0.02, hz + 0.095))


# ---------------------------------------------------------------- 渲染

def _setup_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x = FRAME_W * SS
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


def _render(path, mode):
    """mode：id（平光 + 部位纯色）/ nrm（matcap 法线）/ dep（顶点色里的深度，16 位 PNG 读回来是线性值）"""
    sc = bpy.context.scene
    sh = sc.display.shading
    sc.render.image_settings.color_depth = "16" if mode == "dep" else "8"
    if mode == "id":
        sh.light = "FLAT"
        sh.color_type = "MATERIAL"
    elif mode == "nrm":
        sh.light = "MATCAP"
        sh.studio_light = "check_normal+y.exr"
        sh.color_type = "SINGLE"
        sh.single_color = (1.0, 1.0, 1.0)
    else:
        sh.light = "FLAT"
        sh.color_type = "VERTEX"
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    w, hgt = img.size
    buf = np.empty(w * hgt * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    return buf.reshape(hgt, w, 4)[::-1]  # 第 0 行在顶部


DEPTH_RANGE = 3.0  # 深度遍编码范围（米）：0.5 = 和镜头对准点同深度


def _set_depth(obj, cam):
    """把每个顶点「朝镜头方向离对准点多远」写进顶点色（越大越靠前）"""
    me = obj.data
    co = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    fwd = np.array(cam.location) - np.array([0.0, 0.0, TARGET_Z])
    fwd /= np.linalg.norm(fwd)
    t = (co - np.array([0.0, 0.0, TARGET_Z])) @ fwd
    v = np.clip(0.5 + t / DEPTH_RANGE, 0.0, 1.0)
    att = me.color_attributes.get("pw_depth") or me.color_attributes.new("pw_depth", "FLOAT_COLOR", "POINT")
    cols = np.ones((len(v), 4), dtype=np.float32)
    cols[:, 0] = cols[:, 1] = cols[:, 2] = v
    att.data.foreach_set("color", cols.ravel())
    me.color_attributes.active_color = att


def _project_marks(marks, cam):
    """五官定位点 → 画面像素坐标（x 向右、y 向下）、朝向镜头的程度、离镜头多近"""
    rot = cam.rotation_euler.to_matrix()
    right = np.array(rot.col[0])
    up = np.array(rot.col[1])
    back = np.array(rot.col[2])  # 指向镜头
    tgt = np.array([0.0, 0.0, TARGET_Z])
    out = {}
    head = marks["head"]
    fwd = marks["fwd"] - head
    fwd /= np.linalg.norm(fwd)
    for k, p in marks.items():
        rel = p - tgt
        n = p - head
        n = n / max(np.linalg.norm(n), 1e-6)
        out[k] = {"x": FRAME_W / 2 + rel @ right * PX_PER_M, "y": FRAME / 2 - rel @ up * PX_PER_M, "t": rel @ back,
                  "facing": float(n @ back)}
    out["fwd_dot"] = float(fwd @ back)
    out["fwd_x"] = float(fwd @ right)  # 脸朝画面右边为正
    return out


def _stamp_face(out, pid, alpha, dpx, pal, face, spec):
    """在像素层画五官（只画在露出来的皮肤上）。96 像素 / 米、头宽约 20 像素：
      眼睛：上眼睑一行（男性是深棕、女性 lashes 是近黑并在外眼角上翘）+ 眼白 / 2 格瞳孔（左上高光）+ 瞳孔下半一行
      眉毛：用发色的中间调（不是黑线，和眼睑分得开）；stern 的眉心一头压低贴着眼睑
      鼻子：背光一侧 2 像素的鼻梁阴影 + 鼻底 1 像素；嘴：3 像素唇线（偏红）+ 下唇阴影；女性两颊各 2 像素腮红"""
    nh, nw = out.shape[:2]
    skin = PARTS.index("skin")
    hair = pal[PARTS.index("hair")]
    sk = pal[skin]
    lashes = bool(spec.get("lashes"))
    lid = (hair[3] * 0.3 + INK * 0.7) if lashes else (sk[3] * 0.55 + INK * 0.45)
    brow = hair[2] * 0.78 + INK * 0.22
    white = pal[PARTS.index("sclera")][1] * 0.97
    iris_l = pal[PARTS.index("eye")][1]
    iris_d = pal[PARTS.index("eye")][2] * 0.65 + INK * 0.35
    shine = np.array([1.0, 1.0, 1.0])
    lip = sk[3] * 0.55 + np.array([0.36, 0.1, 0.1])
    blush = sk[1] * 0.72 + np.array([0.26, 0.1, 0.1])
    stern = spec.get("brow", "soft") == "stern"

    def ok(x, y):
        return 0 <= x < nw and 0 <= y < nh and alpha[y, x] and pid[y, x] == skin

    def put(x, y, col):
        x, y = int(x), int(y)
        if ok(x, y):
            out[y, x, :3] = col

    def visible(m, tol=0.035):
        x, y = int(round(m["x"])), int(round(m["y"]))
        return ok(x, y) and dpx[y, x] <= m["t"] + tol

    if face["fwd_dot"] < -0.1:
        return  # 背面
    fx = 1 if face["fwd_x"] > 0.12 else (-1 if face["fwd_x"] < -0.12 else 0)  # 脸朝哪边偏（瞳孔往那边看）
    cx_face = face["nose"]["x"]
    for key in ("eye_l", "eye_r"):
        m = face[key]
        front = m["facing"] > 0.55
        if m["facing"] < 0.15 or not visible(m, 0.035 if front else 0.08):
            continue
        x0, y0 = int(round(m["x"] - 0.5)), int(round(m["y"]))
        inner = 1 if cx_face > m["x"] else -1   # 眉心在这只眼睛的哪一侧
        if front:
            xs = [x0 - 1, x0, x0 + 1, x0 + 2]
            ix = x0 + (1 if fx > 0 else 0) if fx else x0
            ix = min(max(ix, xs[0]), xs[-2])
        else:
            xs = [x0, x0 + 1, x0 + 2] if fx >= 0 else [x0 - 2, x0 - 1, x0]
            ix = xs[1] if fx >= 0 else xs[0]
        outer = xs[0] if inner > 0 else xs[-1]
        for x in xs:
            put(x, y0 - 1, lid)
            put(x, y0, white)
        put(ix, y0, iris_d)
        put(ix + 1, y0, iris_l)
        put(ix, y0 + 1, iris_d)
        put(ix + 1, y0 + 1, iris_d * 0.75 + iris_l * 0.25)
        put(ix, y0, shine * 0.6 + iris_l * 0.4)
        put(outer - inner, y0, sk[2])                 # 外眼角一点阴影，眼型不是方块
        if lashes:
            put(outer - inner, y0 - 2, lid)
            put(xs[0] if inner < 0 else xs[-1], y0 + 2, blush)   # 腮红（外侧脸颊）
            put(outer, y0 + 3, blush)
            put(outer + inner, y0 + 3, blush)
        # 眉毛：比眼睛宽 1 格，离眼睑隔一行；stern 眉心一头压到眼睑上
        bx = sorted(list(xs) + [outer - inner])
        for x in bx:
            near_center = (x - m["x"]) * inner > 0.5
            put(x, y0 - (2 if (stern and near_center) else 3), brow)
    nm = face["nose"]
    if face["fwd_dot"] > 0.3 and visible(nm, 0.06):
        nx, ny = int(round(nm["x"] - 0.5)), int(round(nm["y"]))
        sd = fx if fx else 1                          # 鼻梁阴影在背光 / 远离镜头的一侧
        put(nx + sd, ny - 2, sk[2])
        put(nx + sd, ny - 1, sk[2])
        put(nx + sd, ny, sk[3])
        put(nx, ny, sk[2])
        put(nx - sd, ny - 3, sk[0])
    mm = face["mouth"]
    if face["fwd_dot"] > 0.35:
        x0, y0 = int(round(mm["x"] - 0.5)), int(round(mm["y"]))
        beard = spec.get("beard") and spec.get("beard_style", "goatee") in ("short", "full")
        col = hair[3] * 0.5 + INK * 0.5 if beard else lip
        xs = [x0 - 1, x0, x0 + 1] if face["fwd_dot"] > 0.7 else ([x0, x0 + 1] if fx >= 0 else [x0 - 1, x0])
        for x in xs:
            if 0 <= x < nw and 0 <= y0 < nh and alpha[y0, x] and dpx[y0, x] <= mm["t"] + 0.05 and pid[y0, x] in (skin, PARTS.index("hair")):
                out[y0, x, :3] = col
        if not beard:
            put(x0, y0 + 1, sk[2])


def _compose(idimg, nrm, dep, pal, face=None, spec=None):
    """三遍渲染 → 一帧像素画（FRAME×FRAME，RGBA 0..1）。pal：部位 × 4 档（高光 / 亮 / 中 / 暗）"""
    nh, nw, S, k = FRAME, FRAME_W, SS, len(PARTS)
    q = np.where(idimg[..., :3] >= 0.85, 1.0, np.where(idimg[..., :3] <= 0.15, 0.0, 0.5))
    ids = np.full(idimg.shape[:2], -1, dtype=np.int32)
    opaque = idimg[..., 3] > 0.5
    for i in range(min(k, len(_ID_RGB))):
        r, g, b = _ID_RGB[i]
        ids[opaque & (q[..., 0] == r) & (q[..., 1] == g) & (q[..., 2] == b)] = i
    a = ids >= 0
    # S×S 合并：覆盖一半以上才算不透明；部位取多数，五官这类小部位只要占到几个子像素就保留
    cnt = a.reshape(nh, S, nw, S).sum(axis=(1, 3))
    alpha = cnt >= (S * S) // 2
    votes = np.stack([(ids == i).reshape(nh, S, nw, S).sum(axis=(1, 3)) for i in range(k)], axis=2)
    pid = votes.argmax(axis=2)
    for part, need in PRIORITY.items():
        pi = PARTS.index(part)
        pid[votes[..., pi] >= need * S * S / 16.0] = pi
    # 只用属于这个部位的子像素算法线和深度（边界上不会被别的部位拉偏）
    mine = ids == np.repeat(np.repeat(pid, S, 0), S, 1)
    nv = nrm[..., :3] * 2.0 - 1.0
    ns = (nv * mine[..., None]).reshape(nh, S, nw, S, 3).sum(axis=(1, 3))
    ns /= np.maximum(np.linalg.norm(ns, axis=2, keepdims=True), 1e-6)
    dv = (dep[..., 0] - 0.5) * DEPTH_RANGE
    dpx = np.where(mine, dv, -9.0).reshape(nh, S, nw, S).max(axis=(1, 3))
    lum = ns @ LIGHT_DIR
    skin_i = PARTS.index("skin")
    lum = np.where(pid == skin_i, (ns @ SKIN_LIGHT) * 0.75 + 0.2, lum)
    tone = np.select([lum > TONES[0], lum > TONES[1], lum > TONES[2]], [0, 1, 2], 3)
    gloss = ns @ HALF_DIR
    for part, thr in SHINY.items():
        pi = PARTS.index(part)
        tone[(pid == pi) & (gloss > thr)] = 0
    for part, t in _FLAT_TONE.items():
        tone[pid == PARTS.index(part)] = t
    tone[~alpha] = 0
    # 清理孤立像素：上下左右四个邻居都是同一部位、同一档，而它不一样 → 跟邻居一样（像素画里的「去杂点」），做两遍
    for _pass in range(2):
        nb = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        same = np.ones_like(alpha)
        ref = np.roll(np.roll(tone, 1, 0), 0, 1)
        for dy, dx in nb:
            pt = np.roll(np.roll(pid, dy, 0), dx, 1)
            tt = np.roll(np.roll(tone, dy, 0), dx, 1)
            aa = np.roll(np.roll(alpha, dy, 0), dx, 1)
            same &= aa & (pt == pid) & (tt == ref)
        fix = alpha & same & (tone != ref) & ~np.isin(pid, [PARTS.index(p) for p in PRIORITY])
        tone[fix] = ref[fix]
    # 臂章 / 袖箍：锯齿形花纹（亮、暗两档交替）
    bi = PARTS.index("band")
    yy, xx = np.mgrid[0:nh, 0:nw]
    zig = ((xx + np.abs((yy % 4) - 2)) % 4) < 2
    mb = (pid == bi) & alpha
    tone[mb & zig] = np.minimum(tone, 1)[mb & zig]
    tone[mb & ~zig] = np.maximum(tone, 2)[mb & ~zig]
    # 毛皮：明暗档按固定的随机颗粒上下浮动一档，看起来毛茸茸的
    fi = PARTS.index("fur")
    grain = (np.sin(xx * 12.9898 + yy * 78.233) * 43758.5453) % 1.0
    mf = (pid == fi) & alpha
    tone[mf & (grain < 0.28)] = np.maximum(tone - 1, 1)[mf & (grain < 0.28)]
    tone[mf & (grain > 0.72)] = np.minimum(tone + 1, 3)[mf & (grain > 0.72)]
    out = np.zeros((nh, nw, 4))
    out[..., :3] = pal[pid, tone]
    out[..., 3] = alpha
    # 内部分界线：邻居明显在前面（遮住了这里）→ 这个像素画成本部位的暗色（压一点墨色）。
    # 不同部位之间门槛低（领口、袖口、胸甲边都能勾出来），同一部位只在大的前后落差处勾（手臂挡在身前）
    line = np.zeros((nh, nw), dtype=bool)
    for dy, dx in nb:
        pa = np.roll(np.roll(alpha, dy, 0), dx, 1)
        pd = np.roll(np.roll(dpx, dy, 0), dx, 1)
        pp = np.roll(np.roll(pid, dy, 0), dx, 1)
        thr = np.where(pp == pid, 0.07, 0.022)
        thr = np.where(pid == PARTS.index("skin"), np.maximum(thr, 0.06), thr)  # 脸 / 手只在明显的遮挡处勾线（下巴下面不要一道「胡子」）
        line |= alpha & pa & (pd > dpx + thr)
    line &= ~np.isin(pid, [PARTS.index(p) for p in ("eye", "glow")])
    out[line, :3] = pal[pid[line], 3] * 0.72 + INK * 0.28
    if face is not None:
        _stamp_face(out, pid, alpha, dpx, pal, face, spec or {})
    # 外描边：透明像素只要上下左右挨着角色，就涂成相邻部位的暗色再压一层墨色
    edge = np.zeros((nh, nw), dtype=bool)
    edge_col = np.zeros((nh, nw, 3))
    for dy, dx in nb:
        na = np.roll(np.roll(alpha, dy, 0), dx, 1)
        npid = np.roll(np.roll(pid, dy, 0), dx, 1)
        m = ~alpha & na & ~edge
        edge_col[m] = pal[npid[m], 3] * 0.45 + INK * 0.55
        edge |= m
    out[edge, :3] = edge_col[edge]
    out[edge, 3] = 1.0
    return out


def _palette(spec):
    """部位 × 4 档：规格给的三色色阶前面再加一档高光（亮色往暖白提一点）"""
    r = charspec.ramps(spec)
    pal = np.zeros((len(PARTS), 4, 3))
    for i, key in enumerate(PARTS):
        c = [_hex(x) for x in r[key]]
        hi = c[0] + (np.array([1.0, 0.97, 0.88]) - c[0]) * HILITE.get(key, 0.18)
        pal[i] = np.array([hi, c[0], c[1], c[2]])
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
    sheet = np.zeros((DIRS * FRAME, n * FRAME_W, 4), dtype=np.float32)
    for f in range(n):
        pose = poses.sample(anim, f, actions)
        mb = build_character(spec, pose)
        obj = mb.build_flat("pw_char_%s_%s_%d" % (spec["id"], anim, f))
        for d in range(DIRS):
            _place_camera(cam, d)
            face = _project_marks(mb.marks, cam)
            idimg = _render(os.path.join(tmpdir, "id.png"), "id")
            nrm = _render(os.path.join(tmpdir, "nrm.png"), "nrm")
            _set_depth(obj, cam)
            dep = _render(os.path.join(tmpdir, "dep.png"), "dep")
            sheet[d * FRAME:(d + 1) * FRAME, f * FRAME_W:(f + 1) * FRAME_W] = _compose(idimg, nrm, dep, pal, face, spec)
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
    entry = {"id": spec["id"], "name": spec["name"], "desc": spec["desc"], "style": spec.get("style", ""), "anims": {}}
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
            cells.append(sheets["idle"][d * FRAME:(d + 1) * FRAME, 0:FRAME_W])
    for anim, sh in sheets.items():
        if anim == "idle":
            continue
        n = sh.shape[1] // FRAME_W
        f = n // 2
        cells.append(sh[1 * FRAME:2 * FRAME, f * FRAME_W:(f + 1) * FRAME_W])
    if not cells:
        return
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    _save_png(np.concatenate(cells, axis=1), path)


def catalog_header():
    origin_y = FRAME / 2 + TARGET_Z * math.cos(ELEV) * PX_PER_M
    return {
        "version": 2, "generator": "pixel_world_blender sprites %s" % VERSION, "blender": bpy.app.version_string,
        "frame": FRAME, "frame_w": FRAME_W, "px_per_m": PX_PER_M, "origin": [FRAME_W / 2, round(origin_y, 2)], "dirs": DIRS,
        "elev_deg": round(math.degrees(ELEV), 2), "view_pitch_deg": VIEW_PITCH,
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
