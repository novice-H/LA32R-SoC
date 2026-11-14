#!/usr/bin/env python3
"""校验 constraints/thinpad_top.xdc 是否覆盖 soc/thinpad_top.v 的全部端口位。

用法: python3 tools/check_xdc.py
退出码 0 = 完全覆盖且引脚无重复。
"""
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RTL = ROOT / "soc" / "thinpad_top.v"
XDC = ROOT / "constraints" / "thinpad_top.xdc"


def rtl_ports():
    txt = RTL.read_text()
    m = re.search(r"module\s+thinpad_top\s*\((.*?)\);", txt, re.S)
    if not m:
        sys.exit("找不到 thinpad_top 模块端口表")
    ports = set()
    for decl in m.group(1).split(","):
        mm = re.search(
            r"\b(input|output|inout)\b\s+(?:wire\s+)?(?:\[(\d+):(\d+)\]\s*)?"
            r"([A-Za-z_][A-Za-z0-9_]*)", decl)
        if not mm:
            continue
        name = mm.group(4)
        if mm.group(2) is not None:
            hi, lo = int(mm.group(2)), int(mm.group(3))
            for i in range(lo, hi + 1):
                ports.add(f"{name}[{i}]")
        else:
            ports.add(name)
    return ports


def xdc_ports():
    xdc = XDC.read_text()
    pins = {}
    for line in xdc.splitlines():
        if line.strip().startswith("#"):
            continue
        mm = re.search(
            r"PACKAGE_PIN\s+([A-Z]+\d+).*\[get_ports\s+(?:\{([^}]+)\}|([A-Za-z0-9_]+))\]", line)
        if mm:
            pins[mm.group(2) or mm.group(3)] = mm.group(1)
    return pins


def main():
    rp = rtl_ports()
    xp = xdc_ports()
    missing = sorted(rp - set(xp))
    extra = sorted(set(xp) - rp)

    print(f"RTL 端口位: {len(rp)}   XDC 约束位: {len(xp)}")
    if missing:
        print(f"缺失约束 ({len(missing)}):")
        for p in missing:
            print("  ", p)
    if extra:
        print(f"多余约束 ({len(extra)}):")
        for p in extra:
            print("  ", p)

    dup = [pin for pin, n in Counter(xp.values()).items() if n > 1]
    if dup:
        print("引脚重复:", dup)

    ok = not missing and not extra and not dup
    print("结果:", "PASS（全覆盖、无重复）" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
