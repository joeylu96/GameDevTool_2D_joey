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

# 前 26 个是几何部位（渲染时每个部位一种 ID 色，最多 26 种）；后面几个只用来取色（五官是在像素层画的）
PARTS = ["skin", "hair", "top", "bottom", "skirt", "trim", "boots", "cape", "metal", "wood", "hat", "scarf",
         "gem", "vest", "band", "glow", "armor", "collar", "under", "belt", "apron", "fur", "guard", "strap", "panel",
         "eye", "shine", "brow", "sclera"]
ARMORS = [None, "cuirass", "leather"]
BEARDS = ["goatee", "short", "full"]

HAIR_STYLES = ["short", "spiky", "long", "ponytail", "bun", "bald"]
HATS = [None, "wide", "helmet", "hood", "cap", "toque", "feather", "fur"]
WEAPONS = [None, "sword", "greatsword", "spear", "staff", "cane", "bag", "axe", "hammer", "pitchfork", "lute", "mug", "book",
           "basket", "rifle"]

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
    "fur": ["#d6cab8", "#a39582", "#6e6152"],
    "guard": ["#57493e", "#3a302a", "#221c19"],
}
# 没指定的部位借用相近部位的颜色
FALLBACK = {"hat": "hair", "scarf": "trim", "cape": "top", "skirt": "top", "vest": "top", "band": "trim",
            "armor": "vest", "under": "bottom", "brow": "hair", "strap": "belt", "panel": "trim"}

SKIN_RAMPS = [
    ["#f7d6b8", "#e8b892", "#bf8466"],
    ["#f0c7a0", "#d9a07e", "#a86e55"],
    ["#d9a47a", "#b97f5a", "#8a5a40"],
    ["#a8735a", "#86563f", "#5e3a2b"],
]

