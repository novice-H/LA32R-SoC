#!/usr/bin/env python3
"""对比预期图片与仿真重建图片。

用法: compare.py <expected.ppm> <actual.ppm> <输出目录> [前缀]

产物：
  <输出目录>/side_by_side.png   左：预期 / 右：仿真
  <输出目录>/diff.png           差异放大 4 倍（黑=一致）

退出码 0 = 逐像素完全一致。
"""
import sys

from PIL import Image


def main() -> int:
    if len(sys.argv) not in (4, 5):
        print(__doc__)
        return 2
    exp_path, act_path, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
    prefix = sys.argv[4] if len(sys.argv) == 5 else ""

    exp = Image.open(exp_path).convert("RGB")
    act = Image.open(act_path).convert("RGB")
    if exp.size != act.size:
        print(f"FAIL: 尺寸不一致 {exp.size} vs {act.size}")
        return 1

    w, h = exp.size
    pe, pa = exp.load(), act.load()

    mismatch = 0
    max_diff = 0
    xmin, ymin, xmax, ymax = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            e = pe[x, y]
            a = pa[x, y]
            if e != a:
                mismatch += 1
                d = max(abs(e[0] - a[0]), abs(e[1] - a[1]), abs(e[2] - a[2]))
                if d > max_diff:
                    max_diff = d
                if x < xmin: xmin = x
                if y < ymin: ymin = y
                if x > xmax: xmax = x
                if y > ymax: ymax = y

    total = w * h
    match = total - mismatch
    print(f"图片尺寸      : {w} x {h} = {total} 像素")
    print(f"一致像素      : {match} ({100.0 * match / total:.4f}%)")
    print(f"不一致像素    : {mismatch}")
    if mismatch:
        print(f"最大通道差    : {max_diff}")
        print(f"不一致区域    : x {xmin}..{xmax}, y {ymin}..{ymax}")

    # 并排对比图
    gap = 8
    side = Image.new("RGB", (w * 2 + gap, h), (32, 32, 32))
    side.paste(exp, (0, 0))
    side.paste(act, (w + gap, 0))
    side.save(f"{outdir}/{prefix}side_by_side.png")

    # 差异图（放大 4 倍，黑=一致）
    diff = Image.new("RGB", (w, h), (0, 0, 0))
    pd = diff.load()
    for y in range(h):
        for x in range(w):
            e = pe[x, y]
            a = pa[x, y]
            d = max(abs(e[0] - a[0]), abs(e[1] - a[1]), abs(e[2] - a[2]))
            v = min(255, d * 4)
            pd[x, y] = (v, v, v)
    diff.save(f"{outdir}/{prefix}diff.png")

    print(f"已写出        : {outdir}/{prefix}side_by_side.png, {outdir}/{prefix}diff.png")
    if mismatch == 0:
        print("结果: PASS（画面与预期逐像素一致）")
        return 0
    print(f"结果: FAIL（画面与预期不一致，见 {prefix}diff.png）")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
