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
         "gem", "shine", "vest", "band", "glow"]

HAIR_STYLES = ["short", "spiky", "long", "ponytail", "bun", "bald"]
HATS = [None, "wide", "helmet", "hood", "cap"]
WEAPONS = [None, "sword", "greatsword", "spear", "staff", "cane", "bag", "axe"]

BASE_COLORS = {
    "skin": ["#f7d6b8", "#e8b892", "#bf8466"],
    "eye": ["#2b2338", "#2b2338", "#2b2338"],
    "metal": ["#eef2f7", "#aab4c3", "#666c7c"],
    "wood": ["#9b7653", "#7a5a3e", "#5a412e"],
    "boots": ["#7a5a3e", "#5a412e", "#3d2c22"],
    "gem": ["#fff3b8", "#ffd35c", "#e0952e"],
    "shine": ["#ffffff", "#ffffff", "#ffffff"],
    "glow": ["#ffffff", "#fff6c8", "#ffe08a"],
}
# 没指定的部位借用相近部位的颜色
FALLBACK = {"hat": "hair", "scarf": "trim", "cape": "top", "skirt": "top", "vest": "top", "band": "trim"}

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
    dark = colorsys.hls_to_rgb(shift(hh, 0.68, 0.12), ll * 0.62, min(1.0, ss * 1.08 + 0.04))
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
    out["sleeves"] = _pick(spec.get("sleeves"), ["long", "short"], "long")
    if isinstance(spec.get("source"), dict):
        out["source"] = spec["source"]  # 来源记录（原画、生成用的模型），只存档，不参与生成
    out["skirt"] = _num(spec.get("skirt", 0.2), 0.0, 0.6, 0.2)
    out["height"] = _num(spec.get("height", 1.0), 0.85, 1.1, 1.0)
    out["build"] = _num(spec.get("build", 1.0), 0.85, 1.25, 1.0)
    for flag in ("cape", "scarf", "beard", "vest", "sleeve_band"):
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
        "sleeves": rnd.choice(["long", "short"]),
        "cape": False,
        "scarf": rnd.random() < 0.25,
        "beard": (not female) and rnd.random() < 0.3,
        "vest": rnd.random() < 0.3,
        "weapon": rnd.choice([None, None, None, "bag"]),
        "height": rnd.uniform(0.9, 1.04),
        "build": rnd.uniform(0.9, 1.15),
        "colors": {"skin": rnd.choice(SKIN_RAMPS), "hair": rnd.choice(HAIR_RAMPS), "top": top, "bottom": bottom,
                   "skirt": rnd.choice([top, bottom, CLOTH_RAMPS[5]]), "trim": rnd.choice(CLOTH_RAMPS),
                   "vest": rnd.choice(CLOTH_RAMPS), "hat": rnd.choice(CLOTH_RAMPS + HAIR_RAMPS)},
    }
    return validate(spec)[0]
