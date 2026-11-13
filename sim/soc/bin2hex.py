#!/usr/bin/env python3
"""二进制 → $readmemh 用的 32 位小端字（每行 8 位十六进制）。"""
import sys

if len(sys.argv) != 3:
    print("用法: bin2hex.py <in.bin> <out.hex>")
    raise SystemExit(2)

data = bytearray(open(sys.argv[1], "rb").read())
if len(data) % 4:
    data += b"\x00" * (4 - len(data) % 4)

with open(sys.argv[2], "w") as f:
    for i in range(0, len(data), 4):
        w = data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24)
        f.write(f"{w:08x}\n")

print(f"bin2hex: {len(data)} 字节 -> {len(data)//4} 字 -> {sys.argv[2]}")
