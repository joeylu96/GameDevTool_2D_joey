"""命令行生成 HD-2D 像素角色精灵表（无界面）：

    blender -b --factory-startup -P tools/blender_build_sprites.py                       # 全部角色
    blender -b --factory-startup -P tools/blender_build_sprites.py -- --only swordsman,maiden
    blender -b --factory-startup -P tools/blender_build_sprites.py -- --spec my_hero.json  # 额外的规格文件
    blender -b --factory-startup -P tools/blender_build_sprites.py -- --only mercenary --anims idle,attack

角色来源（按顺序合并，同 id 后者覆盖前者）：
  1. 内置预设（blender/pw_specs/charspec.py 的 PRESETS）
  2. shared/asset_specs/characters/*.json（大模型 / 资产工坊生成的规格都存在这里）
  3. 随机路人 villager_1..N（--villagers N，默认 6；只渲染待机、走路、挥手）
  4. --spec 指定的文件
自定义动作：shared/asset_specs/actions/*.json。角色规格里写 "extra_anims": ["动作 id"]，或者动作规格里写
"for": ["角色 id", ...]（"all" = 全部主要角色，不含随机路人），这些角色就会多渲染这个动作。
输出：godot/assets/sprites/<角色>/<动作>.png（8 方向 × N 帧）+ catalog.json。
需要 Blender 5.2 LTS。
"""
import argparse
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "blender"))

import bpy  # noqa: E402

from pixel_world_blender import sprites  # noqa: E402
from pw_specs import charspec, poses  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--out", default=str(ROOT / "godot" / "assets" / "sprites"))
ap.add_argument("--only", default="")
ap.add_argument("--anims", default="", help="只渲染这些动作（逗号分隔）")
ap.add_argument("--villagers", type=int, default=0)
ap.add_argument("--spec", action="append", default=[])
ap.add_argument("--specs-dir", default=str(ROOT / "shared" / "asset_specs"))
ap.add_argument("--preview-dir", default=str(ROOT / ".workshop" / "previews"), help="预览图输出目录（资产工坊网页用）")
args = ap.parse_args(argv)

if bpy.app.version < (5, 2, 0):
    print("警告：项目锁定 Blender 5.2 LTS，当前是 %s" % bpy.app.version_string)


def load_json_dir(d):
    out = []
    for p in sorted(Path(d).glob("*.json")) if Path(d).exists() else []:
        try:
            out.append(json.loads(p.read_text(encoding="utf-8")))
        except ValueError as e:
            print("跳过 %s：%s" % (p, e))
    return out


actions = {}
for a in load_json_dir(Path(args.specs_dir) / "actions"):
    try:
        act, warn = poses.validate_action(a)
        actions[act["id"]] = act
        for w in warn:
            print("  动作 %s：%s" % (act["id"], w))
    except ValueError as e:
        print("跳过动作：%s" % e)

specs = {}
for s in charspec.PRESETS:
    specs[s["id"]] = (s, None)
for s in charspec.NPCS:  # 中世纪小镇的商人小贩和镇民：只要待机 / 走路 / 挥手
    specs[s["id"]] = (s, poses.VILLAGER_ANIMS)
for s in load_json_dir(Path(args.specs_dir) / "characters"):
    specs[charspec.slug(s.get("id") or s.get("name"))] = (s, None)
for i in range(1, args.villagers + 1):
    v = charspec.random_villager(i)
    specs[v["id"]] = (v, poses.VILLAGER_ANIMS)
for f in args.spec:
    s = json.loads(Path(f).read_text(encoding="utf-8"))
    specs[charspec.slug(s.get("id") or s.get("name"))] = (s, None)

only = [k for k in args.only.split(",") if k]
anims = [k for k in args.anims.split(",") if k] or None
t0 = time.time()
entries = []
for cid, (spec, default_anims) in specs.items():
    if only and cid not in only:
        continue
    t1 = time.time()
    want = anims
    if want is None:
        extra = [aid for aid, act in actions.items()
                 if cid in act.get("for", []) or ("all" in act.get("for", []) and default_anims is None)]
        if default_anims is None:
            want = poses.DEFAULT_ANIMS + [x for x in spec.get("extra_anims", []) if x in actions] + extra
        else:
            want = default_anims + extra
        want = list(dict.fromkeys(want))
    e = sprites.render_character(spec, args.out, want, actions,
                                 preview=str(Path(args.preview_dir) / ("char_%s.png" % cid)) if "idle" in want else None)
    entries.append(e)
    print("  角色 %-14s %-8s %s  %.1f 秒" % (cid, e["name"], ",".join(e["anims"]), time.time() - t1))
cat = sprites.write_catalog(args.out, entries)
print("已生成 %d 个角色（目录里共 %d 个）到 %s，用时 %.1f 秒" % (len(entries), len(cat["characters"]), args.out, time.time() - t0))
