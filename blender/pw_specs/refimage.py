"""原画取色：从参考图里提取主要颜色（k-means），给大模型当参考，或者直接给角色部位上色。
只依赖 numpy（Blender 自带）。图片读取由调用方负责（Blender 里用 bpy.data.images.load）。"""
import numpy as np


def dominant_colors(rgb, k=10, iters=12, seed=0):
    """rgb：N×3 的 0..1 数组。返回 [(hex, 占比)]，按占比从大到小。
    先去掉几乎纯白 / 纯黑的像素（背景、线稿），剩下的做 k-means。"""
    rgb = np.asarray(rgb, dtype=np.float64).reshape(-1, 3)
    lum = rgb @ np.array([0.299, 0.587, 0.114])
    keep = (lum > 0.06) & (lum < 0.96)
    pts = rgb[keep] if keep.sum() > k * 10 else rgb
    rng = np.random.default_rng(seed)
    if len(pts) > 20000:
        pts = pts[rng.choice(len(pts), 20000, replace=False)]
    cent = pts[rng.choice(len(pts), k, replace=False)]
    for _ in range(iters):
        d = ((pts[:, None, :] - cent[None, :, :]) ** 2).sum(axis=2)
        lab = d.argmin(axis=1)
        for i in range(k):
            m = lab == i
            if m.any():
                cent[i] = pts[m].mean(axis=0)
    counts = np.bincount(lab, minlength=k) / len(pts)
    order = np.argsort(-counts)
    out = []
    for i in order:
        if counts[i] < 0.01:
            continue
        c = np.clip(np.rint(cent[i] * 255), 0, 255).astype(int)
        out.append(("#%02x%02x%02x" % tuple(c), round(float(counts[i]), 3)))
    return out
