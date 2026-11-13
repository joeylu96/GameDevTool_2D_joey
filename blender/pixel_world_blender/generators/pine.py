"""松树：和 Godot 端同样的结构——八边形层层叠起，每层 = 深色陡裙边 + 浅色缓顶盖，下面露出树干。"""
import math
import random

from ..builder import MeshBuilder

NAME = "松树"
CATEGORY = "trees"
DESC = "Blender 生成的松树：八边形分层树冠，裙边深、顶盖浅，下雪时每层顶盖积白。"
VARY = "层数、底部粗细、收分、坡度、扭转角随种子变化；放进场景时再随机朝向、比例、色调。"


def build(seed, **over):
    r = random.Random(seed)
    mb = MeshBuilder()
    tiers = r.randint(4, 6)
    base_r = r.uniform(1.0, 1.35)
    shrink = r.uniform(0.7, 0.82)
    slope = r.uniform(0.78, 0.95)
    z = base_r * 0.85 + 0.55 + r.uniform(0, 0.3)
    tr = r.uniform(0.13, 0.17)
    mb.frustum("trunk", 0, 0, 0.0, 0.25, tr * 1.5, tr, 8, 0, top=False)
    mb.frustum("trunk", 0, 0, 0.25, z + 1.2, tr, tr * 0.8, 8, 0, top=False)
    twist = r.random() * math.pi
    for i in range(tiers):
        k = i / tiers
        rad = base_r * (1 - k * shrink) * r.uniform(0.94, 1.06)
        rot = twist + math.pi / 8 * (i % 2) + r.uniform(-0.15, 0.15)
        last = i == tiers - 1
        z_hem = z + rad * 0.35
        r_hem = rad * 0.86
        r_top = 0.0 if last else rad * 0.18
        rise = (r_hem - r_top) * (1.05 if last else slope)
        mb.frustum("pine_skirt", 0, 0, z, z_hem, rad, r_hem, 8, rot, top=False, bottom=(i == 0))
        mb.frustum("pine", 0, 0, z_hem, z_hem + rise, r_hem, r_top, 8, rot, top=False)
        z = z_hem + rise * 0.55
    return mb, {"footprint": [base_r * 2, base_r * 2], "height": z + 0.6, "plant": True}
