"""木栈桥（码头）：2.5 米宽 × 8 米长的木板栈桥模块，从岸边（原点）沿 -Y（导出后 Godot +Z）伸向水里。
约定：原点在靠岸一端的中点、水面高度 z = 0；桥面顶 z = 0.35，x ∈ [-1.25, 1.25]，y ∈ [-8, 0]；
木桩一直插到 z = -2（水下），多个模块可以首尾相接加长。变体 1、2 有高出桥面的系船桩、缆绳圈和货物。"""
from ..builder import MeshBuilder
from ._medieval import box

NAME = "木栈桥"
CATEGORY = "landmarks"
DESC = "Blender 生成的中世纪木栈桥：木板桥面、横梁和插进水里的木桩，从岸边伸向水里，船靠在两侧；有的带系船桩、缆绳和货箱。"
VARY = "变体 0 朴素、1 带系船桩和缆绳圈、2 再加木箱木桶。"
TAGS = ["medieval", "shore"]
VARIANTS = 3
W = 2.5
L = 8.0
TOP = 0.35


def build(seed, **over):
    k = (seed - 1) % 3
    mb = MeshBuilder()
    hw = W * 0.5
    # 桥面：横向木板（每块约 0.33 米）
    n = int(L / 0.33)
    for i in range(n):
        y1 = -L * i / n
        y0 = -L * (i + 1) / n + 0.03
        box(mb, "deck", -hw, y0, TOP - 0.1, hw, y1, TOP)
    # 两根纵梁 + 木桩（每 2 米一对）
    for sx in (-1, 1):
        box(mb, "timber", sx * (hw - 0.3) - 0.09, -L, TOP - 0.3, sx * (hw - 0.3) + 0.09, 0.0, TOP - 0.1)
    for j in range(5):
        y = -L * j / 4
        y = min(-0.15, max(y, -L + 0.15))
        box(mb, "timber", -hw, y - 0.08, TOP - 0.42, hw, y + 0.08, TOP - 0.3)
        for sx in (-1, 1):
            tall = k > 0 and j in (1, 3, 4)
            mb.frustum("trunk", sx * (hw - 0.02), y, -2.0, TOP + (0.75 if tall else 0.05), 0.14, 0.12, 10, 0.0, top=True)
            if tall:
                mb.frustum("iron", sx * (hw - 0.02), y, TOP + 0.5, TOP + 0.58, 0.135, 0.135, 10, 0.0, top=False)
    if k > 0:  # 缆绳圈
        for (x, y) in ((0.6, -6.6), (-0.5, -2.8)):
            for i in range(3):
                mb.frustum("hay", x, y, TOP + i * 0.07, TOP + 0.07 + i * 0.07, 0.3 - i * 0.03, 0.3 - i * 0.03, 12, 0.0, top=True)
    if k == 2:
        box(mb, "crate", -0.9, -5.2, TOP, -0.2, -4.5, TOP + 0.7)
        box(mb, "crate", -0.8, -4.4, TOP, -0.25, -3.85, TOP + 0.55)
        mb.frustum("barrel", 0.65, -4.6, TOP, TOP + 0.45, 0.28, 0.33, 12, 0.0, top=False)
        mb.frustum("barrel", 0.65, -4.6, TOP + 0.45, TOP + 0.9, 0.33, 0.28, 12, 0.0, top=True)
    return mb, {"footprint": [W, L], "height": 1.3,
                "params": {"width": W, "length": L, "deck_top": TOP, "axis": "-Y (Godot +Z) from origin at the quay end"}}
