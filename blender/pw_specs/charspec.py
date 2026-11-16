"""像素角色规格：预设角色、校验补全、随机路人、色阶工具。不依赖 Blender。

一个角色规格（JSON）：
{
  "id": "mercenary",            # 小写字母 / 数字 / 下划线，作为文件夹名
  "name": "佣兵队长",
  "desc": "一句话描述",
  "hair": "short|spiky|long|ponytail|bun|bald",
  "hat": null | "wide" | "helmet" | "hood" | "cap",
  "skirt": 0..0.6,              # 下摆 / 裙子长度（米）；0 = 只有裤子
  "sleeves": "long|short",
  "cape": bool, "scarf": bool, "beard": bool, "vest": bool, "sleeve_band": bool,
  "weapon": null | "sword" | "greatsword" | "spear" | "staff" | "cane" | "bag" | "axe",
  "height": 0.85..1.1,          # 身高系数（1 = 约 1.6 米）
  "build": 0.85..1.25,          # 体格（肩宽、躯干粗细）
  "colors": {部位: [亮, 中, 暗] 或 "#基色"}   # 部位见 PARTS；只给一个基色时自动推出三色色阶
}
"""
import colorsys
import random
import re

PARTS = ["skin", "eye", "hair", "top", "bottom", "skirt", "trim", "boots", "cape", "metal", "wood", "hat", "scarf",
         "gem", "shine", "vest", "band", "glow", "armor", "collar", "under", "belt", "brow", "sclera", "apron"]
ARMORS = [None, "cuirass", "leather"]
BEARDS = ["goatee", "short", "full"]

HAIR_STYLES = ["short", "spiky", "long", "ponytail", "bun", "bald"]
HATS = [None, "wide", "helmet", "hood", "cap", "toque", "feather"]
WEAPONS = [None, "sword", "greatsword", "spear", "staff", "cane", "bag", "axe", "hammer", "pitchfork", "lute", "mug", "book",
           "basket"]

BASE_COLORS = {
    "skin": ["#f7d6b8", "#e8b892", "#bf8466"],
    "eye": ["#2b2338", "#2b2338", "#2b2338"],
    "metal": ["#eef2f7", "#aab4c3", "#666c7c"],
    "wood": ["#9b7653", "#7a5a3e", "#5a412e"],
    "boots": ["#7a5a3e", "#5a412e", "#3d2c22"],
    "gem": ["#fff3b8", "#ffd35c", "#e0952e"],
    "shine": ["#ffffff", "#ffffff", "#ffffff"],
    "glow": ["#ffffff", "#fff6c8", "#ffe08a"],
    "collar": ["#f6f2e8", "#dcd5c6", "#a9a08d"],
    "belt": ["#8a6446", "#654631", "#45301f"],
    "sclera": ["#ffffff", "#efeae0", "#cfc7b8"],
    "apron": ["#f4efe3", "#ddd5c4", "#ada390"],
}
# 没指定的部位借用相近部位的颜色
FALLBACK = {"hat": "hair", "scarf": "trim", "cape": "top", "skirt": "top", "vest": "top", "band": "trim",
            "armor": "vest", "under": "bottom", "brow": "hair"}

SKIN_RAMPS = [
    ["#f7d6b8", "#e8b892", "#bf8466"],
    ["#f0c7a0", "#d9a07e", "#a86e55"],
    ["#d9a47a", "#b97f5a", "#8a5a40"],
    ["#a8735a", "#86563f", "#5e3a2b"],
]

