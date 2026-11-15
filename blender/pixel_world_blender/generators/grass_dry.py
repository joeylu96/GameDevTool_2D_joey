"""干草丛：偏黄的草叶（沙滩、岩石附近）。"""
from ._grass import build_tuft

NAME = "干草丛"
CATEGORY = "plants"
DESC = "Blender 生成的干草丛：偏黄的细长草叶，长在沙滩和岩石附近。"
VARY = "草叶数量、高度、倾斜方向随种子变化；场景里再随机朝向、大小、色调。"
TAGS = ["plains", "desert", "shore", "canyon"]
VARIANTS = 4


def build(seed, **over):
    return build_tuft(seed, "dry")
