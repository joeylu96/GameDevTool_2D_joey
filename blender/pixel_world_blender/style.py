"""读取共享风格规范 shared/style/style.json（调色板、像素密度）。Godot 端读的是同一份文件，画风因此一致。"""
import json
from pathlib import Path

# 插件放在仓库的 blender/pixel_world_blender/ 下时，风格文件在 ../../shared/style/style.json；
# 也可以用环境变量 PW_STYLE_JSON 指定。
_HERE = Path(__file__).resolve().parent
_DEFAULT = _HERE.parent.parent / "shared" / "style" / "style.json"

_cache = None


def load(path=None):
    global _cache
    if _cache is not None and path is None:
        return _cache
    import os
    p = Path(path or os.environ.get("PW_STYLE_JSON", _DEFAULT))
    data = json.loads(p.read_text(encoding="utf-8"))
    pal = {k: _hex(v) for k, v in data["palette"].items()}
    _cache = {"palette": pal, "texel_density": float(data["texel_density"]), "path": str(p)}
    return _cache


def _hex(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def c(name):
    """调色板颜色（sRGB 0..1 三元组）"""
    return load()["palette"][name]


def mix(a, b, t):
    ca = c(a) if isinstance(a, str) else a
    cb = c(b) if isinstance(b, str) else b
    return tuple(ca[i] + (cb[i] - ca[i]) * t for i in range(3))


def texel_density():
    return load()["texel_density"]