PRESETS = [
    {"id": "swordsman", "name": "旅人剑士", "desc": "背着红披风的年轻剑士，腰间挂一把长剑，短发翘起。",
     "hair": "spiky", "hat": None, "skirt": 0.2, "sleeves": "long", "cape": True, "scarf": False, "weapon": "sword",
     "colors": {"hair": ["#7a5434", "#5a3a24", "#3b2618"], "top": ["#6f92c6", "#4a6fa5", "#34507a"],
                "bottom": ["#6b707c", "#4c505c", "#353845"], "skirt": ["#6f92c6", "#4a6fa5", "#34507a"],
                "trim": ["#c9a36a", "#9b7653", "#6f5842"], "cape": ["#d0564a", "#a3352d", "#6e2424"]}},
    {"id": "merchant", "name": "行商", "desc": "戴宽檐帽的行商，系着白围裙，腰边挎一个货袋。",
     "hair": "short", "hat": "wide", "skirt": 0.32, "sleeves": "long", "cape": False, "scarf": True, "weapon": "bag",
     "colors": {"hair": ["#3d3a40", "#2a282e", "#1c1b20"], "top": ["#e2b25c", "#c48f3c", "#8f6230"],
                "bottom": ["#7a5a3e", "#5a412e", "#3d2c22"], "skirt": ["#f3eee3", "#d9d0bf", "#ada28c"],
                "trim": ["#6f9c94", "#4f7c78", "#3a5c5c"], "hat": ["#9b7653", "#7a5a3e", "#5a412e"],
                "scarf": ["#6f9c94", "#4f7c78", "#3a5c5c"]}},
    {"id": "maiden", "name": "村姑", "desc": "长发的村庄姑娘，青色长裙配白上衣，走路时裙摆轻轻摆动。",
     "hair": "long", "hat": None, "skirt": 0.52, "sleeves": "short", "cape": False, "scarf": False, "weapon": None,
     "colors": {"hair": ["#c2683e", "#9a4a2c", "#6b301f"], "top": ["#f3eee3", "#d9d0bf", "#ada28c"],
                "bottom": ["#4f7c78", "#3a5c5c", "#284041"], "skirt": ["#6f9c94", "#4f7c78", "#3a5c5c"],
                "trim": ["#c4473a", "#a3352d", "#7d2826"]}},
    {"id": "scholar", "name": "学者", "desc": "扎马尾的学者，紫色长袍，手持顶端嵌着宝石的木杖。",
     "hair": "ponytail", "hat": None, "skirt": 0.55, "sleeves": "long", "cape": False, "scarf": False, "weapon": "staff",
     "colors": {"hair": ["#3a3550", "#27233a", "#181626"], "top": ["#9a80b8", "#735a94", "#4f3d6a"],
                "bottom": ["#4f3d6a", "#3a2d50", "#281f38"], "skirt": ["#9a80b8", "#735a94", "#4f3d6a"],
                "trim": ["#e0b84a", "#b9843a", "#8f6230"]}},
    {"id": "guard", "name": "卫兵", "desc": "戴铁盔、穿红色罩袍的镇上卫兵，手持长枪。",
     "hair": "short", "hat": "helmet", "skirt": 0.26, "sleeves": "long", "cape": False, "scarf": False, "weapon": "spear",
     "colors": {"hair": ["#5a412e", "#3d2c22", "#2a1e17"], "top": ["#d0564a", "#a3352d", "#6e2424"],
                "bottom": ["#6b707c", "#4c505c", "#353845"], "skirt": ["#d0564a", "#a3352d", "#6e2424"],
                "trim": ["#e0b84a", "#b9843a", "#8f6230"]}},
    {"id": "elder", "name": "长者", "desc": "白发白须的村中长者，披着棕色长袍，拄一根短拐杖。",
     "hair": "bald", "hat": None, "skirt": 0.55, "sleeves": "long", "cape": False, "scarf": True, "weapon": "cane",
     "beard": True, "height": 0.94,
     "colors": {"hair": ["#f4f7fb", "#d3dae6", "#9fabbf"], "top": ["#a8835e", "#7a5a3e", "#5a412e"],
                "bottom": ["#7a5a3e", "#5a412e", "#3d2c22"], "skirt": ["#a8835e", "#7a5a3e", "#5a412e"],
                "trim": ["#6f9c94", "#4f7c78", "#3a5c5c"], "scarf": ["#c4473a", "#a3352d", "#7d2826"]}},
]

# 2026-11-15 升级：预设角色加上分层服装（腰带、高领、内外两层袖、长靴、胸甲、下摆包边），中世纪小镇里更耐看
_UPGRADE = {
    "swordsman": {"collar": True, "belt": True, "boots": "tall", "trim_hem": True, "build": 1.05},
    "merchant": {"belt": True, "collar": True},
    "maiden": {"collar": True, "belt": True, "sleeves": "layered", "height": 0.95, "build": 0.92, "lashes": True,
               "colors": {"under": ["#f6f2e8", "#dcd5c6", "#a9a08d"]}},
    "scholar": {"belt": True, "trim_hem": True, "collar": True},
    "guard": {"armor": "cuirass", "boots": "tall", "belt": True, "sleeves": "layered", "build": 1.1,
              "colors": {"armor": ["#d5dae2", "#9098a6", "#5b616e"], "under": ["#6b707c", "#4c505c", "#353845"]}},
    "elder": {"belt": True, "trim_hem": True},
}
for _p in PRESETS:
    _u = dict(_UPGRADE.get(_p["id"], {}))
    _p["colors"] = dict(_p["colors"], **_u.pop("colors", {}))
    _p.update(_u)

