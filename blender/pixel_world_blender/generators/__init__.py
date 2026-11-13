"""参数化资产生成器。每个生成器：build(seed, **params) -> (MeshBuilder, info)
坐标约定（Blender，Z 向上）：原点在地面中心，正面朝 -Y（导出 glTF 后对应 Godot 的 +Z 正面）。
info：footprint（占地宽、深，米）、height（米）、desc 等，写进 catalog.json。
"""
from . import cottage, handcart, lighthouse, market_stall, oak, pine, signpost, street_lamp, well

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
}
