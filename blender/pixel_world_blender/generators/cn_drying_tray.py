"""晒东西的竹匾：四条外撇的竹腿架子上放一只大圆竹匾（直径约 1.3 米），匾里摊着晒的东西。
变体 0 红辣椒，1 黄豆 / 花生（土黄色），2 玉米粒（金黄），3 一高一低两只匾（辣椒 + 豆子）。原点在架子中心地面。"""
import math

from ..builder import MeshBuilder

NAME = "晒匾"
CATEGORY = "props"
DESC = "Blender 生成的晒匾：竹架子上的大圆竹匾，摊着红辣椒、豆子或玉米粒在院子里晒。"
VARY = "变体 0 红辣椒、1 豆子、2 玉米粒、3 两只匾。"
TAGS = ["cn_village", "yard"]
VARIANTS = 4

FILL = ["fruit_red", "sand", "fruit_yellow"]


def tray(mb, cx, cy, h, r, fill):
    for i in range(4):  # 外撇的竹腿 + 一圈横撑
        a = math.pi / 4 + i * math.pi / 2
        top = (cx + math.cos(a) * r * 0.62, cy + math.sin(a) * r * 0.62, h)
        bot = (cx + math.cos(a) * r * 0.85, cy + math.sin(a) * r * 0.85, 0.0)
        mb.tube("bamboo", bot, top, 0.028, 0.026, 6)
        a2 = a + math.pi / 2
        mid = lambda aa: (cx + math.cos(aa) * r * 0.76, cy + math.sin(aa) * r * 0.76, h * 0.42)  # noqa: E731
        mb.tube("bamboo", mid(a), mid(a2), 0.018, 0.018, 5)
    mb.frustum("bamboo", cx, cy, h, h + 0.05, r * 0.94, r, 16, bottom=True, top=False)   # 匾底
    mb.frustum("bamboo", cx, cy, h + 0.05, h + 0.1, r, r * 1.02, 16, top=False)          # 匾沿
    mb.frustum(fill, cx, cy, h + 0.05, h + 0.085, r * 0.93, r * 0.9, 16)                 # 摊开的东西
    mb.frustum(fill, cx + r * 0.15, cy - r * 0.1, h + 0.085, h + 0.12, r * 0.5, r * 0.3, 12)


def build(seed, **over):
    k = (seed - 1) % 4
    mb = MeshBuilder()
    if k < 3:
        tray(mb, 0.0, 0.0, 0.72, 0.66, FILL[k])
        fp, hh = [1.4, 1.4], 0.85
    else:
        tray(mb, -0.62, 0.1, 0.78, 0.6, "fruit_red")
        tray(mb, 0.6, -0.12, 0.62, 0.56, "sand")
        fp, hh = [2.5, 1.5], 0.9
    return mb, {"footprint": fp, "height": hh, "params": {"fill": FILL[k] if k < 3 else "mixed"}}
