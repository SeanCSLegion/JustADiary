#!/usr/bin/env python3
"""把「改前 / 改后」两次取证的同名帧并排/上下拼起来，看改动到底改了哪儿。

用法:
    python3 tools/film_compare.py <dir_before> <dir_after> <case> <out.png> \
        [--region x0,y0,x1,y1] [--zoom 2.0]

帧按「同序号」配对（两次运行的截图节奏一致，序号即可对齐）。
**只看静止帧的差异**：动画中间帧的两次运行相位会差十几毫秒，逐像素差异会被位移淹没。

Note: 依赖 numpy + Pillow（`python3 -m pip install numpy pillow`）。
"""
import argparse
import glob
import os
import re

import numpy as np
from PIL import Image, ImageDraw

S = 3.0


def frames(d, case):
    out = {}
    for f in sorted(glob.glob(os.path.join(d, f"{case}-*.png"))):
        m = re.search(r"-(\d+)-(\d+)ms", f)
        if not m:
            continue
        out[(f.split(f"{case}-")[1].split("-")[0], int(m.group(1)))] = (int(m.group(2)), f)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("before")
    ap.add_argument("after")
    ap.add_argument("case")
    ap.add_argument("out")
    ap.add_argument("--region", default=None, help="x0,y0,x1,y1（pt）")
    ap.add_argument("--zoom", type=float, default=1.0)
    args = ap.parse_args()

    fb, fa = frames(args.before, args.case), frames(args.after, args.case)
    keys = sorted(set(fb) & set(fa))
    if not keys:
        raise SystemExit("no matching frames")

    print(f"{'frame':>16} | {'before ms':>9} {'after ms':>9} | mean|Δ|  max|Δ|  差异像素占比")
    for k in keys:
        mb, p_b = fb[k]
        ma, p_a = fa[k]
        ab = np.asarray(Image.open(p_b).convert("L"), dtype=np.int16)
        aa = np.asarray(Image.open(p_a).convert("L"), dtype=np.int16)
        d = np.abs(ab - aa)
        big = (d > 12)
        print(f"{k[0] + '-' + str(k[1]):>16} | {mb:>9} {ma:>9} | {d.mean():7.3f} {d.max():7.0f} "
              f" {100.0 * big.mean():7.3f}%")

    if args.region:
        x0, y0, x1, y1 = (int(float(v) * S) for v in args.region.split(","))
        tiles = []
        for k in keys:
            for tag, src in (("before", fb[k][1]), ("after", fa[k][1])):
                im = Image.open(src).convert("RGB").crop((x0, y0, x1, y1))
                if args.zoom != 1.0:
                    im = im.resize((int(im.width * args.zoom), int(im.height * args.zoom)),
                                   Image.LANCZOS)
                tiles.append((f"{tag} {k[0]}-{k[1]} {fb[k][0] if tag == 'before' else fa[k][0]}ms", im))
        w = max(t[1].width for t in tiles)
        h = max(t[1].height for t in tiles)
        sheet = Image.new("RGB", (w + 8, (h + 22) * len(tiles) + 8), (255, 255, 255))
        d = ImageDraw.Draw(sheet)
        y = 4
        for label, im in tiles:
            d.text((6, y + 4), label, fill=(190, 0, 0))
            y += 22
            sheet.paste(im, (4, y))
            y += h
        sheet.save(args.out)
        print(f"-> {args.out} ({sheet.width}x{sheet.height})")


if __name__ == "__main__":
    main()
