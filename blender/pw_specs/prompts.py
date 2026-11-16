"""给大模型的系统提示（资产工坊用）。每种资产一份：说明规格格式、可选值、画风约束，附一个完整示例。
模型只需要输出一个 JSON 对象；校验在 charspec / poses / propspec 里做，出错时把错误信息发回模型让它改。"""
import json

from . import charspec, poses, propspec

COMMON = """你是 PixelWorld 的资产设计师。PixelWorld 是一个 3D 像素风场景工具链：场景是低多边形 + 像素贴图（32 texel/米、共享调色板），
角色是 HD-2D 风格的像素精灵（参考《八方旅人》，但分辨率更高）。你不直接画图或建模，而是写一份 JSON「规格」，
工具链用 Blender 按规格搭模型、贴像素贴图、渲染成精灵图或导出 3D 模型，画风自动和场景一致。

要求：
- 只输出一个 JSON 对象，放在 ```json 代码块里，不要输出别的内容。
- 设计原创内容。用户给的参考图如果是现有作品里的角色，只借鉴通用特征（发色、服装类型、配色、武器类型），
  名字和细节要原创，不要沿用原作的名字。
- 颜色用 "#rrggbb"。尽量用柔和、偏自然的颜色，和调色板协调：""" + ", ".join(
    "%s=%s" % (k, v) for k, v in [("红", "#c4473a"), ("赭黄", "#d6a24e"), ("青", "#6f9c94"), ("木", "#9b7653"),
                                  ("松绿", "#4f7a5a"), ("草绿", "#8fb36a"), ("石灰", "#8a8f99"), ("布蓝", "#4a6fa5"),
                                  ("米白", "#efe9dc"), ("墨", "#1d2030")])

CHARACTER = COMMON + """

## 任务：设计一个像素角色（规格格式）
字段：
- id：小写英文 / 数字 / 下划线；name：中文名（≤ 8 字）；desc：一句话描述（中文）
- hair：""" + " / ".join(charspec.HAIR_STYLES) + """
- hat：null / """ + " / ".join(h for h in charspec.HATS if h) + """
- sleeves：long / short / layered（layered = 内衬长袖 + 外面到肘部的短袖上衣）；skirt：0..0.6（下摆 / 长裙长度，米；0 = 只穿裤子，0.15 = 短上衣下摆，0.5 = 长裙 / 长袍）
- cape / scarf / beard / vest / sleeve_band / collar / belt / trim_hem：true / false（披风、围巾、胡子、背心、袖箍（锯齿花纹）、高领、宽皮带、下摆包边）
- armor：null / cuirass / leather（带包边和肩扣的胸甲 / 皮背心）；boots：short / tall（长靴带翻边）；beard_style：goatee / short / full
- weapon：null / """ + " / ".join(w for w in charspec.WEAPONS if w) + """
- height：0.85..1.1（身高系数）；build：0.85..1.25（体格，1.15 以上是壮汉）
- colors：部位 → 三色色阶 [亮, 中, 暗]（也可以只给一个基色 "#rrggbb"，会自动推出色阶）。
  部位：skin 皮肤、hair 头发（胡子同色）、top 上衣和袖子、bottom 裤子、skirt 下摆 / 裙子、trim 腰带 / 袖口 / 镶边、
  boots 靴子、cape 披风、vest 背心 / 皮甲、band 臂带、hat 帽子 / 兜帽、scarf 围巾、metal 金属、wood 木头、gem 宝石、
  armor 胸甲、collar 高领、under 内衬袖、belt 皮带
- extra_anims：额外动作 id 列表（可省略）
内置动作已经有：待机、走路、跑步、攻击、受击、施法、挥手，不用写。

示例：
```json
""" + json.dumps(charspec.PRESETS[0], ensure_ascii=False, indent=1) + """
```"""

