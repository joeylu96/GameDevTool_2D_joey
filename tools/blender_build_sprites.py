"""命令行生成 HD-2D 像素角色精灵表（无界面）：

    blender -b --factory-startup -P tools/blender_build_sprites.py                 # 全部预设角色
    blender -b --factory-startup -P tools/blender_build_sprites.py -- --only swordsman,maiden

输出：godot/assets/sprites/<角色>.png（8 方向 × 10 帧：待机 4 + 走路 6）+ catalog.json。
需要 Blender 5.2 LTS（与 README 的版本要求一致）。
"""
import argparse
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "blender"))

import bpy  # noqa: E402

from pixel_world_blender import sprites  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--out", default=str(ROOT / "godot" / "assets" / "sprites"))
ap.add_argument("--only", default="")
args = ap.parse_args(argv)

if bpy.app.version < (5, 2, 0):
    print("警告：项目锁定 Blender 5.2 LTS，当前是 %s" % bpy.app.version_string)

t0 = time.time()
only = [k for k in args.only.split(",") if k] or None
cat = sprites.build_all(args.out, only=only)
print("已生成 %d 个角色到 %s，用时 %.1f 秒" % (len(cat["characters"]), args.out, time.time() - t0))