# 中世纪小镇的 NPC（商人小贩、手艺人、镇民）：只渲染待机 / 走路 / 挥手
NPCS = [
    {"id": "baker", "name": "面包师", "desc": "戴白色高帽、系白围裙的面包师，挎着一篮刚出炉的面包。",
     "hair": "short", "hat": "toque", "apron": True, "sleeves": "layered", "belt": True, "weapon": "basket",
     "colors": {"hair": "#6b4a32", "hat": "#f4f1ea", "top": "#d9b77e", "under": "#efe6d4", "bottom": "#7a6450",
                "skirt": "#d9b77e", "trim": "#a8835e"}},
    {"id": "butcher", "name": "屠夫", "desc": "膀大腰圆的光头屠夫，络腮胡，红上衣外系一条沾了污渍的围裙，手提剁骨刀。",
     "hair": "bald", "beard": True, "beard_style": "full", "brow": "stern", "apron": True, "sleeves": "short",
     "build": 1.22, "boots": "tall", "weapon": "axe", "skirt": 0.12,
     "colors": {"hair": "#5a3a24", "top": "#a33f3a", "apron": "#c9b9a6", "bottom": "#4f4a46", "trim": "#5a412e"}},
    {"id": "fruit_vendor", "lashes": True, "name": "水果小贩", "desc": "包着头巾的水果摊大姐，绿裙子配米色围裙，挎着一篮苹果。",
     "hair": "long", "hat": "hood", "skirt": 0.48, "apron": True, "collar": True, "weapon": "basket", "height": 0.96, "build": 0.95,
     "colors": {"hair": "#7a4a2c", "hat": "#c85a3c", "top": "#e8d7b0", "skirt": "#5f7f4a", "bottom": "#5f7f4a",
                "apron": "#efe4cc", "trim": "#c85a3c"}},
    {"id": "blacksmith", "name": "铁匠", "desc": "胳膊粗壮的铁匠，系着厚皮围裙，络腮胡，手里拎着锻锤。",
     "hair": "short", "beard": True, "beard_style": "full", "brow": "stern", "apron": True, "sleeves": "short",
     "build": 1.25, "boots": "tall", "belt": True, "weapon": "hammer", "skirt": 0.1,
     "colors": {"hair": "#3d2c22", "top": "#7a7f86", "apron": "#6b4c36", "bottom": "#4c505c", "trim": "#3d2c22"}},
    {"id": "innkeeper", "name": "酒馆老板", "desc": "圆滚滚的酒馆老板，山羊胡，背心外系围裙，手里端着一杯麦酒。",
     "hair": "bald", "beard": True, "vest": True, "apron": True, "build": 1.25, "belt": True, "weapon": "mug", "skirt": 0.14,
     "colors": {"hair": "#8a5a34", "top": "#e8dcc8", "vest": "#7a3a2c", "apron": "#ece4d2", "bottom": "#5a4a3c",
                "trim": "#5a412e"}},
    {"id": "friar", "name": "修士", "desc": "穿棕色连帽长袍的修士，腰系麻绳，怀里抱着一本厚书。",
     "hair": "bald", "hat": "hood", "skirt": 0.58, "belt": True, "weapon": "book",
     "colors": {"hair": "#6b4a32", "hat": "#6e5a46", "top": "#6e5a46", "skirt": "#6e5a46", "bottom": "#5a4a3c",
                "belt": "#c9b48a", "trim": "#c9b48a"}},
    {"id": "knight", "name": "骑士", "desc": "戴铁盔、穿钢胸甲的骑士，蓝色罩袍和披风，腰挂长剑。",
     "hair": "short", "hat": "helmet", "armor": "cuirass", "sleeves": "layered", "cape": True, "skirt": 0.22, "boots": "tall",
     "belt": True, "weapon": "sword", "brow": "stern", "build": 1.15, "trim_hem": True,
     "colors": {"hair": "#5a412e", "armor": ["#e3e7ee", "#a0a8b6", "#5e6573"], "under": "#7a808c", "top": "#3f5a8c",
                "cape": "#3f5a8c", "trim": ["#ecd27a", "#c9a03c", "#8a6a28"], "bottom": "#4c505c"}},
    {"id": "farmer", "name": "农夫", "desc": "戴草帽的农夫，短袖衫外套皮背心，扛着一把草叉。",
     "hair": "short", "hat": "wide", "sleeves": "short", "vest": True, "boots": "tall", "beard": True, "beard_style": "short",
     "weapon": "pitchfork", "skirt": 0.0,
     "colors": {"hair": "#8a6440", "hat": ["#f0dc9a", "#d9be7a", "#a88a4a"], "top": "#9aa878", "vest": "#8a6446",
                "bottom": "#7a6450", "trim": "#6a4a30"}},
    {"id": "bard", "name": "吟游诗人", "desc": "帽子上插着羽毛的吟游诗人，紫色短外衣、锯齿花纹袖箍，背着一把鲁特琴。",
     "hair": "ponytail", "hat": "feather", "sleeves": "layered", "sleeve_band": True, "skirt": 0.2, "belt": True,
     "weapon": "lute", "trim_hem": True,
     "colors": {"hair": "#c2683e", "hat": "#7a3a5a", "top": "#8f4fa0", "skirt": "#8f4fa0", "under": "#e8dcc8",
                "band": ["#f3e3b0", "#c9a03c", "#7a3a5a"], "bottom": "#4a5a7a", "trim": "#c9a03c"}},
    {"id": "noble_lady", "lashes": True, "name": "贵族小姐", "desc": "盘发的贵族小姐，紫红色长裙配金色镶边和白色高领。",
     "hair": "bun", "collar": True, "skirt": 0.58, "trim_hem": True, "belt": True, "height": 0.95, "build": 0.9,
     "colors": {"hair": "#e3c070", "top": "#9a4a7a", "skirt": "#7a3a6a", "bottom": "#7a3a6a",
                "trim": ["#ecd27a", "#c9a03c", "#8a6a28"], "belt": ["#ecd27a", "#c9a03c", "#8a6a28"]}},
    {"id": "herbalist", "lashes": True, "name": "草药师", "desc": "披着绿色兜帽的草药师，长裙，挎着装满药草的布袋。",
     "hair": "ponytail", "hat": "hood", "skirt": 0.5, "scarf": True, "weapon": "bag", "height": 0.97,
     "colors": {"hair": "#3d3a40", "hat": "#5f7f4a", "top": "#7a9a5a", "skirt": "#6a5a46", "bottom": "#6a5a46",
                "scarf": "#c9b48a", "trim": "#c9b48a"}},
    {"id": "child", "name": "小孩", "desc": "在广场上跑来跑去的小孩，翘头发，短袖衫。",
     "hair": "spiky", "sleeves": "short", "height": 0.66, "build": 0.9, "skirt": 0.0,
     "colors": {"hair": "#7a5434", "top": "#c9884a", "bottom": "#6a5a46", "trim": "#8a6446"}},
    {"id": "town_crier", "name": "传令官", "desc": "戴红帽、穿红黄罩袍的传令官，手里拿着告示卷轴。",
     "hair": "short", "hat": "cap", "sleeves": "layered", "skirt": 0.26, "belt": True, "weapon": "book", "trim_hem": True,
     "colors": {"hair": "#5a3a24", "hat": "#a3352d", "top": "#e0b84a", "skirt": "#a3352d", "under": "#a3352d",
                "bottom": "#4c505c", "trim": "#e0b84a"}},
    {"id": "cloth_merchant", "lashes": True, "name": "布商", "desc": "盘发的布商大婶，青色上衣、橙黄长裙，围巾，挎着一卷布。",
     "hair": "bun", "scarf": True, "collar": True, "skirt": 0.5, "weapon": "bag", "build": 1.08,
     "colors": {"hair": "#5a412e", "top": "#4f7c78", "skirt": "#c48f3c", "bottom": "#c48f3c", "scarf": "#c4473a",
                "trim": "#c4473a"}},
]

