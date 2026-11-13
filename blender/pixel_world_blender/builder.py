"""网格构建：和 Godot 端 pw_mesh_builder.gd 同样的思路——按材质分组的面，UV 以「米」为单位投影，
再按 32 texel / 米 换算成贴图重复次数，所以所有资产的像素颗粒大小一致。
最后生成一个 Blender 网格对象，材质用最近邻（Closest）取样的像素贴图。
"""
import math

import bpy
import numpy as np

from . import pixtex
from . import style as S

# 材质定义：key -> (贴图生成函数, 贴图像素尺寸)。贴图按需生成并缓存（每次运行一份）
_TEX = {
    "wall_red": lambda: pixtex.planks(["red_0", "red_1", "red_2", "red_3"], 101),
    "wall_ochre": lambda: pixtex.planks(["ochre_0", "ochre_1", "ochre_2", "ochre_3"], 102),
    "wall_teal": lambda: pixtex.planks(["teal_0", "teal_1", "teal_2", "teal_3"], 103),
    "wall_wood": lambda: pixtex.planks(["wood_0", "wood_1", "wood_2", "wood_3"], 104),
    "roof_grey": lambda: pixtex.shingles(["stone_0", "roof_0", "roof_1", "roof_2"], 201),
    "roof_red": lambda: pixtex.shingles(["red_0", "red_1", "red_2", "red_3"], 202),
    "stone": lambda: pixtex.bricks(["stone_0", "stone_1", "stone_2", "stone_3"], 401),
    "brick": lambda: pixtex.bricks(["red_1", "red_2", "red_2", "red_3"], 402, brick_w=12),
    "trim": lambda: pixtex.mottle(["frame_0", "frame_1"], 301),
    "trunk": lambda: pixtex.planks(["wood_1", "wood_2", "wood_2", "wood_3"], 505, size=32, plank_w=3),
    "pine": lambda: pixtex.foliage(["pine_1", "pine_0", "pine_2"], 501),
    "pine_skirt": lambda: pixtex.foliage(["pine_2", "pine_1", "pine_3"], 502, droop=True),
    "canvas_red": lambda: pixtex.stripes(["red_0", "frame_0"], 601),
    "canvas_teal": lambda: pixtex.stripes(["teal_1", "frame_0"], 602),
    "canvas_ochre": lambda: pixtex.stripes(["ochre_0", "frame_0"], 603),
    "metal": lambda: pixtex.mottle(["stone_3", "ink"], 604),
    "door": lambda: pixtex.planks(["wood_0", "wood_1", "wood_2", "wood_3"], 111, plank_w=6),
    "glass": lambda: pixtex.window(),
    "water": lambda: pixtex.mottle([S.c("water_2"), S.c("water_1")], 605, size=16),
    "fruit_red": lambda: pixtex.mottle(["red_0", "red_1"], 606, size=16),
    "fruit_yellow": lambda: pixtex.mottle(["cloth_yellow", "ochre_0"], 607, size=16),
    "fruit_green": lambda: pixtex.mottle(["grass_0", "grass_1"], 608, size=16),
    "leaf": lambda: pixtex.foliage(["grass_1", "grass_0", "grass_2"], 511),
    "leaf_dark": lambda: pixtex.foliage(["grass_2", "grass_1", "pine_1"], 512, droop=True),
    "metal_green": lambda: pixtex.mottle(["teal_2", "teal_3"], 611),
    "bulb": lambda: pixtex.mottle(["light_0", "light_1"], 612, size=16),
    "hay": lambda: pixtex.stripes(["cloth_yellow", "ochre_0"], 613, width=3),
    "crate": lambda: pixtex.planks(["ochre_1", "ochre_2", "ochre_2", "ochre_3"], 614, size=32, plank_w=6),
}
# 整张贴图铺满一个面（UV 0..1）而不是按米平铺的材质
_STRETCH = {"glass"}

_mat_cache = {}
_arr_cache = {}


def texture_array(key):
    if key not in _arr_cache:
        _arr_cache[key] = _TEX[key]()
    return _arr_cache[key]


def material(key):
    if key in _mat_cache and _mat_cache[key].name in bpy.data.materials:
        return _mat_cache[key]
    arr = texture_array(key)
    h, w = arr.shape[:2]
    img = bpy.data.images.new("pw_" + key, width=w, height=h, alpha=False)
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[..., :3] = arr[::-1]  # Blender 图像第 0 行在底部
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    mat = bpy.data.materials.new("pw_" + key)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"  # 最近邻：glTF 导出为 NEAREST 采样
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    mat["pw_key"] = key  # Godot 端用它把材质换成统一的 pixel_world 材质
    _mat_cache[key] = mat
    return mat


def tex_size(key):
    arr = texture_array(key)
    return arr.shape[1], arr.shape[0]


