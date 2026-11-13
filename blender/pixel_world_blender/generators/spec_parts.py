"""按 JSON 规格拼装摆件（资产工坊 / 大模型生成的 3D 资产走这里）。

规格格式见 blender/pw_specs/propspec.py：一组零件（盒子、棱台、管子、团块、双坡屋顶、环形复制），
材质只能从像素贴图库里挑，所以生成出来的东西和手写的生成器画风完全一致（32 texel / 米、共享调色板）。
"""
import math
import sys
from pathlib import Path

from ..builder import MeshBuilder

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))
from pw_specs import propspec  # noqa: E402


def build_from_spec(spec, seed):
    """返回 (MeshBuilder, info)。spec 应已经过 propspec.validate。"""
    mb = MeshBuilder()
    parts = propspec.variant(spec, seed)
    for p in parts:
        _part(mb, p, (0.0, 0.0), 0.0)
    xs, ys, zs = [], [], []
    for v in mb.verts:
        xs.append(v[0])
        ys.append(v[1])
        zs.append(v[2])
    fp = [float(max(0.3, max(xs) - min(xs))), float(max(0.3, max(ys) - min(ys)))] if xs else [1.0, 1.0]
    return mb, {"footprint": fp, "height": float(max(zs)) if zs else 1.0, "plant": spec.get("plant", False)}


def _xf(p, off, ang):
    """零件坐标绕原点转 ang（repeat 用）再平移 off"""
    c, s = math.cos(ang), math.sin(ang)
    x, y = p[0], p[1]
    out = [x * c - y * s + off[0], x * s + y * c + off[1]]
    return out + list(p[2:])


def _part(mb, p, off, ang):
    shape = p["shape"]
    m = p.get("mat", "trunk")
    if shape == "box":
        if abs(ang) < 1e-6:
            a, b = _xf(p["min"], off, 0.0), _xf(p["max"], off, 0.0)
            mb.box(m, tuple(min(a[i], b[i]) for i in range(3)), tuple(max(a[i], b[i]) for i in range(3)))
        else:  # 转过角度的盒子（repeat 里）：8 个角点逐面拼
            mn, mx = p["min"], p["max"]
            x0, x1 = sorted((mn[0], mx[0]))
            y0, y1 = sorted((mn[1], mx[1]))
            z0, z1 = sorted((mn[2], mx[2]))
            q = {k: _xf([x, y], off, ang) for k, (x, y) in
                 {"a": (x0, y0), "b": (x1, y0), "c": (x1, y1), "d": (x0, y1)}.items()}
            lo = {k: (v[0], v[1], z0) for k, v in q.items()}
            hi = {k: (v[0], v[1], z1) for k, v in q.items()}
            ctr = ((q["a"][0] + q["c"][0]) / 2, (q["a"][1] + q["c"][1]) / 2)
            for u, v in (("a", "b"), ("b", "c"), ("c", "d"), ("d", "a")):
                mid = ((q[u][0] + q[v][0]) / 2 - ctr[0], (q[u][1] + q[v][1]) / 2 - ctr[1], 0.0)
                mb.face(m, [lo[u], lo[v], hi[v], hi[u]], mid)
            mb.face(m, [hi["a"], hi["b"], hi["c"], hi["d"]], (0, 0, 1))
    elif shape == "frustum":
        c = _xf(p["center"], off, ang)
        r0, r1 = p["r"]
        z0, z1 = p["z"]
        sides = int(max(3, min(24, p.get("sides", 8))))
        mb.frustum(m, c[0], c[1], z0, z1, max(0.0, r0), max(0.0, r1), sides, p.get("rot", 0.0) + ang,
                   top=r1 > 1e-4, bottom=bool(p.get("bottom", False)))
    elif shape == "tube":
        r0, r1 = p["r"]
        sides = int(max(3, min(16, p.get("sides", 6))))
        mb.tube(m, _xf(p["from"], off, ang), _xf(p["to"], off, ang), max(0.002, r0), max(0.0, r1), sides)
    elif shape == "blob":
        c = _xf(p["center"], off, ang)
        r = float(p.get("r", 0.5))
        mb.blob(m, c[0], c[1], c[2], r, float(p.get("h", r * 1.6)), int(p.get("sides", 8)), p.get("rot", 0.0) + ang)
    elif shape == "gable_roof":
        _gable(mb, p, off, ang)
    elif shape == "repeat":
        n = int(p["count"])
        rad = float(p.get("radius", 1.0))
        ctr = p.get("center", [0.0, 0.0])
        for k in range(n):
            a = 2 * math.pi * k / n
            o = _xf([ctr[0] + math.cos(a) * rad, ctr[1] + math.sin(a) * rad], off, ang)
            # 零件自身以 (radius, 0) 为基准写：先减掉，再转到第 k 个位置
            _part(mb, _shift(p["part"], -rad), o, ang + a)


def _shift(p, dx):
    """把零件沿 X 平移 dx（repeat 里把基准点挪回原点）"""
    q = dict(p)
    for key in ("min", "max", "from", "to"):
        if key in q:
            q[key] = [q[key][0] + dx] + list(q[key][1:])
    for key in ("center",):
        if key in q:
            q[key] = [q[key][0] + dx] + list(q[key][1:])
    return q


def _gable(mb, p, off, ang):
    """双坡屋顶：屋脊沿局部 X；两块斜面 + 下表面 + 两个三角山墙"""
    w, d = p["size"]
    z0 = float(p.get("z", 2.5))
    pitch = math.radians(float(p.get("pitch", 35.0)))
    ov = float(p.get("overhang", 0.2))
    hw, hd = w / 2 + ov, d / 2 + ov
    ridge = z0 + (d / 2) * math.tan(pitch)
    eave = z0 - ov * math.tan(pitch)
    m = p.get("mat", "roof_grey")
    gm = p.get("gable_mat", "wall_wood")
    c = p["center"]

    def P(x, y, z):
        q = _xf([c[0] + x, c[1] + y], off, ang)
        return (q[0], q[1], z)

    for s in (-1, 1):
        a, b = P(-hw, 0, ridge), P(hw, 0, ridge)
        cc, dd = P(hw, s * hd, eave), P(-hw, s * hd, eave)
        nrm = _xf([0.0, s], (0.0, 0.0), ang) + [1.0]
        mb.face(m, [a, b, cc, dd], tuple(nrm))
        mb.face("wall_wood", [(x, y, z - 0.08) for (x, y, z) in (a, b, cc, dd)], (-nrm[0], -nrm[1], -1.0))
    for sx in (-1, 1):
        x = sx * w / 2
        nrm = _xf([sx, 0.0], (0.0, 0.0), ang) + [0.0]
        mb.face(gm, [P(x, -d / 2, z0), P(x, d / 2, z0), P(x, 0, ridge)], tuple(nrm))