# 随机路人用的布料色阶（取自共享调色板及其相近色）
CLOTH_RAMPS = [
    ["#6f92c6", "#4a6fa5", "#34507a"], ["#d0564a", "#a3352d", "#6e2424"], ["#e2b25c", "#c48f3c", "#8f6230"],
    ["#6f9c94", "#4f7c78", "#3a5c5c"], ["#8fb36a", "#6e9652", "#527a40"], ["#f3eee3", "#d9d0bf", "#ada28c"],
    ["#a8835e", "#7a5a3e", "#5a412e"], ["#9a80b8", "#735a94", "#4f3d6a"], ["#8a8f99", "#6b707c", "#4c505c"],
    ["#e8a0a0", "#c97878", "#9a5656"],
]
HAIR_RAMPS = [
    ["#7a5434", "#5a3a24", "#3b2618"], ["#3d3a40", "#2a282e", "#1c1b20"], ["#c2683e", "#9a4a2c", "#6b301f"],
    ["#e3c070", "#c49a48", "#8f6a30"], ["#f4f7fb", "#d3dae6", "#9fabbf"], ["#5a412e", "#3d2c22", "#2a1e17"],
]

_HEX = re.compile(r"^#?[0-9a-fA-F]{6}$")


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def rgb_to_hex(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(v * 255)))) for v in c)