class MeshBuilder:
    """按材质收集多边形；UV 自动投影（米 → 贴图重复次数）"""

    def __init__(self):
        self.verts = []
        self.faces = []      # (顶点索引列表, 材质键, uv 列表)
        self.mats = []

    def _mat_index(self, key):
        if key not in self.mats:
            self.mats.append(key)
        return self.mats.index(key)

    def face(self, key, pts, outward=None):
        pts = [np.asarray(p, dtype=float) for p in pts]
        n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
        ln = np.linalg.norm(n)
        if ln < 1e-9:
            return
        n /= ln
        if outward is not None and np.dot(n, outward) < 0:
            pts = pts[::-1]
            n = -n
        # 投影轴：u 沿水平切线，v 沿面内向上（与 Godot 端一致）
        up = np.array([0.0, 0.0, 1.0])  # Blender 是 Z 向上
        u_axis = np.cross(n, up)
        if np.linalg.norm(u_axis) < 1e-4:
            u_axis = np.array([1.0, 0.0, 0.0])
        u_axis /= np.linalg.norm(u_axis)
        v_axis = np.cross(u_axis, n)
        v_axis /= np.linalg.norm(v_axis)
        if key in _STRETCH:
            uvs = [(0, 1), (1, 1), (1, 0), (0, 0)][: len(pts)]
        else:
            tw, th = tex_size(key)
            d = S.texel_density()
            uvs = [(float(np.dot(p, u_axis)) * d / tw, float(np.dot(p, v_axis)) * d / th) for p in pts]
        base = len(self.verts)
        self.verts.extend(pts)
        self.faces.append((list(range(base, base + len(pts))), key, uvs))

    def box(self, key, mn, mx, top=True, bottom=False, sides=True):
        (x0, y0, z0), (x1, y1, z1) = mn, mx
        if sides:
            self.face(key, [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], (1, 0, 0))
            self.face(key, [(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)], (-1, 0, 0))
            self.face(key, [(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)], (0, 1, 0))
            self.face(key, [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0))
        if top:
            self.face(key, [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1))
        if bottom:
            self.face(key, [(x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0)], (0, 0, -1))

    def frustum(self, key, cx, cy, z0, z1, r0, r1, sides=8, rot=0.0, top=True, bottom=False):
        """正 N 边形棱台（Z 向上）"""
        b = [(cx + math.cos(rot + 2 * math.pi * i / sides) * r0, cy + math.sin(rot + 2 * math.pi * i / sides) * r0, z0) for i in range(sides)]
        t = [(cx + math.cos(rot + 2 * math.pi * i / sides) * r1, cy + math.sin(rot + 2 * math.pi * i / sides) * r1, z1) for i in range(sides)]
        for i in range(sides):
            j = (i + 1) % sides
            mid = ((b[i][0] + b[j][0]) * 0.5 - cx, (b[i][1] + b[j][1]) * 0.5 - cy, 0)
            if r1 <= 1e-4:
                self.face(key, [b[i], b[j], t[i]], mid)
            else:
                self.face(key, [b[i], b[j], t[j], t[i]], mid)
        if top and r1 > 1e-4:
            self.face(key, t, (0, 0, 1))
        if bottom:
            self.face(key, b[::-1], (0, 0, -1))

    def tube(self, key, p0, p1, r0, r1, sides=6, rot=0.0, caps=True):
        """任意方向的 N 边形棱台：从 p0（半径 r0）到 p1（半径 r1）。树枝、车轮、灯臂都用它。"""
        p0 = np.asarray(p0, dtype=float)
        p1 = np.asarray(p1, dtype=float)
        ax = p1 - p0
        ln = np.linalg.norm(ax)
        if ln < 1e-6:
            return
        ax /= ln
        ref = np.array([0.0, 0.0, 1.0]) if abs(ax[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
        u = np.cross(ax, ref)
        u /= np.linalg.norm(u)
        v = np.cross(ax, u)
        ring = [math.cos(rot + 2 * math.pi * i / sides) * u + math.sin(rot + 2 * math.pi * i / sides) * v for i in range(sides)]
        a = [p0 + d * r0 for d in ring]
        b = [p1 + d * r1 for d in ring]
        for i in range(sides):
            j = (i + 1) % sides
            out = (ring[i] + ring[j]) * 0.5
            if r1 <= 1e-4:
                self.face(key, [a[i], a[j], p1], out)
            else:
                self.face(key, [a[i], a[j], b[j], b[i]], out)
        if caps:
            self.face(key, a[::-1], -ax)
            if r1 > 1e-4:
                self.face(key, b, ax)

    def blob(self, key, cx, cy, cz, r, h, sides=8, rot=0.0):
        """低多边形的团块（阔叶树冠的一簇）：下收的碗底 + 鼓起的腰 + 圆顶，三段棱台叠成。"""
        z0, z1, z2, z3 = cz - h * 0.5, cz - h * 0.1, cz + h * 0.2, cz + h * 0.5
        self.frustum(key, cx, cy, z0, z1, r * 0.55, r, sides, rot, top=False, bottom=True)
        self.frustum(key, cx, cy, z1, z2, r, r * 0.9, sides, rot, top=False)
        self.frustum(key, cx, cy, z2, z3, r * 0.9, r * 0.35, sides, rot, top=True)

    def build(self, name, collection=None):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in self.verts], [], [f[0] for f in self.faces])
        uv = me.uv_layers.new(name="UVMap")
        li = 0
        for pi, (idx, key, uvs) in enumerate(self.faces):
            poly = me.polygons[pi]
            poly.material_index = self._mat_index(key)
            for k in range(poly.loop_total):
                uv.data[poly.loop_start + k].uv = uvs[k]
        for key in self.mats:
            me.materials.append(material(key))
        me.validate()
        me.update()
        obj = bpy.data.objects.new(name, me)
        (collection or bpy.context.scene.collection).objects.link(obj)
        return obj
