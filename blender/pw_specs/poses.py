"""角色姿势与动作（不依赖 Blender）。

一个「姿势」是一组参数（角度都是弧度；角色正面朝前，左 = 角色自己的左手边）：
  bob         骨盆上下偏移（米，负数 = 下蹲）
  breath      胸口 / 头的额外起伏（米）
  lean        上身前倾（正 = 向前弯腰，负 = 后仰）
  twist       上身绕竖轴扭转（正 = 右肩向前，左肩向后）
  head        [低头(正)/抬头(负), 向左转(正)/向右转(负)]
  arm_l/arm_r [前摆角 swing（0 = 垂下，π/2 = 平举向前，π = 举过头顶）, 肘弯 elbow（0 = 伸直）, 外张 spread（0..1）]
  leg_l/leg_r [大腿前摆 thigh（正 = 向前迈）, 膝弯 knee（0 = 伸直）]
  cape        披风 / 马尾向后飘的程度（0..1）
  weapon      "sheathed"（剑挂在腰上，杖竖着拿）或 "hand"（武器握在右手，沿前臂方向）
  weapon_angle 握在手里的武器相对前臂再往前转的角度
  hand_glow   手上发光的大小（0 = 无，1 = 最大；施法用）

一个「动作」：{"id", "name", "frames": 帧数, "fps", "loop": 是否循环, "keys": [{"t": 0..1, 姿势参数...}, ...]}
关键帧之间按平滑曲线插值；关键帧里没写的参数沿用上一个关键帧（第一个关键帧没写的用 NEUTRAL）。
待机 / 走路 / 跑步是程序化生成的（周期运动），其余内置动作和大模型新写的动作都用关键帧。
"""
import copy
import math
import re

NEUTRAL = {
    "bob": 0.0, "breath": 0.0, "lean": 0.0, "twist": 0.0, "head": [0.0, 0.0],
    "arm_l": [0.04, 0.18, 0.2], "arm_r": [0.04, 0.18, 0.2],
    "leg_l": [0.0, 0.04], "leg_r": [0.0, 0.04],
    "cape": 0.1, "weapon": "sheathed", "weapon_angle": 0.0, "hand_glow": 0.0,
}

# 每个数值参数的合法范围（大模型写的动作会被夹到范围内，避免肢体拧成麻花）
RANGES = {
    "bob": (-0.25, 0.3), "breath": (-0.03, 0.03), "lean": (-0.6, 0.9), "twist": (-0.8, 0.8),
    "head": [(-0.6, 0.6), (-0.9, 0.9)],
    "arm_l": [(-1.2, 3.1), (0.0, 2.4), (0.0, 1.2)], "arm_r": [(-1.2, 3.1), (0.0, 2.4), (0.0, 1.2)],
    "leg_l": [(-1.2, 1.6), (0.0, 2.2)], "leg_r": [(-1.2, 1.6), (0.0, 2.2)],
    "cape": (0.0, 1.0), "weapon_angle": (-1.6, 1.6), "hand_glow": (0.0, 1.0),
}

