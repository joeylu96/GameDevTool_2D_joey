"""生成器共用的部件（对照 Godot 端 pw_tree_builder._blob、pw_parts.window / door）。
坐标：Blender Z 向上，正面朝 -Y（Godot 的 (x, y, z) 对应这里的 (x, -z, y)）。"""
import numpy as np


def leaf_blob(mb, x, y, cz, r, h, rot, light="leaf", dark="leaf_dark", sides=8):
    """树冠团块：下收口（暗）+ 腰（暗）+ 上收口（亮，能积雪）。cz 为团块中心高度，h 为总高"""
    z0, z1, z2, z3 = cz - h * 0.5, cz - h * 0.12, cz + h * 0.15, cz + h * 0.5
    mb.frustum(dark, x, y, z0, z1, r * 0.6, r, sides, rot, top=False, bottom=True)
    mb.frustum(dark, x, y, z1, z2, r, r, sides, rot, top=False)
    mb.frustum(light, x, y, z2, z3, r, r * 0.5, sides, rot, top=True)


def _v(p):
    return np.asarray(p, dtype=float)


def lbox(mb, mat, c, left, n, x0, x1, y0, y1, d0, d1):
    """部件局部坐标下的方盒：lx 沿 left，ly 向上（Z），ld 沿外法线 n"""
    c, left, n = _v(c), _v(left), _v(n)
    up = np.array([0.0, 0.0, 1.0])
    a = c + left * x0 + n * d0 + up * y0
    b = c + left * x1 + n * d1 + up * y1
    mb.box(mat, tuple(np.minimum(a, b)), tuple(np.maximum(a, b)))


def window(mb, c, n, hw, h, panes_x=2, panes_y=2, shutters="", flowers=False):
    """窗户：玻璃 + 窗框 + 窗棂 + 窗台 / 窗楣 + 可选百叶窗、花箱。c = 底边中点（墙面上），n = 墙面外法线"""
    c, n = _v(c), _v(n)
    up = np.array([0.0, 0.0, 1.0])
    left = np.cross(n, up)
    ft = 0.07
    g = c + n * 0.012
    mb.face("glass", [g + left * hw + up * h, g - left * hw + up * h, g - left * hw, g + left * hw], tuple(n))
    lbox(mb, "trim", c, left, n, -hw - ft * 0.5, hw + ft * 0.5, h - ft * 0.5, h + ft * 0.5, 0.0, 0.06)
    lbox(mb, "trim", c, left, n, -hw - ft * 0.5, hw + ft * 0.5, -ft * 0.5, ft * 0.5, 0.0, 0.06)
    lbox(mb, "trim", c, left, n, hw - ft * 0.5, hw + ft * 0.5, ft * 0.5, h - ft * 0.5, 0.0, 0.06)
    lbox(mb, "trim", c, left, n, -hw - ft * 0.5, -hw + ft * 0.5, ft * 0.5, h - ft * 0.5, 0.0, 0.06)
    for i in range(1, panes_x):
        x = -hw + 2.0 * hw * i / panes_x
        lbox(mb, "trim", c, left, n, x - 0.022, x + 0.022, ft * 0.5, h - ft * 0.5, 0.0, 0.035)
    for j in range(1, panes_y):
        y = h * j / panes_y
        lbox(mb, "trim", c, left, n, -hw + ft * 0.5, hw - ft * 0.5, y - 0.022, y + 0.022, 0.0, 0.035)
    lbox(mb, "trim", c, left, n, -hw - 0.11, hw + 0.11, -0.13, -ft * 0.5, 0.0, 0.16)
    lbox(mb, "trim", c, left, n, -hw - 0.1, hw + 0.1, h + ft * 0.5, h + ft * 0.5 + 0.1, 0.0, 0.07)
    lbox(mb, "trim", c, left, n, -hw - 0.14, hw + 0.14, h + ft * 0.5 + 0.1, h + ft * 0.5 + 0.14, 0.0, 0.12)
    if shutters:
        sw = hw * 0.9
        for side in (-1.0, 1.0):
            a = hw + ft * 0.5 + 0.03
            x0, x1 = side * a, side * (a + sw)
            lbox(mb, shutters, c, left, n, min(x0, x1), max(x0, x1), 0.0, h, 0.0, 0.04)
            for yy in (h * 0.22, h * 0.78):
                lbox(mb, shutters, c, left, n, min(x0, x1) + 0.03, max(x0, x1) - 0.03, yy - 0.03, yy + 0.03, 0.04, 0.06)
    if flowers:
        lbox(mb, "wall_wood", c, left, n, -hw - 0.05, hw + 0.05, -0.46, -0.13, 0.16, 0.42)
        lbox(mb, "flowers", c, left, n, -hw, hw, -0.13, 0.04, 0.18, 0.4)


def door(mb, c, n, w=1.05, h=2.05, mat="door_wood", glass_top=True):
    """门：门框 + 门楣檐口 + 门板 + 下半两块嵌板 + 上半玻璃（或嵌板）+ 黄铜把手"""
    c, n = _v(c), _v(n)
    up = np.array([0.0, 0.0, 1.0])
    left = np.cross(n, up)
    hw, ft = w * 0.5, 0.1
    lbox(mb, "trim", c, left, n, hw, hw + ft, 0.0, h + ft, 0.0, 0.09)
    lbox(mb, "trim", c, left, n, -hw - ft, -hw, 0.0, h + ft, 0.0, 0.09)
    lbox(mb, "trim", c, left, n, -hw, hw, h, h + ft, 0.0, 0.09)
    lbox(mb, "trim", c, left, n, -hw - ft - 0.07, hw + ft + 0.07, h + ft, h + ft + 0.07, 0.0, 0.15)
    lbox(mb, mat, c, left, n, -hw, hw, 0.0, h, 0.0, 0.035)
    for side in (-1.0, 1.0):
        x0, x1 = side * 0.05, side * (hw - 0.1)
        lbox(mb, mat, c, left, n, min(x0, x1), max(x0, x1), 0.14, h * 0.44, 0.035, 0.055)
    y0, y1 = h * 0.54, h - 0.12
    if glass_top:
        g = c + n * 0.04
        gx = hw - 0.13
        mb.face("glass", [g + left * gx + up * y1, g - left * gx + up * y1, g - left * gx + up * y0, g + left * gx + up * y0], tuple(n))
        lbox(mb, mat, c, left, n, -gx - 0.04, gx + 0.04, y1, y1 + 0.04, 0.035, 0.065)
        lbox(mb, mat, c, left, n, -gx - 0.04, gx + 0.04, y0 - 0.04, y0, 0.035, 0.065)
        lbox(mb, mat, c, left, n, gx, gx + 0.04, y0, y1, 0.035, 0.065)
        lbox(mb, mat, c, left, n, -gx - 0.04, -gx, y0, y1, 0.035, 0.065)
        lbox(mb, mat, c, left, n, -0.018, 0.018, y0, y1, 0.035, 0.055)
    else:
        for side in (-1.0, 1.0):
            x0, x1 = side * 0.05, side * (hw - 0.1)
            lbox(mb, mat, c, left, n, min(x0, x1), max(x0, x1), y0, y1, 0.035, 0.055)
    hx = -(hw - 0.14)
    lbox(mb, "brass", c, left, n, hx - 0.03, hx + 0.03, h * 0.46, h * 0.54, 0.035, 0.05)
    lbox(mb, "brass", c, left, n, hx - 0.07, hx + 0.02, h * 0.49, h * 0.51, 0.05, 0.11)
