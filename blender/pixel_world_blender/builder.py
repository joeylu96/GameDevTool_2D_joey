"""网格构建：和 Godot 端 pw_mesh_builder.gd 同样的思路——按材质分组的面，UV 以「米」为单位投影，
再按 32 texel / 米 换算成贴图重复次数，所以所有资产的像素颗粒大小一致。
最后生成一个 Blender 网格对象，材质用最近邻（Closest）取样的像素贴图。
"""
import math

import bmesh
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
    # 横木板墙：竖木板贴图转 90°
    "siding_white": lambda: np.ascontiguousarray(np.transpose(pixtex.planks(["frame_0", "frame_0", "frame_1", "snow_2"], 121), (1, 0, 2))),
    "siding_ochre": lambda: np.ascontiguousarray(np.transpose(pixtex.planks(["ochre_0", "ochre_1", "ochre_2", "ochre_3"], 122), (1, 0, 2))),
    "plaster_white": lambda: pixtex.mottle(["frame_0", "frame_1"], 131, threshold=0.75),
    "plaster_red": lambda: pixtex.mottle(["red_0", "red_1"], 132, threshold=0.75),
    "palm_leaf": lambda: pixtex.foliage(["grass_0", "grass_1", "grass_2"], 521, droop=True),
    "cactus": lambda: pixtex.planks(["teal_1", "teal_2", "grass_2", "teal_3"], 522, size=32, plank_w=4),
    "snow": lambda: pixtex.mottle(["snow_0", "snow_1"], 621, threshold=0.7),
    "sand": lambda: pixtex.mottle(["ochre_0", "dirt_0"], 622, threshold=0.6),
    "rock_red": lambda: pixtex.bricks(["ochre_1", "ochre_2", "red_2", "ochre_3"], 623, brick_w=20, row_h=10),
    "coal": lambda: pixtex.mottle(["ink", "stone_3"], 624, size=16),
    "cloth_blue": lambda: pixtex.mottle(["cloth_blue", "teal_2"], 625, threshold=0.7),
    # 和 Godot 端 pw_materials.gd 同名的材质（Godot 换材质后积雪、摇摆、发光行为一致）
    "birch_bark": lambda: pixtex.bark_marks(531),
    "leaf_birch": lambda: pixtex.foliage([S.mix("grass_0", "cloth_yellow", 0.15), S.mix("grass_0", "light_0", 0.35), S.c("grass_1")], 532),
    "leaf_birch_dark": lambda: pixtex.foliage(["grass_1", "grass_0", "grass_2"], 533, droop=True),
    "flowers": lambda: pixtex.flowers(534),
    "rock": lambda: pixtex.mottle(["stone_1", "stone_0"], 535, size=64, threshold=0.55),
    "barrel": lambda: pixtex.planks(["wood_0", "wood_1", "wood_2", "wood_3"], 536, size=32, plank_w=5),
    "boards": lambda: np.ascontiguousarray(np.transpose(pixtex.planks(["wood_0", "wood_1", "wood_2", "wood_3"], 537, size=32, plank_w=4), (1, 0, 2))),
    "deck": lambda: np.ascontiguousarray(np.transpose(pixtex.planks(["ochre_1", "wood_0", "wood_1", "wood_2"], 538, size=32, plank_w=4), (1, 0, 2))),
    "curb": lambda: pixtex.mottle(["snow_3", "stone_0"], 539, threshold=0.6),
    "weed": lambda: pixtex.foliage(["teal_1", "grass_2", "teal_2"], 540, size=32, droop=True),
    "fish_orange": lambda: pixtex.mottle(["light_2", "ochre_0"], 541, size=16),
    "fish_silver": lambda: pixtex.mottle(["stone_0", "snow_3"], 542, size=16),
    "door_red": lambda: pixtex.planks(["red_0", "red_1", "red_2", "red_3"], 543, plank_w=6),
    "door_teal": lambda: pixtex.planks(["teal_0", "teal_1", "teal_2", "teal_3"], 544, plank_w=6),
    "door_green": lambda: pixtex.planks(["grass_1", "pine_0", "pine_1", "pine_2"], 545, plank_w=6),
    "door_wood": lambda: pixtex.planks(["wood_0", "wood_1", "wood_2", "wood_3"], 546, plank_w=6),
    "roof_cap": lambda: pixtex.mottle(["roof_2", "stone_3"], 547),
    "roof_under": lambda: pixtex.planks(["wood_1", "wood_2", "wood_2", "wood_3"], 548),
    "brass": lambda: pixtex.mottle(["light_1", "light_2"], 549, size=16),
    # 草叶：整面铺满的竖向渐变（行 0 = 根部深绿，最后一行 = 尖端浅色），见 _STRETCH
    "blade": lambda: pixtex.gradient(S.mix("grass_2", "grass_1", 0.3), S.mix("grass_0", "light_0", 0.25)),
    "blade_dry": lambda: pixtex.gradient(S.mix("grass_2", "dirt_1", 0.5), "ochre_0"),
    # 中世纪小镇
    "timber": lambda: pixtex.planks(["wood_2", "wood_3", S.mix("wood_3", "ink", 0.4), "ink"], 551, size=32, plank_w=8),
    "plaster_ochre": lambda: pixtex.mottle([S.mix("ochre_0", "frame_0", 0.55), S.mix("ochre_0", "frame_1", 0.35)], 552, threshold=0.72),
    "thatch": lambda: pixtex.thatch(553),
    "slate": lambda: pixtex.shingles(["stone_1", "roof_1", "roof_2", "ink"], 554, row_h=6, sw=10),
    # --- medieval seaside (fork A)：米白石灰岩建筑 + 鲜红瓦顶（参考 res/中世纪海边小镇.jpg）
    "castle_stone": lambda: pixtex.bricks([S._hex("f3ead4"), S._hex("e6dabd"), S._hex("d2c3a0"), S._hex("b9aa88")], 555, brick_w=20, row_h=10),
    "cobble_wall": lambda: pixtex.bricks([S._hex("e2d3b2"), S._hex("cdbb96"), S._hex("b5a17c"), S._hex("93815f")], 556, brick_w=10, row_h=7),
    "plaster_cream": lambda: pixtex.mottle([S._hex("f4eddb"), S._hex("e9dfc8")], 562, size=64, threshold=0.7),
    "tile_red": lambda: pixtex.shingles([S._hex("e8694f"), S._hex("cf4631"), S._hex("b23527"), S._hex("7d2620")], 563, row_h=6, sw=8),
    "tile_darkred": lambda: pixtex.shingles([S._hex("b5503f"), S._hex("96392f"), S._hex("7c2d28"), S._hex("531e1d")], 564, row_h=6, sw=8),
    "stone_greygreen": lambda: pixtex.bricks([S._hex("c9cfc0"), S._hex("aeb6a6"), S._hex("929b8c"), S._hex("747c70")], 565, brick_w=20, row_h=10),
    "sail": lambda: pixtex.mottle([S._hex("f1e6c8"), S._hex("e0d2ae")], 566, size=32, threshold=0.6),
    "hull": lambda: np.ascontiguousarray(np.transpose(pixtex.planks(["wood_1", "wood_2", "wood_3", "ink"], 567, size=32, plank_w=5), (1, 0, 2))),
    # --- end fork A
    "forge_coal": lambda: pixtex.mottle(["light_2", "red_0"], 557, size=16, threshold=0.55),
    "glass_lead": lambda: pixtex.leaded_glass(),
    "cloth_red": lambda: pixtex.mottle(["red_1", "red_0"], 558, threshold=0.7),
    "cloth_green": lambda: pixtex.mottle(["pine_0", "cloth_green"], 559, threshold=0.7),
    "cloth_gold": lambda: pixtex.mottle(["cloth_yellow", "ochre_0"], 560, size=16, threshold=0.7),
    "iron": lambda: pixtex.mottle(["stone_3", S.mix("stone_3", "ink", 0.5)], 561, size=16),
    # 现代风格：抹灰外墙、木 / 深色挂板、金属屋面、大玻璃、钢、混凝土、车漆
    "render_white": lambda: pixtex.mottle(["frame_0", S.mix("frame_0", "snow_2", 0.4)], 801, size=64, threshold=0.72),
    "render_grey": lambda: pixtex.mottle([S.mix("stone_0", "snow_1", 0.45), S.mix("stone_0", "snow_1", 0.3)], 802, size=64, threshold=0.7),
    "render_sand": lambda: pixtex.mottle([S.mix("dirt_0", "frame_0", 0.55), S.mix("dirt_0", "frame_0", 0.4)], 803, size=64, threshold=0.7),
    "clad_wood": lambda: np.ascontiguousarray(np.transpose(pixtex.planks(["ochre_1", "wood_0", "wood_1", "wood_2"], 804, size=32, plank_w=4), (1, 0, 2))),
    "clad_dark": lambda: np.ascontiguousarray(np.transpose(pixtex.planks([S.mix("stone_2", "stone_1", 0.5), "stone_2", "stone_3", "ink"], 805, size=32, plank_w=4), (1, 0, 2))),
    "metal_roof": lambda: pixtex.planks(["roof_0", "roof_1", "roof_2", "ink"], 806, size=32, plank_w=8),
    "glass_modern": lambda: pixtex.glass_pane(),
    "glass_car": lambda: pixtex.glass_pane(),
    "steel": lambda: pixtex.mottle(["stone_0", S.mix("stone_0", "snow_2", 0.5)], 807, size=16),
    "concrete": lambda: pixtex.mottle([S.mix("stone_0", "snow_2", 0.3), "stone_0"], 808, size=64, threshold=0.62),
    "paint_red": lambda: pixtex.mottle(["red_0", S.mix("red_0", "light_0", 0.3)], 811, size=16, threshold=0.75),
    "paint_blue": lambda: pixtex.mottle(["cloth_blue", S.mix("cloth_blue", "snow_0", 0.3)], 812, size=16, threshold=0.75),
    "paint_white": lambda: pixtex.mottle(["snow_0", "snow_1"], 813, size=16, threshold=0.75),
    "paint_grey": lambda: pixtex.mottle(["stone_1", "stone_0"], 814, size=16, threshold=0.75),
    "paint_yellow": lambda: pixtex.mottle(["cloth_yellow", S.mix("cloth_yellow", "light_0", 0.4)], 815, size=16, threshold=0.75),
    "paint_teal": lambda: pixtex.mottle(["teal_1", "teal_0"], 816, size=16, threshold=0.75),
    "paint_black": lambda: pixtex.mottle(["stone_3", S.mix("stone_3", "ink", 0.5)], 817, size=16, threshold=0.7),
    "paint_green": lambda: pixtex.mottle(["cloth_green", "grass_1"], 818, size=16, threshold=0.75),
    "tyre": lambda: pixtex.mottle(["ink", S.mix("ink", "stone_3", 0.5)], 819, size=16),
    # 八九十年代中国乡村：红砖 / 青砖 / 土坯、白灰墙、小青瓦、红纸（对联，不写字）、水泥、釉面水缸
    "brick_red_cn": lambda: pixtex.bricks(["red_1", "red_2", "red_3", "frame_1"], 821, brick_w=14, row_h=6),
    "brick_grey": lambda: pixtex.bricks(["stone_0", "stone_1", "stone_2", "frame_1"], 822, brick_w=14, row_h=6),
    "mudbrick": lambda: pixtex.bricks(["dirt_0", "dirt_1", "dirt_2", "wood_2"], 823, brick_w=18, row_h=9),
    "whitewash": lambda: pixtex.mottle(["frame_0", S.mix("frame_0", "frame_1", 0.55)], 824, size=64, threshold=0.68),  # fork B：斑块对比降低，墙面干净
    "tile_cn": lambda: pixtex.cn_tiles(825),
    "red_paper": lambda: pixtex.mottle(["red_0", S.mix("red_0", "light_2", 0.3)], 826, size=16, threshold=0.75),
    "cement": lambda: pixtex.mottle(["stone_0", S.mix("stone_0", "snow_2", 0.35)], 827, size=64, threshold=0.6),
    "glaze": lambda: pixtex.mottle(["wood_2", S.mix("wood_2", "ochre_1", 0.4)], 828, size=16, threshold=0.7),
    # --- cn village remodel (fork B)：灰褐 / 红褐 / 深灰瓦、干垒石墙、竹子、旧红门、木格窗、玉米和麦子的叶片渐变
    "tile_cn_brown": lambda: pixtex.cn_tiles(831, cols=[S.mix("dirt_0", "stone_0", 0.5), S.mix("dirt_1", "stone_1", 0.5), S.mix("dirt_2", "stone_2", 0.5), S.mix("wood_3", "stone_3", 0.5)]),
    "tile_cn_red": lambda: pixtex.cn_tiles(832, cols=[S.mix("red_0", "dirt_0", 0.55), S.mix("red_1", "dirt_1", 0.5), S.mix("red_2", "dirt_2", 0.45), S.mix("red_3", "wood_3", 0.5)]),
    "tile_cn_dark": lambda: pixtex.cn_tiles(833, cols=["stone_1", "stone_2", S.mix("stone_2", "stone_3", 0.6), S.mix("stone_3", "ink", 0.4)]),
    "drystone": lambda: pixtex.bricks([S.mix("stone_0", "dirt_0", 0.4), "stone_0", S.mix("stone_1", "dirt_1", 0.4), "stone_2"], 834, brick_w=13, row_h=9),
    "bamboo": lambda: pixtex.planks([S.mix("ochre_0", "frame_1", 0.35), "ochre_0", "ochre_1", "ochre_2"], 835, size=32, plank_w=3),
    "door_oldred": lambda: pixtex.planks([S.mix("red_2", "wood_1", 0.3), "red_2", S.mix("red_3", "wood_2", 0.4), "red_3"], 836, plank_w=6),
    "whitewash_old": lambda: pixtex.mottle([S.mix("frame_0", "frame_1", 0.45), S.mix("frame_1", "dirt_0", 0.45)], 837, size=64, threshold=0.6),
    "glass_lattice": lambda: pixtex.lattice_window(),
    "render_cn": lambda: pixtex.mottle([S.mix("stone_0", "frame_1", 0.55), S.mix("stone_0", "frame_1", 0.42)], 838, size=64, threshold=0.66),
    "blade_corn": lambda: pixtex.gradient(S.mix("grass_2", "pine_1", 0.3), S.mix("grass_0", "cloth_yellow", 0.2)),
    "blade_wheat": lambda: pixtex.gradient(S.mix("grass_2", "grass_1", 0.5), S.mix("grass_0", "light_0", 0.4)),
    "blade_wheat_ripe": lambda: pixtex.gradient("ochre_1", S.mix("cloth_yellow", "light_0", 0.35)),
}
# 整张贴图铺满一个面（UV 0..1）而不是按米平铺的材质
_STRETCH = {"glass", "glass_lead", "blade", "blade_dry", "glass_modern", "glass_car",
            "glass_lattice", "blade_corn", "blade_wheat", "blade_wheat_ripe"}  # 最后一行：cn village remodel (fork B)

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