# 内置动作（关键帧）
ACTIONS = {
    "attack": {
        "id": "attack", "name": "攻击（劈砍）", "frames": 6, "fps": 12, "loop": False,
        "keys": [
            {"t": 0.0, "weapon": "hand", "arm_r": [2.5, 0.4, 0.35], "arm_l": [0.7, 0.9, 0.3], "twist": -0.4, "lean": -0.12,
             "leg_l": [0.35, 0.25], "leg_r": [-0.3, 0.1], "bob": -0.03, "weapon_angle": 0.9, "cape": 0.2},
            {"t": 0.3, "arm_r": [1.3, 0.05, 0.25], "arm_l": [-0.2, 0.4, 0.25], "twist": 0.35, "lean": 0.25,
             "leg_l": [0.45, 0.35], "leg_r": [-0.4, 0.15], "bob": -0.07, "weapon_angle": 0.15, "cape": 0.5},
            {"t": 0.55, "arm_r": [0.35, 0.15, 0.35], "arm_l": [-0.4, 0.3, 0.3], "twist": 0.5, "lean": 0.32, "bob": -0.08,
             "weapon_angle": 0.3, "cape": 0.6},
            {"t": 1.0, "arm_r": [0.5, 0.7, 0.25], "arm_l": [0.2, 0.5, 0.2], "twist": 0.1, "lean": 0.08, "bob": -0.02,
             "leg_l": [0.2, 0.15], "leg_r": [-0.15, 0.08], "weapon_angle": 0.6, "cape": 0.3},
        ],
    },
    "hit": {
        "id": "hit", "name": "受击", "frames": 4, "fps": 10, "loop": False,
        "keys": [
            {"t": 0.0, "lean": -0.35, "head": [-0.3, 0.2], "arm_l": [0.7, 1.1, 0.5], "arm_r": [0.6, 1.2, 0.5], "bob": -0.03,
             "leg_l": [-0.15, 0.2], "leg_r": [0.1, 0.25], "cape": 0.0},
            {"t": 0.35, "lean": -0.25, "head": [-0.2, 0.1], "arm_l": [0.5, 0.9, 0.45], "arm_r": [0.45, 1.0, 0.45], "bob": -0.05},
            {"t": 1.0, "lean": 0.05, "head": [0.05, 0.0], "arm_l": [0.1, 0.3, 0.25], "arm_r": [0.1, 0.3, 0.25], "bob": -0.01,
             "leg_l": [0.0, 0.05], "leg_r": [0.0, 0.05], "cape": 0.1},
        ],
    },
    "cast": {
        "id": "cast", "name": "施法", "frames": 6, "fps": 10, "loop": False,
        "keys": [
            {"t": 0.0, "arm_l": [0.9, 1.4, 0.3], "arm_r": [0.9, 1.4, 0.3], "lean": 0.1, "hand_glow": 0.2, "bob": -0.02,
             "head": [0.15, 0.0]},
            {"t": 0.4, "arm_l": [1.5, 0.3, 0.2], "arm_r": [1.5, 0.3, 0.2], "lean": -0.05, "hand_glow": 0.7, "bob": 0.0,
             "head": [-0.1, 0.0], "cape": 0.3},
            {"t": 0.7, "arm_l": [2.5, 0.15, 0.45], "arm_r": [2.5, 0.15, 0.45], "lean": -0.15, "hand_glow": 1.0, "bob": 0.03,
             "head": [-0.3, 0.0], "cape": 0.6},
            {"t": 1.0, "arm_l": [2.3, 0.3, 0.6], "arm_r": [2.3, 0.3, 0.6], "lean": -0.1, "hand_glow": 0.5, "bob": 0.02,
             "head": [-0.25, 0.0], "cape": 0.4},
        ],
    },
    "wave": {
        "id": "wave", "name": "挥手", "frames": 4, "fps": 6, "loop": True,
        "keys": [
            {"t": 0.0, "arm_l": [2.6, 0.3, 0.55], "head": [-0.05, 0.15], "lean": -0.03},
            {"t": 0.5, "arm_l": [2.6, 0.9, 0.35], "head": [-0.05, 0.15]},
            {"t": 1.0, "arm_l": [2.6, 0.3, 0.55], "head": [-0.05, 0.15]},
        ],
    },
}

PROCEDURAL = {
    "idle": {"id": "idle", "name": "待机", "frames": 4, "fps": 4, "loop": True},
    "walk": {"id": "walk", "name": "走路", "frames": 6, "fps": 10, "loop": True},
    "run": {"id": "run", "name": "跑步", "frames": 6, "fps": 14, "loop": True},
}

DEFAULT_ANIMS = ["idle", "walk", "run", "attack", "hit", "cast", "wave"]
VILLAGER_ANIMS = ["idle", "walk", "wave"]


def _procedural(kind, t):
    p = copy.deepcopy(NEUTRAL)
    if kind == "idle":
        b = 0.006 * math.sin(2 * math.pi * t)
        p["breath"] = b
        p["arm_l"] = [0.04, 0.18 + b * 4, 0.2]
        p["arm_r"] = [0.04, 0.18 + b * 4, 0.2]
        p["cape"] = 0.08 + b * 2
        return p
    phi = 2 * math.pi * t
    run = kind == "run"
    amp = 0.75 if run else 0.42
    p["bob"] = (-0.075 if run else -0.045) * abs(math.sin(phi)) + (0.035 if run else 0.0)
    p["lean"] = 0.22 if run else 0.04
    for key, ph in (("leg_l", phi), ("leg_r", phi + math.pi)):
        p[key] = [amp * math.sin(ph), (0.2 if run else 0.08) + (1.05 if run else 0.55) * max(0.0, math.cos(ph))]
    aa = 0.9 if run else 0.45
    el = 1.3 if run else 0.25
    p["arm_l"] = [-aa * math.sin(phi), el + (0.0 if run else 0.25 * max(0.0, -math.sin(phi))), 0.2]
    p["arm_r"] = [aa * math.sin(phi), el + (0.0 if run else 0.25 * max(0.0, math.sin(phi))), 0.2]
    p["cape"] = (0.55 if run else 0.25) + 0.12 * abs(math.sin(phi))
    return p


