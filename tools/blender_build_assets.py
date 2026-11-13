"""命令行批量生成 Blender 资产并导出到 Godot（无界面）：

    blender -b -P tools/blender_build_assets.py                     # 全部资产，每种 4 个变体
    blender -b -P tools/blender_build_assets.py -- --variants 6 --only cottage,well
    blender -b -P tools/blender_build_assets.py -- --only spec_snowman        # 只重做一个规格摆件
规格摆件：shared/asset_specs/props/*.json（资产工坊 / 大模型生成），格式见 blender/pw_specs/propspec.py。
    blender -b -P tools/blender_build_assets.py -- --out <目录>

输出：godot/assets/blender/*.glb + catalog.json。之后在 Godot 里导入（打开编辑器，或 godot --headless --import）。
需要 Blender 5.2 LTS（与 README 的版本要求一致）。
"""
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "blender"))

import bpy  # noqa: E402

from pixel_world_blender import export  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--out", default=str(ROOT / "godot" / "assets" / "blender"))
ap.add_argument("--variants", type=int, default=4)
ap.add_argument("--only", default="", help="生成器名或 spec_<规格 id>，逗号分隔")
ap.add_argument("--specs-dir", default=str(ROOT / "shared" / "asset_specs" / "props"))
args = ap.parse_args(argv)

if bpy.app.version < (5, 2, 0):
    print("警告：项目锁定 Blender 5.2 LTS，当前是 %s" % bpy.app.version_string)

kinds = [k for k in args.only.split(",") if k] or None
cat = export.build_all(args.out, kinds=kinds, variants=args.variants, specs_dir=args.specs_dir)
for a in cat["assets"]:
    print("  %-14s %-8s %d 个变体  占地 %s  高 %.1f 米" % (a["id"], a["name"], len(a["files"]), a["footprint"], a["height"]))
print("已导出 %d 种资产到 %s" % (len(cat["assets"]), args.out))
