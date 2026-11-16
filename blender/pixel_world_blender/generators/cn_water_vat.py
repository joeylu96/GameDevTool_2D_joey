"""水缸：酱褐色釉面的大陶缸，肩部鼓起、口沿外翻；变体 0 盖着圆木盖、1 敞口装满水、上面漂着一只葫芦瓢，2 小一号的腌菜坛。
原点在缸底中心地面。"""
from ..builder import MeshBuilder

NAME = "水缸"
CATEGORY = "props"
DESC = "Blender 生成的农家水缸：酱褐色釉面大陶缸，盖着木盖或敞口漂着葫芦瓢，还有小一号的腌菜坛。"
VARY = "变体 0 盖木盖的大缸、1 敞口大缸带水瓢、2 小坛子。"
TAGS = ["cn_village", "yard"]
VARIANTS = 3


def build(seed, **over):
    k = (seed - 1) % 3
    s = [1.0, 1.05, 0.55][k]
    mb = MeshBuilder()
    rings = [(0.0, 0.26), (0.18, 0.36), (0.42, 0.42), (0.62, 0.4), (0.74, 0.34), (0.8, 0.36)]
    for (z0, r0), (z1, r1) in zip(rings, rings[1:]):
        mb.frustum("glaze", 0.0, 0.0, z0 * s, z1 * s, r0 * s, r1 * s, 16, top=False, bottom=(z0 == 0.0))
    top = 0.8 * s
    mb.frustum("glaze", 0.0, 0.0, top, top + 0.03 * s, 0.37 * s, 0.37 * s, 16, top=False)  # 口沿
    if k == 0:
        mb.frustum("boards", 0.0, 0.0, top + 0.03 * s, top + 0.08 * s, 0.4 * s, 0.4 * s, 16)
        mb.frustum("wall_wood", 0.0, 0.0, top + 0.08 * s, top + 0.13 * s, 0.08, 0.06, 8)
        h = top + 0.13 * s
    elif k == 1:
        mb.frustum("water", 0.0, 0.0, top - 0.06, top - 0.05, 0.33 * s, 0.33 * s, 16)
        mb.blob("hay", 0.1, 0.05, top - 0.02, 0.13, 0.1, 8)
        mb.tube("hay", (0.18, 0.05, top - 0.02), (0.38, 0.05, top + 0.08), 0.03, 0.025, 6)
        h = top + 0.08
    else:
        mb.frustum("glaze", 0.0, 0.0, top + 0.03 * s, top + 0.12 * s, 0.24 * s, 0.2 * s, 12)
        mb.frustum("cloth_red", 0.0, 0.0, top + 0.12 * s, top + 0.16 * s, 0.22 * s, 0.18 * s, 12)  # 封口的红布
        h = top + 0.16 * s
    return mb, {"footprint": [round(0.9 * s, 2), round(0.9 * s, 2)], "height": round(h, 2), "params": {"scale": s}}
