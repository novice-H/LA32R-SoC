#!/usr/bin/env python3
"""把 fb0.bin（字节流）转换成 $readmemh 用的 32 位小端字。

用法: gen_mem.py <fb0.bin> <fb0.hex>
每个 32 位字 = 4 个连续像素，像素 x 位于字节道 (x % 4)，低字节在前。
"""
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    data = bytearray(open(src, "rb").read())
    if len(data) % 4:
        data += b"\x00" * (4 - len(data) % 4)

    with open(dst, "w") as f:
        for i in range(0, len(data), 4):
            w = data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24)
            f.write(f"{w:08x}\n")

    print(f"gen_mem: {len(data)} 字节 -> {len(data)//4} 个 32 位字 -> {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