def _smooth(x):
    return x * x * (3 - 2 * x)


def _lerp(a, b, t):
    if isinstance(a, list):
        return [_lerp(x, y, t) for x, y in zip(a, b)]
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return a + (b - a) * t
    return a if t < 0.5 else b


def _filled_keys(action):
    """每个关键帧补全成完整姿势（没写的参数沿用上一个关键帧）"""
    keys = sorted(action["keys"], key=lambda k: k.get("t", 0.0))
    out = []
    prev = copy.deepcopy(NEUTRAL)
    for k in keys:
        cur = copy.deepcopy(prev)
        for name, v in k.items():
            if name != "t":
                cur[name] = copy.deepcopy(v)
        cur["t"] = k.get("t", 0.0)
        out.append(cur)
        prev = cur
    return out


def sample(action_id, frame, actions=None):
    """动作的第 frame 帧的姿势"""
    if action_id in PROCEDURAL:
        a = PROCEDURAL[action_id]
        return _procedural(action_id, frame / a["frames"])
    a = (actions or {}).get(action_id) or ACTIONS[action_id]
    n = a["frames"]
    # 循环动作最后一帧不重复第一帧；一次性动作首尾都要（收招姿势）
    t = frame / n if a.get("loop") else (frame / max(1, n - 1))
    keys = _filled_keys(a)
    if t <= keys[0]["t"]:
        return {k: v for k, v in keys[0].items() if k != "t"}
    for i in range(len(keys) - 1):
        k0, k1 = keys[i], keys[i + 1]
        if t <= k1["t"]:
            u = _smooth((t - k0["t"]) / max(1e-6, k1["t"] - k0["t"]))
            return {k: _lerp(k0[k], k1[k], u) for k in NEUTRAL}
    return {k: v for k, v in keys[-1].items() if k != "t"}


def info(action_id, actions=None):
    if action_id in PROCEDURAL:
        return PROCEDURAL[action_id]
    return (actions or {}).get(action_id) or ACTIONS[action_id]


def _clamp(v, rng, default):
    if isinstance(rng, list):
        if not isinstance(v, list) or len(v) != len(rng):
            return copy.deepcopy(default)
        return [_clamp(x, r, d) for x, r, d in zip(v, rng, default)]
    try:
        v = float(v)
    except (TypeError, ValueError):
        return default
    return max(rng[0], min(rng[1], v))


def validate_action(spec):
    """校验大模型写的动作，返回 (动作, 警告列表)"""
    warn = []
    if not isinstance(spec, dict):
        raise ValueError("动作规格必须是 JSON 对象")
    aid = re.sub(r"[^a-z0-9_]+", "_", str(spec.get("id") or "action").lower()).strip("_")[:30] or "action"
    if aid in PROCEDURAL:
        aid += "_custom"
        warn.append("id 和程序化动作重名，改成 %s" % aid)
    out = {"id": aid, "name": str(spec.get("name") or aid)[:20],
           "frames": int(max(2, min(12, int(spec.get("frames", 6) or 6)))),
           "fps": int(max(2, min(24, int(spec.get("fps", 10) or 10)))),
           "loop": bool(spec.get("loop", False)), "keys": [],
           "for": [re.sub(r"[^a-z0-9_]+", "_", str(x).lower()) for x in (spec.get("for") or []) if isinstance(x, str)][:20]}
    keys = spec.get("keys") or []
    if not isinstance(keys, list) or not keys:
        raise ValueError("动作至少要有一个关键帧（keys）")
    for k in keys[:16]:
        if not isinstance(k, dict):
            continue
        nk = {"t": max(0.0, min(1.0, float(k.get("t", 0.0) or 0.0)))}
        for name, v in k.items():
            if name == "t":
                continue
            if name == "weapon":
                nk[name] = "hand" if v == "hand" else "sheathed"
            elif name in RANGES:
                nk[name] = _clamp(v, RANGES[name], NEUTRAL[name])
            else:
                warn.append("未知姿势参数 %s，已忽略" % name)
        out["keys"].append(nk)
    return out, warn