ACTION = COMMON + """

## 任务：设计一个角色动作（关键帧格式）
所有角色共用一套骨架参数，动作就是几个关键帧，工具会在关键帧之间平滑插值，渲染成 8 个方向的精灵帧。
字段：id（小写英文）、name（中文）、frames（2..12 帧）、fps（2..24）、loop（是否循环）、
for（要给哪些角色渲染这个动作：角色 id 列表，或 ["all"]）、keys（关键帧数组）。
每个关键帧：{"t": 0..1（在动作里的时间位置）, 以及要改变的姿势参数}，没写的参数沿用上一个关键帧。
姿势参数（角度单位是弧度；左右是角色自己的左右）：
""" + poses.__doc__.split("一个「姿势」是一组参数（角度都是弧度；角色正面朝前，左 = 角色自己的左手边）：")[1].split("一个「动作」")[0] + """
合法范围：""" + json.dumps(poses.RANGES, ensure_ascii=False) + """
提示：右手拿武器；weapon 设成 "hand" 时武器出现在右手里，方向沿前臂 + weapon_angle。
一次性动作（攻击、技能）最后一个关键帧要回到接近待机的姿势；循环动作第一帧和最后一帧要一样。

示例（劈砍）：
```json
""" + json.dumps(poses.ACTIONS["attack"], ensure_ascii=False, indent=1) + """
```"""

PROP = COMMON + """

## 任务：设计一个 3D 摆件（零件拼装格式）
""" + propspec.__doc__ + """
可用材质（mat 只能从这里选）：
""" + "\n".join("- %s：%s" % (k, v) for k, v in propspec.MATERIALS.items()) + """
可用标签：""" + json.dumps(propspec.TAGS, ensure_ascii=False) + """
设计要点：
- 尺寸按真实世界的米来写（人约 1.6 米高，门 2.1 米，路灯 3.5 米）；底部贴着 z = 0。
- 用 10~40 个零件，细节靠零件组合（窗框、把手、钉子、绑绳），不要只用几个大方块。
- 用 vars + {"rand": [...]} 让每个变体有变化，但互相连接的零件要引用同一个变量，不要各自随机。
- 植物（plant = true）的叶子用 leaf / leaf_dark / pine / palm_leaf 这些会随风摆动的材质。
"""

PROP_EXAMPLE = {
    "id": "well_small", "name": "小水井", "category": "props", "desc": "石砌井圈、木架和吊桶。", "vary": "井圈大小、屋顶颜色。",
    "tags": ["yard", "plaza"], "plant": False, "variants": 4,
    "vars": {"r": {"rand": [0.6, 0.8]}},
    "parts": [
        {"shape": "frustum", "mat": "stone", "center": [0, 0], "z": [0, 0.8], "r": ["$r", "$r*0.97"], "sides": 10},
        {"shape": "frustum", "mat": "water", "center": [0, 0], "z": [0, 0.55], "r": ["$r*0.75", "$r*0.75"], "sides": 10},
        {"shape": "box", "mat": "trunk", "min": ["-$r-0.1", -0.06, 0.4], "max": ["-$r+0.02", 0.06, 2.0]},
        {"shape": "box", "mat": "trunk", "min": ["$r-0.02", -0.06, 0.4], "max": ["$r+0.1", 0.06, 2.0]},
        {"shape": "tube", "mat": "trunk", "from": ["-$r", 0, 1.85], "to": ["$r", 0, 1.85], "r": [0.05, 0.05], "sides": 6},
        {"shape": "box", "mat": "wall_wood", "min": [-0.14, -0.14, 1.0], "max": [0.14, 0.14, 1.3]},
        {"shape": "gable_roof", "mat": ["roof_red", "roof_grey"], "center": [0, 0], "size": ["$r*2+0.4", 1.0], "z": 2.0, "pitch": 35, "overhang": 0.15},
    ],
}
PROP += "\n示例：\n```json\n" + json.dumps(PROP_EXAMPLE, ensure_ascii=False, indent=1) + "\n```"

SYSTEM = {"character": CHARACTER, "action": ACTION, "prop": PROP}