# ---------------------------------------------------------------- 圆滑规则（所有资产）
# 场景里的模型不要棱角分明（2026-11-16 定的规则，以后新加的生成器 / AI 规格摆件都自动遵守）：
#   1. 圆形部件（柱子、树冠、桶、管子）的边数有下限：半径 ≥ 0.15 米至少 12 边，再小的至少 8 边（细杆 4~6 边不变）
#   2. 导出前统一「柔化」：合并重合顶点让盒子连成一体 → 硬边（两面夹角 30°~150°）倒一道圆角斜边，宽度按物体大小 1.2~5 厘米
#      → 按 40° 平滑着色（大平面仍然平整，转折处是柔和的过渡，不再是一刀切的硬边）
#      植物（树、灌木、草，场景里成百上千棵）不倒角，只靠足够的边数 + 平滑着色变圆润，面数不至于翻好几倍
SOFT_MIN_SIDES_BIG = 12
SOFT_MIN_SIDES = 8
SOFT_BEVEL_ANGLE = (30.0, 150.0)
SOFT_SMOOTH_ANGLE = 40.0


def _round_sides(sides, r):
    if sides <= 4 and r < 0.04:
        return sides  # 很细的杆子、绳子保持原样（多了只是浪费面数）
    if r >= 0.15:
        return max(sides, SOFT_MIN_SIDES_BIG)
    if r >= 0.04:
        return max(sides, SOFT_MIN_SIDES)
    return sides


