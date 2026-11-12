#!/usr/bin/env python3
"""把 shared/style/style.json 同步为 Godot 插件可直接 preload 的 GDScript 常量文件。

风格规范只有一个来源（style.json），Godot 与 Blender 插件都从它派生。
修改 style.json 后运行：python3 tools/sync_style.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "shared" / "style" / "style.json"
DST = ROOT / "godot" / "addons" / "pixel_world" / "style" / "pw_style_data.gd"
GPL = ROOT / "shared" / "style" / "palette.gpl"


def main() -> None:
    style = json.loads(SRC.read_text(encoding="utf-8"))
    pal = style["palette"]
    cam = style["camera"]

    lines = [
        "# 自动生成，请勿手改。来源：shared/style/style.json（运行 tools/sync_style.py 更新）",
        "@tool",
        "extends RefCounted",
        "",
        f"const TEXEL_DENSITY := {float(style['texel_density'])}",
        f"const PIXEL_HEIGHT := {int(style['pixel_height'])}",
        f"const CAMERA_FOV := {float(cam['fov'])}",
        f"const CAMERA_PITCH_DEG := {float(cam['pitch_deg'])}",
        f"const CAMERA_DISTANCE := {float(cam['distance'])}",
        "",
        "const PALETTE := {",
    ]
    for name, hexv in pal.items():
        lines.append(f'\t"{name}": Color("{hexv}"),')
    lines.append("}")
    DST.write_text("\n".join(lines) + "\n", encoding="utf-8")

    gpl = ["GIMP Palette", "Name: PixelWorld", "Columns: 8", "#"]
    for name, hexv in pal.items():
        h = hexv.lstrip("#")
        r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
        gpl.append(f"{r:3d} {g:3d} {b:3d}\t{name}")
    GPL.write_text("\n".join(gpl) + "\n", encoding="utf-8")
    print(f"wrote {DST.relative_to(ROOT)} and {GPL.relative_to(ROOT)} ({len(pal)} colors)")


if __name__ == "__main__":
    main()
