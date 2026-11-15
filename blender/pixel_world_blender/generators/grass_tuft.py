"""草丛（普通 + 高草）。变体 0~3 普通草、4~5 高草。"""
from ._grass import build_tuft

NAME = "草丛"
CATEGORY = "plants"
DESC = "Blender 生成的草丛：一丛细长的草叶，根部深绿、尖端浅绿，随风摆动；前 4 个变体是普通草，后 2 个是高草。"
VARY = "草叶数量、高度、倾斜方向随种子变化；场景里再随机朝向、大小、色调。"
TAGS = ["plains", "forest", "town", "yard"]
VARIANTS = 6


def build(seed, **over):
    return build_tuft(seed, "tall" if seed > 4 else "grass")
