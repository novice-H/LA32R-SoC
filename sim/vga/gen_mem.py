#!/usr/bin/env python3
"""把 fb0.bin / fb1.bin 转成 $readmemh 用的 32 位小端字。

用法:
  gen_mem.py fb0.bin out.hex              # 只装 FB0
  gen_mem.py fb0.bin fb1.bin out.hex      # FB0 + FB1（FB1 基址 131072 字）

每个 32 位字 = 4 个连续像素，像素 x 位于字节道 (x % 4)，低字节在前。
"""
import sys

FB0_WORDS = 120000
FB1_WORD_BASE = 131072


def to_words(path: str):
    data = bytearray(open(path, "rb").read())
    if len(data) % 4:
        data += b"\x00" * (4 - len(data) % 4)
    return [
        data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24)
        for i in range(0, len(data), 4)
    ]


def main() -> int:
    if len(sys.argv) == 3:
        fb0, fb1, dst = sys.argv[1], None, sys.argv[2]
    elif len(sys.argv) == 4:
        fb0, fb1, dst = sys.argv[1], sys.argv[2], sys.argv[3]
    else:
        print(__doc__)
        return 2

    words0 = to_words(fb0)
    if len(words0) != FB0_WORDS:
        print(f"错误: {fb0} 应有 {FB0_WORDS} 字，实际 {len(words0)}")
        return 1

    lines = [f"{w:08x}" for w in words0]

    if fb1 is not None:
        words1 = to_words(fb1)
        if len(words1) != FB0_WORDS:
            print(f"错误: {fb1} 应有 {FB0_WORDS} 字，实际 {len(words1)}")
            return 1
        lines += ["00000000"] * (FB1_WORD_BASE - len(lines))
        lines += [f"{w:08x}" for w in words1]

    with open(dst, "w") as f:
        f.write("\n".join(lines) + "\n")

    print(f"gen_mem: FB0 {len(words0)} 字"
          + (f"，FB1 {len(words1) if fb1 else 0} 字 @ 字偏移 {FB1_WORD_BASE}" if fb1 else "")
          + f" -> {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
