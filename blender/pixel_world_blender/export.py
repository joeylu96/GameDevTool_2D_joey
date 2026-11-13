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


def render_preview(obj, path, size=320):
    """资产工坊用的预览图：Workbench 显示像素贴图，从斜前上方看，透明底。"""
    import math
    from mathutils import Vector
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x = size
    sc.render.resolution_y = size
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_shadows = False
    sh.show_cavity = False
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    ctr = (lo + hi) * 0.5
    span = max((hi - lo).length, 0.5)
    cam_data = bpy.data.cameras.new("pw_preview_cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = span * 1.05
    cam = bpy.data.objects.new("pw_preview_cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    yaw, pitch = math.radians(-60.0), math.radians(28.0)  # 正面朝 -Y：从左前上方看
    d = Vector((math.cos(yaw) * math.cos(pitch), math.sin(yaw) * math.cos(pitch), math.sin(pitch)))
    cam.location = ctr + d * (span * 3.0)
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    sc.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    bpy.data.cameras.remove(cam_data)


def _rel(path):
    """路径记成相对仓库根目录（Windows / macOS 都能用）"""
    root = Path(__file__).resolve().parent.parent.parent
    try:
        return Path(path).resolve().relative_to(root).as_posix()
    except ValueError:
        return Path(path).name


def _entry(kind, name, category, desc, vary, files, info, tags, source="generator"):
    return {
        "id": "bl_" + kind,
        "kind": kind,
        "name": name,
        "category": category,
        "desc": desc,
        "vary": vary,
        "tags": list(tags or []),
        "source": source,
        "files": files,
        "footprint": [round(x, 2) for x in info.get("footprint", [1, 1])],
        "height": round(info.get("height", 1.0), 2),
        "plant": bool(info.get("plant", False)),
    }


def load_prop_specs(specs_dir):
    """shared/asset_specs/props/*.json → 校验过的规格列表"""
    from .generators import spec_parts  # noqa: F401（确保 pw_specs 在 sys.path 里）
    from pw_specs import propspec
    out = []
    d = Path(specs_dir)
    for p in sorted(d.glob("*.json")) if d.exists() else []:
        try:
            spec, warn = propspec.validate(json.loads(p.read_text(encoding="utf-8")))
            for w in warn:
                print("  规格 %s：%s" % (p.name, w))
            out.append(spec)
        except ValueError as e:
            print("跳过规格 %s：%s" % (p.name, e))
    return out


def export_spec(spec, out_dir, seed0=1, preview_dir=None):
    """按一个摆件规格生成全部变体并导出，返回目录条目。preview_dir：第一个变体的预览图放这里"""
    from .generators import spec_parts
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    files = []
    info = {}
    kind = "spec_" + spec["id"]
    for v in range(spec.get("variants", 4)):
        clear_scene()
        mb, info = spec_parts.build_from_spec(spec, seed0 + v)
        obj = mb.build("%s_%d" % (kind, v))
        name = "%s_%d.glb" % (kind, v)
        export_object(obj, out / name)
        files.append(name)
        if preview_dir and v == 0:
            render_preview(obj, Path(preview_dir) / ("prop_%s.png" % kind))
    return _entry(kind, spec["name"], spec["category"], spec["desc"], spec["vary"], files, info, spec.get("tags"),
                  source="spec")


def build_all(out_dir, kinds=None, variants=4, seed0=1, specs_dir=None, preview_dir=None):
    """生成所有（或指定）资产的若干变体，导出到 out_dir，写 catalog.json。
    kinds：生成器名或 "spec_<id>"；只重做部分资产时，目录里其他资产的条目保留。"""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    path = out / "catalog.json"
    old = []
    if kinds and path.exists():
        try:
            old = json.loads(path.read_text(encoding="utf-8")).get("assets", [])
        except ValueError:
            old = []
    catalog = {
        "version": 2,
        "generator": "pixel_world_blender " + VERSION,
        "blender": bpy.app.version_string,
        "texel_density": style.texel_density(),
        "style": _rel(style.load()["path"]),
        "assets": [],
    }
    for kind in GENERATORS.keys():
        if kinds and kind not in kinds:
            continue
        gen = GENERATORS[kind]
        files = []
        info = {}
        for v in range(variants):
            clear_scene()
            obj, info = generate(kind, seed0 + v)
            name = "%s_%d.glb" % (kind, v)
            export_object(obj, out / name)
            files.append(name)
            if preview_dir and v == 0:
                render_preview(obj, Path(preview_dir) / ("prop_%s.png" % kind))
        catalog["assets"].append(_entry(kind, gen.NAME, gen.CATEGORY, gen.DESC, gen.VARY, files, info,
                                        getattr(gen, "TAGS", [])))
    for spec in load_prop_specs(specs_dir) if specs_dir else []:
        if kinds and "spec_" + spec["id"] not in kinds:
            continue
        catalog["assets"].append(export_spec(spec, out, seed0, preview_dir))
    done = {a["id"] for a in catalog["assets"]}
    catalog["assets"] = [a for a in old if a.get("id") not in done] + catalog["assets"]
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8")
    clear_scene()
    return catalog
