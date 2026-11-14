"""给已经导出的 Blender 资产补预览图（资产工坊网页用；预览图在 .workshop/previews/，不进仓库）：

    blender -b --factory-startup -P tools/blender_render_previews.py                  # 缺预览图的全部补上
    blender -b --factory-startup -P tools/blender_render_previews.py -- --only cottage,spec_snowman --force

直接读 godot/assets/blender/ 里每种资产的第一个 .glb 渲染，不重新生成模型。
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "blender"))

import bpy  # noqa: E402

from pixel_world_blender import export  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--assets", default=str(ROOT / "godot" / "assets" / "blender"))
ap.add_argument("--out", default=str(ROOT / ".workshop" / "previews"))
ap.add_argument("--only", default="")
ap.add_argument("--force", action="store_true")
args = ap.parse_args(argv)

cat = json.loads((Path(args.assets) / "catalog.json").read_text(encoding="utf-8"))
only = [k for k in args.only.split(",") if k]
n = 0
for a in cat.get("assets", []):
    kind = a["kind"]
    if only and kind not in only:
        continue
    out = Path(args.out) / ("prop_%s.png" % kind)
    if out.exists() and out.with_name(out.stem + "_spin.png").exists() and not args.force:
        continue
    files = a.get("files", [])
    if not files:
        continue
    export.clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(Path(args.assets) / files[0]))
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not objs:
        continue
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    export.render_preview(bpy.context.view_layer.objects.active, out)
    n += 1
    print("  预览 %s" % kind)
print("补了 %d 张预览图" % n)
