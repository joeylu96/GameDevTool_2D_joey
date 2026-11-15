"""参数化资产生成器。每个生成器：build(seed, **params) -> (MeshBuilder, info)
坐标约定（Blender，Z 向上）：原点在地面中心，正面朝 -Y（导出 glTF 后对应 Godot 的 +Z 正面）。
info：footprint（占地宽、深，米）、height（米）、desc 等，写进 catalog.json。
"""
from . import cottage, handcart, lighthouse, market_stall, oak, pine, signpost, street_lamp, well
from . import (barrel, bench, birch, bush, crate, fence, fence_post, fish, grass_dry, grass_flower, grass_tuft,
               haystack, poplar, rock, town_house, weed, windmill_blades, windmill_tower)

GENERATORS = {
    "cottage": cottage,
    "pine": pine,
    "well": well,
    "market_stall": market_stall,
    "oak": oak,
    "street_lamp": street_lamp,
    "handcart": handcart,
    "signpost": signpost,
    "lighthouse": lighthouse,
    "birch": birch,
    "poplar": poplar,
    "bush": bush,
    "rock": rock,
    "grass_tuft": grass_tuft,
    "grass_dry": grass_dry,
    "grass_flower": grass_flower,
    "weed": weed,
    "fish": fish,
    "crate": crate,
    "barrel": barrel,
    "haystack": haystack,
    "bench": bench,
    "fence": fence,
    "fence_post": fence_post,
    "windmill_tower": windmill_tower,
    "windmill_blades": windmill_blades,
    "town_house": town_house,
}
