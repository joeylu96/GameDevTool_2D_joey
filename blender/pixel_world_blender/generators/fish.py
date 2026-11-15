"""小鱼：菱形身体 + 背鳍 + 双面尾鳍，长约 0.3 米。变体 0 = 橙色，1 = 银色。
朝向和 Godot 端 build_fish 一致：Godot 里头朝 +Z（这里头朝 -Y，导出后对应 Godot +Z）。"""
from ..builder import MeshBuilder

NAME = "小鱼"
CATEGORY = "water"
DESC = "Blender 生成的小鱼：菱形身体、背鳍和尾鳍，橙色和银色两种，成群在湖里游。"
VARY = "两种颜色（变体 0 橙色、1 银色）。"
TAGS = ["shore"]
VARIANTS = 2


def _g(x, y, z):
    """Godot 坐标 → Blender 坐标"""
    return (x, -z, y)


def build(seed, **over):
    mat = "fish_orange" if seed % 2 == 1 else "fish_silver"
    mb = MeshBuilder()
    nose = _g(0, 0, 0.16)
    tail = _g(0, 0, -0.12)
    ring = [_g(0, 0.05, 0.02), _g(0.04, 0, 0.02), _g(0, -0.04, 0.02), _g(-0.04, 0, 0.02)]
    center = _g(0, 0, 0.02)
    for i in range(4):
        a, b = ring[i], ring[(i + 1) % 4]
        for tip in (nose, tail):
            out = tuple((tip[k] + a[k] + b[k]) / 3.0 - center[k] for k in range(3))
            mb.face(mat, [tip, a, b], out)
    fin = [_g(0, 0, -0.1), _g(0, 0.07, -0.2), _g(0, -0.07, -0.2)]
    mb.face(mat, fin, (1, 0, 0))
    mb.face(mat, fin, (-1, 0, 0))
    dorsal = [_g(0, 0.045, 0.05), _g(0, 0.085, -0.02), _g(0, 0.04, -0.04)]
    mb.face(mat, dorsal, (1, 0, 0))
    mb.face(mat, dorsal, (-1, 0, 0))
    return mb, {"footprint": [0.1, 0.4], "height": 0.1, "plant": False}
