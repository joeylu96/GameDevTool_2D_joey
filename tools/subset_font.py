#!/usr/bin/env python3
"""把思源黑体（Noto Sans SC，OFL 许可）裁剪成只含界面用字的小字体，供 Godot 界面（含 Web 导出）显示中文。

为什么要裁剪：完整字体约 8 MB，Web 版下载太慢；界面实际只用到几百个字。
界面文字改动后重新运行一次：

    python3 -m venv .venv && .venv/bin/pip install fonttools
    .venv/bin/python tools/subset_font.py <完整字体路径 NotoSansSC-Regular.otf>

完整字体下载地址：https://github.com/notofonts/noto-cjk/raw/main/Sans/SubsetOTF/SC/NotoSansSC-Regular.otf
输出：godot/addons/pixel_world/ui/fonts/NotoSansSC-PW.otf（以及同目录的 OFL.txt）
"""
import sys
from pathlib import Path

from fontTools import subset

ROOT = Path(__file__).resolve().parent.parent
SCAN = [ROOT / "godot" / "addons", ROOT / "godot" / "demo", ROOT / "godot" / "assets", ROOT / "blender"]
OUT_DIR = ROOT / "godot" / "addons" / "pixel_world" / "ui" / "fonts"
OUT = OUT_DIR / "NotoSansSC-PW.otf"

# 总是保留：ASCII、常用中文标点、全角符号，以及一些动态拼出来的字（数字单位等）
BASE = "".join(chr(c) for c in range(0x20, 0x7F))
BASE += "，。、；：？！“”‘’（）《》【】—…·～￥％＋－×÷＝＜＞／「」『』"
BASE += "零一二三四五六七八九十百千万米秒分时天个张棵盏栋座条片处种类"


def collect() -> str:
    chars = set(BASE)
    for d in SCAN:
        for p in d.rglob("*"):
            if p.suffix in (".gd", ".tscn", ".tres", ".json", ".py") and p.is_file():
                text = p.read_text(encoding="utf-8", errors="ignore")
                chars.update(ch for ch in text if ord(ch) > 0x7F)
    return "".join(sorted(chars))


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = Path(sys.argv[1])
    text = collect()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    font = subset.load_font(str(src), opts)
    sub = subset.Subsetter(opts)
    sub.populate(text=text)
    sub.subset(font)
    subset.save_font(font, str(OUT), opts)
    lic = src.parent / "LICENSE"
    if lic.exists():
        (OUT_DIR / "OFL.txt").write_text(lic.read_text(encoding="utf-8"), encoding="utf-8")
    print(f"{len(text)} 个字符 -> {OUT.relative_to(ROOT)}（{OUT.stat().st_size // 1024} KB）")


if __name__ == "__main__":
    main()
