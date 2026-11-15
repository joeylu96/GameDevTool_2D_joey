"""开花的草丛：草叶里夹着 2~4 朵小花。"""
from ._grass import build_tuft

NAME = "花草丛"
CATEGORY = "plants"
DESC = "Blender 生成的花草丛：草叶中间夹着两三朵红 / 黄 / 白色小花。"
VARY = "草叶和花的数量、花色、高度随种子变化。"
TAGS = ["plains", "town", "yard"]
VARIANTS = 4


def build(seed, **over):
    return build_tuft(seed, "flower")