def ramp_from_base(base):
    """一个基色 → [亮, 中, 暗] 三色色阶。像素画的「色相偏移」做法：亮部往暖（黄）偏、提亮降饱和一点；
    暗部往冷（蓝紫）偏、压暗加饱和。比单纯加减亮度更有层次。"""
    r, g, b = hex_to_rgb(base)
    hh, ll, ss = colorsys.rgb_to_hls(r, g, b)

    def shift(h, toward, amt):
        d = ((toward - h + 0.5) % 1.0) - 0.5
        return (h + d * amt) % 1.0

    light = colorsys.hls_to_rgb(shift(hh, 0.14, 0.12), min(0.95, ll + (1 - ll) * 0.28), ss * 0.92)
    # 暗部：压暗、往冷偏一点，饱和度不加（浅色衣服加了饱和度的暗部会像一块块橙色污渍）
    dark = colorsys.hls_to_rgb(shift(hh, 0.68, 0.1), ll * (0.74 if ll > 0.6 else 0.66), ss * 0.9)
    return [rgb_to_hex(light), rgb_to_hex((r, g, b)), rgb_to_hex(dark)]


def _num(v, lo, hi, default):
    try:
        v = float(v)
    except (TypeError, ValueError):
        return default
    return max(lo, min(hi, v))


def _pick(v, options, default):
    return v if v in options else default


def slug(s, default="char"):
    s = re.sub(r"[^a-z0-9_]+", "_", str(s).lower()).strip("_")
    return s[:40] or default


