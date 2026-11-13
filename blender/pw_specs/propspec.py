"""3D 摆件规格（不依赖 Blender）。大模型写 JSON，Blender 按零件拼出模型、贴上像素贴图、导出 glb。

{
  "id": "snowman", "name": "雪人", "category": "props",      # category：trees / plants / rocks / buildings / landmarks / street / props
  "desc": "一句话描述", "vary": "变体之间有什么不同",
  "tags": ["winter", "roadside"],                              # 场景生成器按标签挑选（见 TAGS）
  "plant": false,                                              # true = 植物：放进场景时随机朝向 / 比例 / 色调，叶子随风摆
  "variants": 4,                                               # 导出几个变体（1..6）
  "parts": [ 零件, ... ]
}
坐标：米；原点在地面中心；Z 向上；正面朝 -Y（导出后对应 Godot 的 +Z）。

零件（每个都必须有 "shape" 和 "mat"）：
  {"shape": "box",     "mat": M, "min": [x,y,z], "max": [x,y,z]}
  {"shape": "frustum", "mat": M, "center": [x,y], "z": [z0,z1], "r": [r0,r1], "sides": 3..24, "rot": 弧度}
       竖直的 N 边形棱台；r1 = 0 是锥体；sides 大一点就是圆柱
  {"shape": "tube",    "mat": M, "from": [x,y,z], "to": [x,y,z], "r": [r0,r1], "sides": 3..16}
       任意方向的棱台：树枝、栏杆、斜撑、车轴
  {"shape": "blob",    "mat": M, "center": [x,y,z], "r": 半径, "h": 高度}
       低多边形团块：树冠、雪球、灌木、石头
  {"shape": "gable_roof", "mat": M, "center": [x,y], "size": [宽,深], "z": 屋檐高度, "pitch": 坡度(度), "overhang": 出檐}
       双坡屋顶（屋脊沿 X 方向），两侧山墙用 "gable_mat"（可选，默认 wall_wood）
  {"shape": "repeat",  "count": 2..24, "radius": r, "center": [x,y], "part": 零件}
       把 part 绕中心均匀复制 count 份（part 的坐标以 (radius, 0) 为基准）：柱子一圈、石头一圈、花瓣
数值可以写成 {"rand": [最小, 最大]}，每个变体随机取值；mat 可以写成数组，每个变体随机挑一个。
共享变量：顶层 "vars": {"h": {"rand": [1.4, 1.9]}, "lean": 0.3, "hull": ["wall_teal", "wall_red"]}，
零件里写 "$h"、"$h+0.1"、"$lean*2" 引用数值，"mat": "$hull" 引用随机选中的材质（几个零件同色）
（只支持数字、变量、+ - * / 和括号）。几个零件要对齐（树干接树冠、柱子接屋顶）时一定要用变量，不要各自随机。
"""
import ast
import copy
import operator
import random
import re
import zlib

# 可用的像素材质（和 Blender 端 builder._TEX 一一对应；Godot 端按同名材质响应积雪、潮湿、夜间发光、随风摆动）
MATERIALS = {
    "wall_red": "红色竖木板墙", "wall_ochre": "赭黄色竖木板墙", "wall_teal": "青色竖木板墙", "wall_wood": "原木色竖木板",
    "siding_white": "白色横木板墙", "siding_ochre": "赭黄色横木板墙",
    "roof_grey": "灰色瓦片", "roof_red": "红色瓦片", "stone": "灰色砌石", "brick": "红砖",
    "plaster_white": "白色灰泥", "plaster_red": "红色灰泥",
    "trim": "白色木线条（窗框、封檐、转角）", "trunk": "树皮 / 原木", "door": "木门板",
    "glass": "窗玻璃（夜里发光）", "bulb": "灯泡 / 灯笼玻璃（夜里发光）",
    "pine": "针叶（随风摆）", "pine_skirt": "针叶裙边（随风摆）", "leaf": "阔叶（随风摆）", "leaf_dark": "深色阔叶（随风摆）",
    "palm_leaf": "棕榈叶（随风摆）", "cactus": "仙人掌绿", "hay": "干草", "crate": "木箱板",
    "canvas_red": "红白条纹帆布", "canvas_teal": "青白条纹帆布", "canvas_ochre": "黄白条纹帆布",
    "metal": "铁灰金属", "metal_green": "墨绿铸铁", "water": "水面",
    "snow": "积雪（白）", "sand": "沙子", "rock_red": "红褐岩石", "coal": "黑色煤块 / 纽扣",
    "fruit_red": "红色果子", "fruit_yellow": "黄色果子", "fruit_green": "绿色果子", "cloth_blue": "蓝布",
}
CATEGORIES = ["trees", "plants", "rocks", "buildings", "landmarks", "street", "props"]
# 场景生成器认识的标签
TAGS = {
    "roadside": "小镇路边（路灯带、路口）", "plaza": "小镇广场", "yard": "房前屋后", "camp": "野外营地",
    "winter": "雪原风格", "desert": "沙漠绿洲风格", "island": "海岛风格", "canyon": "峡谷风格",
    "forest": "森林风格", "plains": "平原风格", "town": "小镇风格", "shore": "湖边 / 海边",
}
SHAPES = {"box", "frustum", "tube", "blob", "gable_roof", "repeat"}


