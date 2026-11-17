"""城墙塔楼：12 边形圆塔（半径 2.6 米、塔身 8 米），斜面勒脚、腰线、箭窗、挑出的檐口，
顶上是红瓦圆锥高尖顶（尖上一面小旗）、平顶垛口或红褐矮圆顶。内侧（+Y，城里）底部有一扇小拱门。
原点在塔中心地面；放在城墙模块的接缝处（模块端点），1.6 米厚的墙端会被塔身盖住。"""
from ..builder import MeshBuilder
from ._medieval import round_tower

NAME = "城墙塔楼"
CATEGORY = "landmarks"
DESC = "Blender 生成的中世纪圆塔：石砌塔身、箭窗、挑出的檐口，红瓦尖顶、平顶垛口或矮圆顶，放在城墙转角和接缝处。"
VARY = "变体 0 米白石 + 红瓦高尖顶、1 米白石平顶垛口、2 灰绿石 + 红褐矮圆顶（雪地城堡）。"
TAGS = ["town", "medieval"]
VARIANTS = 3
R = 2.6
H = 8.0


def build(seed, **over):
    k = seed - 1
    mb = MeshBuilder()
    roof = ["tile_red", "battlement", "dome"][k % 3]
    stone = ["castle_stone", "castle_stone", "stone_greygreen"][k % 3]
    top = round_tower(mb, 0.0, 0.0, R, H + (1.5 if k % 3 == 0 else 0.0), roof=roof, stone=stone)
    d = (R + 0.45) * 2
    return mb, {"footprint": [round(d, 2), round(d, 2)], "height": round(top, 2), "params": {"radius": R, "roof": roof}}