def validate(spec):
    """校验并补全一个角色规格，返回 (规格, 警告列表)。不合法的值改成默认值并记一条警告，不会抛异常。"""
    warn = []
    if not isinstance(spec, dict):
        raise ValueError("角色规格必须是 JSON 对象")
    out = {}
    out["id"] = slug(spec.get("id") or spec.get("name") or "char")
    out["name"] = str(spec.get("name") or out["id"])[:20]
    out["desc"] = str(spec.get("desc") or "")[:120]
    for key, opts, dflt in (("hair", HAIR_STYLES, "short"), ("hat", HATS, None), ("weapon", WEAPONS, None)):
        v = spec.get(key, dflt)
        if v in ("", "none", "None"):
            v = None
        if v not in opts:
            warn.append("%s=%r 不支持，改成 %r" % (key, v, dflt))
            v = dflt
        out[key] = v
    out["sleeves"] = _pick(spec.get("sleeves"), ["long", "short", "layered"], "long")
    out["armor"] = _pick(spec.get("armor"), ARMORS, None)
    out["boots"] = _pick(spec.get("boots"), ["short", "tall"], "short")
    out["beard_style"] = _pick(spec.get("beard_style"), BEARDS, "goatee")
    out["brow"] = _pick(spec.get("brow"), ["soft", "stern"], "soft")
    if isinstance(spec.get("source"), dict):
        out["source"] = spec["source"]  # 来源记录（原画、生成用的模型），只存档，不参与生成
    out["skirt"] = _num(spec.get("skirt", 0.2), 0.0, 0.6, 0.2)
    out["height"] = _num(spec.get("height", 1.0), 0.6, 1.1, 1.0)  # 0.6~0.75 是小孩
    out["build"] = _num(spec.get("build", 1.0), 0.85, 1.25, 1.0)
    for flag in ("cape", "scarf", "beard", "vest", "sleeve_band", "collar", "belt", "trim_hem", "apron", "lashes"):
        out[flag] = bool(spec.get(flag, False))
    extra = spec.get("extra_anims") or []
    out["extra_anims"] = [slug(x, "") for x in extra if isinstance(x, str) and slug(x, "")][:8] if isinstance(extra, list) else []
    cols = {}
    src = spec.get("colors") or {}
    if not isinstance(src, dict):
        warn.append("colors 不是对象，已忽略")
        src = {}
    for part, v in src.items():
        if part not in PARTS:
            warn.append("未知部位 %s，已忽略" % part)
            continue
        if isinstance(v, str) and _HEX.match(v):
            cols[part] = ramp_from_base("#" + v.lstrip("#"))
        elif isinstance(v, list) and len(v) == 3 and all(isinstance(c, str) and _HEX.match(c) for c in v):
            cols[part] = ["#" + c.lstrip("#").lower() for c in v]
        else:
            warn.append("部位 %s 的颜色格式不对（要 \"#rrggbb\" 或三个色值的数组）" % part)
    for need, dflt in (("hair", HAIR_RAMPS[0]), ("top", CLOTH_RAMPS[0]), ("bottom", CLOTH_RAMPS[8]), ("trim", CLOTH_RAMPS[6])):
        if need not in cols:
            cols[need] = dflt
    out["colors"] = cols
    return out, warn


def ramps(spec):
    """部位 → 三色色阶（全部部位都有）"""
    r = {}
    cols = spec.get("colors", {})
    for key in PARTS:
        c = cols.get(key) or BASE_COLORS.get(key)
        if c is None:
            c = cols.get(FALLBACK.get(key, "top")) or cols.get("top")
        r[key] = c
    return r


def random_villager(seed):
    """随机路人：发型、帽子、衣服长短、配饰和颜色随种子组合，每个都不一样，但都在调色板范围内。"""
    rnd = random.Random(seed)
    female = rnd.random() < 0.5
    hair = rnd.choice(["long", "ponytail", "bun", "short"] if female else ["short", "spiky", "short", "bald"])
    top = rnd.choice(CLOTH_RAMPS)
    bottom = rnd.choice([c for c in CLOTH_RAMPS if c != top])
    skirt = rnd.uniform(0.4, 0.55) if female and rnd.random() < 0.7 else rnd.uniform(0.0, 0.25)
    spec = {
        "id": "villager_%d" % seed,
        "name": "路人 %d" % seed,
        "desc": "随机组合的小镇路人（种子 %d）。" % seed,
        "hair": hair,
        "hat": rnd.choice([None, None, None, "cap", "wide", "hood"]),
        "skirt": skirt,
        "sleeves": rnd.choice(["long", "short", "layered"]),
        "cape": False,
        "scarf": rnd.random() < 0.25,
        "beard": (not female) and rnd.random() < 0.3,
        "vest": rnd.random() < 0.3,
        "weapon": rnd.choice([None, None, None, "bag"]),
        "belt": rnd.random() < 0.6,
        "collar": rnd.random() < 0.3,
        "trim_hem": rnd.random() < 0.3,
        "boots": "tall" if rnd.random() < 0.3 else "short",
        "brow": "soft" if female or rnd.random() < 0.5 else "stern",
        "lashes": female,
        "height": rnd.uniform(0.9, 1.04),
        "build": rnd.uniform(0.9, 1.15),
        "colors": {"skin": rnd.choice(SKIN_RAMPS), "hair": rnd.choice(HAIR_RAMPS), "top": top, "bottom": bottom,
                   "skirt": rnd.choice([top, bottom, CLOTH_RAMPS[5]]), "trim": rnd.choice(CLOTH_RAMPS),
                   "vest": rnd.choice(CLOTH_RAMPS), "hat": rnd.choice(CLOTH_RAMPS + HAIR_RAMPS),
                   "under": rnd.choice([CLOTH_RAMPS[5], CLOTH_RAMPS[8], CLOTH_RAMPS[6]])},
    }
    return validate(spec)[0]