def slug(s, default="prop"):
    s = re.sub(r"[^a-z0-9_]+", "_", str(s).lower()).strip("_")
    return s[:40] or default


def _vec(v, n):
    return isinstance(v, list) and len(v) == n and all(_isnum(x) for x in v)


def _isnum(x):
    return (isinstance(x, (int, float)) or (isinstance(x, dict) and "rand" in x and _vec(x["rand"], 2))
            or (isinstance(x, str) and "$" in x))


_OPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul, ast.Div: operator.truediv,
        ast.USub: operator.neg, ast.UAdd: operator.pos}


def eval_expr(text, env):
    """安全地算 "$h+0.1" 这种表达式：只允许数字、变量、四则运算和括号"""
    src = text.replace("$", "")

    def ev(n):
        if isinstance(n, ast.Expression):
            return ev(n.body)
        if isinstance(n, ast.Constant) and isinstance(n.value, (int, float)):
            return float(n.value)
        if isinstance(n, ast.Name):
            if n.id not in env:
                raise ValueError("未定义的变量 $%s" % n.id)
            return float(env[n.id])
        if isinstance(n, ast.BinOp) and type(n.op) in _OPS:
            return _OPS[type(n.op)](ev(n.left), ev(n.right))
        if isinstance(n, ast.UnaryOp) and type(n.op) in _OPS:
            return _OPS[type(n.op)](ev(n.operand))
        raise ValueError("表达式里只能有数字、变量和 + - * /：%s" % text)

    return ev(ast.parse(src, mode="eval"))


def _check_part(p, path, warn, depth=0):
    if not isinstance(p, dict) or p.get("shape") not in SHAPES:
        warn.append("%s：shape 必须是 %s 之一" % (path, "/".join(sorted(SHAPES))))
        return None
    shape = p["shape"]
    if shape == "repeat":
        if depth > 1:
            warn.append("%s：repeat 不能嵌套超过两层" % path)
            return None
        inner = _check_part(p.get("part"), path + ".part", warn, depth + 1)
        if inner is None:
            return None
        q = {"shape": "repeat", "count": int(max(2, min(24, float(_plain(p.get("count", 6)))))),
             "radius": p.get("radius", 1.0), "center": p.get("center", [0, 0]), "part": inner}
        return q
    mats = p.get("mat")
    if isinstance(mats, str) and mats.startswith("$"):
        q = copy.deepcopy(p)  # 材质变量：生成变体时再取值
        return q
    mlist = mats if isinstance(mats, list) else [mats]
    good = [m for m in mlist if m in MATERIALS]
    if not good:
        warn.append("%s：材质 %r 不在材质库里，改成 trunk" % (path, mats))
        good = ["trunk"]
    q = copy.deepcopy(p)
    q["mat"] = good if len(good) > 1 else good[0]
    need = {"box": [("min", 3), ("max", 3)], "frustum": [("center", 2), ("z", 2), ("r", 2)],
            "tube": [("from", 3), ("to", 3), ("r", 2)], "blob": [("center", 3)],
            "gable_roof": [("center", 2), ("size", 2)]}[shape]
    for key, n in need:
        if not _vec(q.get(key), n):
            warn.append("%s：%s 需要 %d 个数" % (path, key, n))
            return None
    return q


