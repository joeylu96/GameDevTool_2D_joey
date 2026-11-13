"""Pixel World 资产生成器（Blender 插件，P3）。

在 Blender 里按参数生成与 Godot 端画风一致的像素风低模资产（共用 shared/style/style.json 的调色板和 32 texel/米），
导出 glTF + catalog.json 到 Godot 工程，Godot 的资源库会自动列出它们。

使用：3D 视图 → 侧边栏（N）→ Pixel World 标签页：选资产类型、种子 → 「生成」；
「导出全部到 Godot」把所有资产的若干变体导出到 godot/assets/blender/。
命令行（无界面）：blender -b -P tools/blender_build_assets.py
"""
import importlib

bl_info = {
    "name": "Pixel World 资产生成器",
    "author": "GameDevTool_2D_joey",
    "version": (0, 1, 0),
    "blender": (5, 2, 0),
    "location": "3D 视图 > 侧边栏 > Pixel World",
    "description": "生成像素风低模资产（房屋、树、石井、集市摊位……）并导出到 Godot",
    "category": "Add Mesh",
}

if "bpy" in locals():
    from . import style, pixtex, builder, export
    from . import generators
    for m in (style, pixtex, builder, generators, export):
        importlib.reload(m)

import bpy
from pathlib import Path

from . import export
from .generators import GENERATORS

_DEFAULT_OUT = str(Path(__file__).resolve().parent.parent.parent / "godot" / "assets" / "blender")


class PW_Props(bpy.types.PropertyGroup):
    kind: bpy.props.EnumProperty(
        name="资产",
        items=[(k, getattr(GENERATORS[k], "NAME", k), "") for k in GENERATORS],
    )
    seed: bpy.props.IntProperty(name="种子", default=1, min=0)
    variants: bpy.props.IntProperty(name="每种变体数", default=4, min=1, max=16)
    out_dir: bpy.props.StringProperty(name="导出目录", subtype="DIR_PATH", default=_DEFAULT_OUT)


class PW_OT_generate(bpy.types.Operator):
    bl_idname = "pixel_world.generate"
    bl_label = "生成"
    bl_description = "在当前场景生成一个资产（同一个种子总是得到同一个结果）"
    bl_options = {"REGISTER", "UNDO"}

    def execute(self, context):
        p = context.scene.pixel_world
        obj, info = export.generate(p.kind, p.seed)
        obj.location = context.scene.cursor.location
        self.report({"INFO"}, "已生成 %s #%d" % (p.kind, p.seed))
        return {"FINISHED"}


class PW_OT_export_all(bpy.types.Operator):
    bl_idname = "pixel_world.export_all"
    bl_label = "导出全部到 Godot"
    bl_description = "清空当前场景，生成所有资产的若干变体，导出 .glb 和 catalog.json"

    def execute(self, context):
        p = context.scene.pixel_world
        cat = export.build_all(bpy.path.abspath(p.out_dir), variants=p.variants)
        self.report({"INFO"}, "已导出 %d 种资产到 %s" % (len(cat["assets"]), p.out_dir))
        return {"FINISHED"}


class PW_PT_panel(bpy.types.Panel):
    bl_label = "Pixel World"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "Pixel World"

    def draw(self, context):
        p = context.scene.pixel_world
        col = self.layout.column(align=True)
        col.prop(p, "kind")
        col.prop(p, "seed")
        col.operator("pixel_world.generate", icon="ADD")
        self.layout.separator()
        col = self.layout.column(align=True)
        col.prop(p, "variants")
        col.prop(p, "out_dir")
        col.operator("pixel_world.export_all", icon="EXPORT")


_CLASSES = (PW_Props, PW_OT_generate, PW_OT_export_all, PW_PT_panel)


def register():
    for c in _CLASSES:
        bpy.utils.register_class(c)
    bpy.types.Scene.pixel_world = bpy.props.PointerProperty(type=PW_Props)


def unregister():
    del bpy.types.Scene.pixel_world
    for c in reversed(_CLASSES):
        bpy.utils.unregister_class(c)