def soften_mesh(me, plant=False):
    """把网格的硬边倒成小圆角并按角度平滑着色（见上面的圆滑规则）；plant = True 只平滑着色不倒角"""
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    if len(bm.verts) == 0:
        bm.free()
        return
    xs = [v.co for v in bm.verts]
    size = max(max(c[i] for c in xs) - min(c[i] for c in xs) for i in range(3))
    width = min(0.05, max(0.012, size * 0.012))
    lo, hi = (math.radians(a) for a in SOFT_BEVEL_ANGLE)
    edges = []
    for e in ([] if plant else bm.edges):
        if len(e.link_faces) != 2:
            continue
        try:
            ang = e.calc_face_angle()
        except ValueError:
            continue
        if lo <= ang <= hi:
            edges.append(e)
    if edges:
        bmesh.ops.bevel(bm, geom=edges, offset=width, offset_type="OFFSET", segments=1, profile=0.5,
                        affect="EDGES", clamp_overlap=True)
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(SOFT_SMOOTH_ANGLE))
    me.update()


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
        if key in _STRETCH and len(pts) <= 4:
            uvs = [(0, 1), (1, 1), (1, 0), (0, 0)][: len(pts)]
        elif key in _STRETCH:
            # 多边形（拱窗、尖拱窗）：按面内包围盒把整张贴图铺满
            us = [float(np.dot(p, u_axis)) for p in pts]
            vs = [float(np.dot(p, v_axis)) for p in pts]
            du, dv = max(max(us) - min(us), 1e-6), max(max(vs) - min(vs), 1e-6)
            uvs = [((uu - min(us)) / du, (vv - min(vs)) / dv) for uu, vv in zip(us, vs)]
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
        sides = _round_sides(sides, max(r0, r1))
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
        sides = _round_sides(sides, max(r0, r1))
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

    def build(self, name, collection=None, soften=True, plant=False):
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
        if soften:
            soften_mesh(me, plant)
        obj = bpy.data.objects.new(name, me)
        (collection or bpy.context.scene.collection).objects.link(obj)
        return obj