def _plain(v):
    return v["rand"][0] if isinstance(v, dict) else v


def validate(spec):
    """校验摆件规格，返回 (规格, 警告)。坏掉的零件丢弃并记警告；一个零件都不剩时抛 ValueError。"""
    if not isinstance(spec, dict):
        raise ValueError("摆件规格必须是 JSON 对象")
    warn = []
    out = {
        "id": slug(spec.get("id") or spec.get("name")),
        "name": str(spec.get("name") or spec.get("id") or "摆件")[:20],
        "category": spec.get("category") if spec.get("category") in CATEGORIES else "props",
        "desc": str(spec.get("desc") or "")[:160],
        "vary": str(spec.get("vary") or "")[:120],
        "tags": [t for t in (spec.get("tags") or []) if t in TAGS][:6],
        "plant": bool(spec.get("plant", False)),
        "variants": int(max(1, min(6, int(spec.get("variants", 4) or 4)))),
        "parts": [],
    }
    for t in spec.get("tags") or []:
        if t not in TAGS:
            warn.append("未知标签 %s，已忽略" % t)
    vars_in = spec.get("vars") or {}
    out["vars"] = {}
    if isinstance(vars_in, dict):
        for k, v in list(vars_in.items())[:20]:
            if re.match(r"^[a-z_][a-z0-9_]*$", str(k)) and (_isnum(v)):
                out["vars"][k] = v
            elif re.match(r"^[a-z_][a-z0-9_]*$", str(k)) and isinstance(v, list) and v and all(m in MATERIALS for m in v):
                out["vars"][k] = v  # 材质候选列表
            else:
                warn.append("变量 %s 的值不是数字或 {rand}，已忽略" % k)
    # 先试算一遍，表达式写错（引用未定义变量）就在这里报出来
    try:
        variant(dict(out, parts=[]), 1)
    except ValueError as e:
        warn.append(str(e))
    for i, p in enumerate((spec.get("parts") or [])[:200]):
        q = _check_part(p, "parts[%d]" % i, warn)
        if q is not None:
            out["parts"].append(q)
    if not out["parts"]:
        raise ValueError("没有可用的零件：" + "；".join(warn[:5]))
    if isinstance(spec.get("source"), dict):
        out["source"] = spec["source"]
    return out, warn


def resolve(value, rnd, env=None):
    """把 {"rand": [a, b]} 换成随机数、"$变量" 换成数值、材质数组换成其中一个（递归）"""
    env = env or {}
    if isinstance(value, dict):
        if "rand" in value and _vec(value["rand"], 2):
            a, b = (resolve(x, rnd, env) for x in value["rand"])
            return rnd.uniform(float(a), float(b))
        return {k: resolve(v, rnd, env) for k, v in value.items()}
    if isinstance(value, str) and value.startswith("$") and isinstance(env.get(value[1:]), str):
        return env[value[1:]]  # 材质变量
    if isinstance(value, str) and "$" in value:
        return eval_expr(value, env)
    if isinstance(value, list):
        if value and all(isinstance(x, str) and "$" not in x for x in value):
            return rnd.choice(value)
        return [resolve(v, rnd, env) for v in value]
    return value


def variant(spec, seed):
    """规格的第 seed 个变体：所有随机值落定"""
    rnd = random.Random(zlib.crc32(("%s:%d" % (spec["id"], seed)).encode("utf-8")))
    env = {}
    for k, v in (spec.get("vars") or {}).items():  # 变量按顺序算，后面的可以引用前面的
        if isinstance(v, list) and v and all(isinstance(x, str) and "$" not in x for x in v):
            env[k] = rnd.choice(v)
        else:
            env[k] = float(resolve(v, rnd, env))
    return resolve(spec["parts"], rnd, env)
