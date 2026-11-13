"""生成 + 导出：每个资产的每个变体导出成一个 .glb，并写 catalog.json（Godot 端 PWBlenderCatalog 读取）。

catalog.json：
{
  "version": 1, "generator": "pixel_world_blender x.y.z", "blender": "5.2.4", "texel_density": 32,
  "assets": [
    {"id": "bl_cottage", "kind": "cottage", "name": "农舍", "category": "buildings", "desc": ..., "vary": ...,
     "files": ["cottage_0.glb", ...], "footprint": [宽, 深], "height": 高, "plant": false}
  ]
}
"""
import json
from pathlib import Path

import bpy

from . import builder, style
from .generators import GENERATORS

VERSION = "0.1.0"


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for item in list(coll):
            if item.users == 0:
                coll.remove(item)
    builder._mat_cache.clear()


def generate(kind, seed, collection=None, **params):
    """在当前场景里生成一个资产对象，返回 (object, info)"""
    gen = GENERATORS[kind]
    mb, info = gen.build(seed, **params)
    obj = mb.build("%s_%d" % (kind, seed), collection)
    return obj, info


def export_object(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )


def _rel(path):
    """路径记成相对仓库根目录（Windows / macOS 都能用）"""
    root = Path(__file__).resolve().parent.parent.parent
    try:
        return Path(path).resolve().relative_to(root).as_posix()
    except ValueError:
        return Path(path).name


def build_all(out_dir, kinds=None, variants=4, seed0=1):
    """生成所有（或指定）资产的若干变体，导出到 out_dir，写 catalog.json"""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    catalog = {
        "version": 1,
        "generator": "pixel_world_blender " + VERSION,
        "blender": bpy.app.version_string,
        "texel_density": style.texel_density(),
        "style": _rel(style.load()["path"]),
        "assets": [],
    }
    for kind in kinds or GENERATORS.keys():
        gen = GENERATORS[kind]
        files = []
        info = {}
        for v in range(variants):
            clear_scene()
            obj, info = generate(kind, seed0 + v)
            name = "%s_%d.glb" % (kind, v)
            export_object(obj, out / name)
            files.append(name)
        catalog["assets"].append({
            "id": "bl_" + kind,
            "kind": kind,
            "name": gen.NAME,
            "category": gen.CATEGORY,
            "desc": gen.DESC,
            "vary": gen.VARY,
            "files": files,
            "footprint": [round(x, 2) for x in info.get("footprint", [1, 1])],
            "height": round(info.get("height", 1.0), 2),
            "plant": bool(info.get("plant", False)),
        })
    (out / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8")
    clear_scene()
    return catalog
