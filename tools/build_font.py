#!/usr/bin/env python3
"""產生 art/NotoSansTC-subset.otf：Noto Sans CJK TC 的子集（Big5 常用字 + 專案內出現的所有字）。
網頁版沒有系統字型，所以要把中文字型包進去。新增了罕見字就重跑一次：
    python3 tools/build_font.py /path/to/NotoSansCJK-Regular.ttc
Noto Sans CJK 以 SIL Open Font License 1.1 授權。
"""
import glob, os, sys
from fontTools.ttLib import TTCollection
from fontTools import subset

src = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
root = os.path.join(os.path.dirname(__file__), "..")
idx = next(i for i, f in enumerate(TTCollection(src).fonts) if f["name"].getDebugName(1) == "Noto Sans CJK TC")
chars = set(chr(c) for c in range(0x20, 0x7F))
for hi in range(0xA1, 0xC7):
    for lo in list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF)):
        try:
            chars.add(bytes([hi, lo]).decode("big5"))
        except Exception:
            pass
for pat in ("**/*.gd", "data/*.json"):
    for p in glob.glob(os.path.join(root, pat), recursive=True):
        chars.update(open(p, encoding="utf-8").read())
chars.update("★⏸▶✓✗⚠†✝⏳·－＋×→←↑↓…")
opts = subset.Options()
opts.font_number = idx
opts.layout_features = ["kern", "liga", "locl"]
opts.name_IDs = [1, 2]
font = subset.load_font(src, opts)
s = subset.Subsetter(opts)
s.populate(text="".join(chars))
s.subset(font)
out = os.path.join(root, "art", "NotoSansTC-subset.otf")
subset.save_font(font, out, opts)
print("wrote", out, os.path.getsize(out), "bytes,", len(chars), "chars")