# 2026-11-17：之前的人物全部去掉（用户不喜欢）。现在的角色都按 res/ 里的参考图重画：写实 7.5 头身，
# 每个角色带 style（属于哪个场景风格）。前两个是照着参考图做的：中世纪战士（res/中世纪人物.jpg）、猎人（res/8090中国乡村猎人.jpg）
PRESETS = [
    {"id": "warrior", "name": "佣兵战士", "style": "medieval",
     "desc": "金色短发、留着山羊胡的中年佣兵：白色高领内衫外罩黑色肌肉胸甲（金边、肩扣），棕色短袖的袖口是红色锯齿纹，灰色长内衬袖，"
             "米色开衩长下摆垂到小腿，灰裤、带护膝的棕色长靴，腰挂长剑。",
     "hair": "spiky", "beard": True, "beard_style": "goatee", "brow": "stern", "collar": True, "armor": "cuirass",
     "sleeves": "layered", "sleeve_band": True, "belt": True, "boots": "tall", "knee_guards": True,
     "skirt": 0.5, "skirt_split": True, "skirt_cloth": True, "weapon": "sword", "height": 1.0, "build": 1.14,
     "extra_anims": ["shoulder_rest"],
     "colors": {"hair": ["#f0d98a", "#d2b45c", "#9a7c3a"], "skin": ["#f3cba8", "#dba585", "#a8715a"],
                "eye": ["#9ab0cc", "#6f89ad", "#4a607f"],
                "armor": ["#4a4b52", "#2a2a30", "#151518"], "trim": ["#e6c66a", "#b8943e", "#7a5e26"],
                "top": ["#b98a62", "#94694a", "#6b4a35"], "band": ["#d8553f", "#8c2f2a", "#5c1f1f"],
                "under": ["#9a979b", "#757277", "#535156"], "skirt": ["#ecdcae", "#d4c08a", "#a8935f"],
                "panel": ["#d9bf8a", "#bfa06a", "#8f744a"], "bottom": ["#8c8a8e", "#68666b", "#48474b"],
                "boots": ["#7d5a45", "#5c4032", "#3b2920"], "guard": ["#4f463f", "#352e29", "#201b18"],
                "belt": ["#4a3d36", "#322924", "#1f1916"], "collar": ["#f6f3ea", "#dcd6c8", "#aaa392"]}},
    {"id": "hunter", "name": "猎人", "style": "cn_village",
     "desc": "戴毛皮帽的年轻猎人：灰色棉袄，毛领、毛袖口，皮背带和皮挎包，深蓝棉裤，膝上裹着毛皮护膝，黑色系带靴，背着猎枪。",
     "hair": "short", "hat": "fur", "brow": "soft", "sleeves": "long", "fur_collar": True, "fur_trim": True, "straps": True,
     "satchel": True, "belt": True, "knee_fur": True, "boots": "short", "skirt": 0.2, "trim_hem": True, "weapon": "rifle",
     "height": 0.98, "build": 1.08,
     "colors": {"hair": ["#3a3432", "#262221", "#161413"], "skin": ["#f0c8a4", "#d9a584", "#a8735c"],
                "eye": ["#4a3a32", "#33261f", "#1f1612"],
                "top": ["#a9a8a6", "#868583", "#5f5e5d"], "skirt": ["#a9a8a6", "#868583", "#5f5e5d"],
                "trim": ["#d6cab8", "#a39582", "#6e6152"], "fur": ["#d9cdb9", "#a69783", "#6f6253"],
                "bottom": ["#3f5a6e", "#2c4254", "#1c2c3a"], "boots": ["#3a3a3e", "#26262a", "#151518"],
                "belt": ["#9a6a48", "#734c33", "#4c3222"], "strap": ["#9a6a48", "#734c33", "#4c3222"]}},
]
# 各风格的镇民 / 村民（只渲染待机、走路、挥手），和上面两个参考角色同一套写实比例和画法
_SKIN = ["#f0c8a4", "#d9a584", "#a8735c"]
NPCS = [
    # ---- 中世纪海边小镇
    {"id": "med_guard", "name": "城防卫兵", "style": "medieval", "desc": "戴铁盔、穿钢胸甲和红色罩袍的城防卫兵，手持长枪。",
     "hair": "short", "hat": "helmet", "armor": "cuirass", "sleeves": "layered", "belt": True, "boots": "tall", "knee_guards": True,
     "skirt": 0.3, "skirt_cloth": True, "trim_hem": True, "weapon": "spear", "brow": "stern", "build": 1.1,
     "colors": {"hair": "#5a412e", "armor": ["#dfe3ea", "#9aa2b0", "#5c6370"], "under": "#7a808c", "top": "#b23a32",
                "skirt": "#b23a32", "trim": ["#ecd27a", "#c9a03c", "#8a6a28"], "bottom": "#55585f"}},
    {"id": "med_merchant", "name": "港口商人", "style": "medieval", "desc": "戴宽檐帽的港口商人，赭黄长外衣、宽皮带，挎着货袋。",
     "hair": "short", "hat": "wide", "beard": True, "beard_style": "short", "sleeves": "long", "belt": True, "collar": True,
     "skirt": 0.42, "trim_hem": True, "weapon": "bag", "build": 1.08,
     "colors": {"hair": "#4a3426", "hat": "#7a5a3e", "top": "#c8923e", "skirt": "#c8923e", "trim": "#7a3a2c", "bottom": "#5a4a3c"}},
    {"id": "med_townswoman", "name": "镇上妇人", "style": "medieval", "lashes": True,
     "desc": "盘发的镇上妇人，白衬衣、红色长裙配米色围裙，挎着一篮面包。",
     "hair": "bun", "sleeves": "layered", "collar": True, "skirt": 0.72, "apron": True, "weapon": "basket",
     "height": 0.93, "build": 0.9,
     "colors": {"hair": "#8a4a2c", "top": "#b8443a", "under": "#f1ebdd", "skirt": "#b8443a", "bottom": "#b8443a",
                "apron": "#efe6d0", "trim": "#7a2a26"}},
    {"id": "med_friar", "name": "修士", "style": "medieval", "desc": "穿棕色连帽长袍的修士，腰系麻绳，抱着一本厚书。",
     "hair": "bald", "hat": "hood", "skirt": 0.78, "belt": True, "weapon": "book",
     "colors": {"hair": "#6b4a32", "hat": "#6e5a46", "top": "#6e5a46", "skirt": "#6e5a46", "bottom": "#5a4a3c",
                "belt": "#c9b48a"}},
    {"id": "med_sailor", "name": "水手", "style": "medieval", "desc": "码头上的水手：条纹头巾、卷起袖子的白衫、蓝色马甲和宽腿裤。",
     "hair": "short", "hat": "cap", "sleeves": "short", "vest": True, "belt": True, "skirt": 0.0, "beard": True,
     "beard_style": "short", "build": 1.1,
     "colors": {"hair": "#3d2c22", "hat": "#b23a32", "top": "#f1ebdd", "vest": "#3f5a8c", "bottom": "#7a6a55", "trim": "#5a412e"}},
    {"id": "med_noblewoman", "name": "贵族小姐", "style": "medieval", "lashes": True, "desc": "金发的贵族小姐，蓝色长裙配金色镶边和白色高领。",
     "hair": "long", "collar": True, "skirt": 0.78, "trim_hem": True, "belt": True, "height": 0.94, "build": 0.88,
     "colors": {"hair": ["#f0d98a", "#d2b45c", "#9a7c3a"], "top": "#3f6a9c", "skirt": "#34588a", "bottom": "#34588a",
                "trim": ["#ecd27a", "#c9a03c", "#8a6a28"], "belt": ["#ecd27a", "#c9a03c", "#8a6a28"]}},
    # ---- 八九十年代中国乡村
    {"id": "cn_farmer", "name": "庄稼汉", "style": "cn_village", "desc": "戴草帽的庄稼汉：挽着袖子的白汗衫、深蓝长裤、黑布鞋，扛着草叉。",
     "hair": "short", "hat": "wide", "sleeves": "short", "skirt": 0.0, "weapon": "pitchfork", "build": 1.02,
     "colors": {"skin": _SKIN, "hair": "#262221", "hat": ["#f0dc9a", "#d9be7a", "#a88a4a"], "top": "#eeeae0",
                "bottom": "#34455e", "boots": "#2a2a2e", "trim": "#34455e"}},
    {"id": "cn_uncle", "name": "蓝褂大叔", "style": "cn_village", "desc": "穿蓝色中山装式外套的大叔，戴解放帽，背着手在村里转。",
     "hair": "short", "hat": "cap", "sleeves": "long", "collar": True, "skirt": 0.16, "build": 1.05,
     "colors": {"skin": _SKIN, "hair": "#3a3432", "hat": "#4a6a5a", "top": "#3f5f8a", "skirt": "#3f5f8a", "collar": "#34507a",
                "bottom": "#3a4658", "boots": "#2a2a2e", "trim": "#34507a"}},
    {"id": "cn_auntie", "name": "碎花大婶", "style": "cn_village", "lashes": True, "desc": "扎着发髻的大婶，红底碎花衬衫、深色长裤，挎着菜篮子。",
     "hair": "bun", "sleeves": "long", "skirt": 0.14, "weapon": "basket", "height": 0.9, "build": 1.0,
     "colors": {"skin": _SKIN, "hair": "#262221", "top": "#c4504a", "skirt": "#c4504a", "bottom": "#3a3f4c",
                "boots": "#2a2a2e", "trim": "#f0d8c8"}},
    {"id": "cn_granny", "name": "老奶奶", "style": "cn_village", "desc": "花白头发盘在脑后的老奶奶，藏青色斜襟褂子、黑裤布鞋，系着围裙。",
     "hair": "bun", "sleeves": "long", "skirt": 0.2, "apron": True, "height": 0.84, "build": 0.95,
     "colors": {"skin": ["#e8c0a0", "#cf9c80", "#9c6c58"], "hair": ["#d8d8dc", "#a8a8b0", "#74747c"], "top": "#34405a",
                "skirt": "#34405a", "apron": "#4a556e", "bottom": "#2c2c32", "boots": "#232327", "trim": "#2a3348"}},
    {"id": "cn_girl", "name": "村里姑娘", "style": "cn_village", "lashes": True, "desc": "扎马尾的姑娘，白底蓝格衬衫、蓝长裤。",
     "hair": "ponytail", "sleeves": "short", "skirt": 0.1, "height": 0.9, "build": 0.86,
     "colors": {"skin": _SKIN, "hair": "#262221", "top": "#e6eef6", "skirt": "#e6eef6", "bottom": "#3f5f8a",
                "boots": "#2a2a2e", "trim": "#c4504a"}},
    {"id": "cn_kid", "name": "小孩", "style": "cn_village", "desc": "穿背心短裤、在村里疯跑的小孩。",
     "hair": "short", "sleeves": "short", "skirt": 0.0, "height": 0.62, "build": 0.9,
     "colors": {"skin": _SKIN, "hair": "#262221", "top": "#d8483a", "bottom": "#3f5f8a", "boots": "#2a2a2e", "trim": "#f0f0f0"}},
    # ---- 现代小镇
    {"id": "mod_man", "name": "小镇青年", "style": "modern", "desc": "穿连帽外套和牛仔裤的小镇青年。",
     "hair": "short", "sleeves": "long", "skirt": 0.1, "skirt_cloth": True,
     "colors": {"skin": _SKIN, "hair": "#3a2c24", "top": "#5f7f6a", "skirt": "#5f7f6a", "bottom": "#3f5878",
                "boots": "#e8e6e0", "trim": "#4a6a56"}},
    {"id": "mod_woman", "name": "上班族", "style": "modern", "lashes": True, "desc": "长发的上班族，米色风衣、深色长裤，挎着包。",
     "hair": "long", "sleeves": "long", "belt": True, "skirt": 0.5, "weapon": "bag", "height": 0.93, "build": 0.88,
     "colors": {"skin": _SKIN, "hair": "#5a3a28", "top": "#d8c4a0", "skirt": "#d8c4a0", "bottom": "#3a3f4c",
                "boots": "#3a2c24", "belt": "#8a6a4a", "trim": "#8a6a4a"}},
    {"id": "mod_shopkeeper", "name": "咖啡店主", "style": "modern", "desc": "系着深色围裙的咖啡店主，白衬衫，袖子挽到手肘，端着一杯咖啡。",
     "hair": "short", "beard": True, "beard_style": "short", "sleeves": "short", "apron": True, "skirt": 0.0, "weapon": "mug",
     "colors": {"skin": _SKIN, "hair": "#2a2422", "top": "#f1f1ee", "apron": "#3a4048", "bottom": "#2f3138",
                "boots": "#2a2a2e", "trim": "#3a4048"}},
    {"id": "mod_jogger", "name": "晨跑的人", "style": "modern", "lashes": True, "desc": "扎马尾、穿运动服晨跑的人。",
     "hair": "ponytail", "sleeves": "short", "skirt": 0.0, "height": 0.92, "build": 0.88,
     "colors": {"skin": _SKIN, "hair": "#262221", "top": "#e0584a", "bottom": "#2f3138", "boots": "#f0f0f0", "trim": "#f0f0f0"}},
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
    out["skirt"] = _num(spec.get("skirt", 0.2), 0.0, 0.8, 0.2)
    out["style"] = slug(spec.get("style") or "", "")  # 属于哪个场景风格（medieval / cn_village / modern），场景里只出现对应风格的人
    out["height"] = _num(spec.get("height", 1.0), 0.6, 1.1, 1.0)  # 0.6~0.75 是小孩
    out["build"] = _num(spec.get("build", 1.0), 0.85, 1.25, 1.0)
    for flag in ("cape", "scarf", "beard", "vest", "sleeve_band", "collar", "belt", "trim_hem", "apron", "lashes", "skirt_split", "skirt_cloth",
                 "knee_guards", "knee_fur", "fur_trim", "fur_collar", "straps", "satchel"):
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


def random_villager(seed):  # 旧的随机路人（已停用：tools/blender_build_sprites.py --villagers 默认 0）
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
