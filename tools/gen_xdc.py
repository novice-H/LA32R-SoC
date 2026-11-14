#!/usr/bin/env python3
"""从 docs/引脚对照表_R-a3.xlsx 生成 constraints/thinpad_top.xdc。

用法: python3 tools/gen_xdc.py
输出: constraints/thinpad_top.xdc
校验: 每个 thinpad_top 端口位都必须有引脚；引脚不得重复。
"""
import re
import sys
import zipfile
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
XLSX = ROOT / "docs" / "引脚对照表_R-a3.xlsx"
OUT = ROOT / "constraints" / "thinpad_top.xdc"

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
T = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t"


def load_table():
    z = zipfile.ZipFile(XLSX)
    shared = ["".join(t.text or "" for t in si.iter(T))
              for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", NS)]
    sheet = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
    rows = {}
    for c in sheet.iter("{http://schemas.openxmlformats.org/spreadsheetml/2006/main}c"):
        ref = c.get("r")
        v = c.find("m:v", NS)
        if v is None:
            continue
        val = shared[int(v.text)] if c.get("t") == "s" else v.text
        m = re.match(r"([A-Z]+)(\d+)", ref)
        rows.setdefault(int(m.group(2)), {})[m.group(1)] = val
    table = {}
    for r, d in rows.items():
        if r == 1:
            continue
        name = (d.get("B") or "").strip()
        pin = (d.get("E") or "").strip()
        io = (d.get("I") or "").strip() or "LVCMOS33"
        if name and pin:
            if name in table:
                sys.exit(f"表内重名: {name}")
            table[name] = (pin, io)
    return table


# ---- 端口位 -> 引脚表信号名 ----
SEG_BITS = ["dp", "c", "d", "e", "b", "a", "f", "g"]   # dpy = {g,f,a,b,e,d,c,p}


def port_map():
    m = {}
    m["clk_50M"] = "clk"
    m["clk_11M0592"] = "clk_11m0592"
    m["clock_btn"] = "btn5"
    m["reset_btn"] = "btn6"
    m["txd"] = "gpio5"
    m["rxd"] = "gpio6"

    for i in range(4):
        m[f"touch_btn[{i}]"] = f"btn{i+1}"
    for i in range(32):
        m[f"dip_sw[{i}]"] = f"sw{i}"
    for i in range(16):
        m[f"leds[{i}]"] = f"led{i+1}"
    for i, s in enumerate(SEG_BITS):
        m[f"dpy0[{i}]"] = f"seg0_{s}"
        m[f"dpy1[{i}]"] = f"seg1_{s}"

    m["video_clk"] = "video_clk"
    m["video_hsync"] = "video_hsync"
    m["video_vsync"] = "video_vsync"
    m["video_de"] = "video_de"
    for i in range(3):
        m[f"video_red[{i}]"] = f"video_red{i}"
        m[f"video_green[{i}]"] = f"video_green{i}"
    for i in range(2):
        m[f"video_blue[{i}]"] = f"video_blue{i}"

    for p, s in (("base_ram", "base_ram"), ("ext_ram", "ext_ram")):
        for i in range(20):
            m[f"{p}_addr[{i}]"] = f"{s}_addr{i}"
        for i in range(4):
            m[f"{p}_be_n[{i}]"] = f"{s}_be{i}_n"
        for i in range(32):
            m[f"{p}_data[{i}]"] = f"{s}_data{i}"
        m[f"{p}_ce_n"] = f"{s}_ce_n"
        m[f"{p}_oe_n"] = f"{s}_oe_n"
        m[f"{p}_we_n"] = f"{s}_we_n"

    for i in range(23):
        m[f"flash_a[{i}]"] = f"nor_a{i}"
    for i in range(16):
        m[f"flash_d[{i}]"] = f"nor_dq{i}"
    m["flash_rp_n"] = "nor_rp_n"
    m["flash_vpen"] = "nor_vpen"
    m["flash_ce_n"] = "nor_ce_n"
    m["flash_oe_n"] = "nor_oe_n"
    m["flash_we_n"] = "nor_we_n"
    m["flash_byte_n"] = "nor_byte_n"
    return m


def main():
    table = load_table()
    pm = port_map()

    missing = [p for p in pm if pm[p] not in table]
    if missing:
        sys.exit("引脚表缺少信号: " + ", ".join(missing))

    pins = [table[s][0] for s in pm.values()]
    if len(set(pins)) != len(pins):
        seen, dup = set(), []
        for s in pm.values():
            if table[s][0] in seen:
                dup.append(s)
            seen.add(table[s][0])
        sys.exit("引脚重复: " + ", ".join(dup))

    lines = [
        "# ---------------------------------------------------------------------------",
        "# thinpad_top 引脚与时钟约束",
        "# 由 tools/gen_xdc.py 从 docs/引脚对照表_R-a3.xlsx 自动生成，请勿手改。",
        "# 生成命令: python3 tools/gen_xdc.py",
        "# ---------------------------------------------------------------------------",
        "",
        "# ---------------- 时钟 ----------------",
        f"set_property -dict {{PACKAGE_PIN {table['clk'][0]} IOSTANDARD {table['clk'][1]}}} [get_ports clk_50M]",
        "create_clock -period 20.000 -name clk_50M -waveform {0.000 10.000} [get_ports clk_50M]",
        "",
        "# 复位按钮走普通 IO，不占专用时钟线",
        "set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets reset_btn_IBUF]",
        "",
    ]

    groups = [
        ("按钮 / 拨码 / LED", [f"touch_btn[{i}]" for i in range(4)] +
                             [f"dip_sw[{i}]" for i in range(32)] +
                             [f"leds[{i}]" for i in range(16)] +
                             ["clock_btn", "reset_btn"]),
        ("数码管", [f"dpy0[{i}]" for i in range(8)] + [f"dpy1[{i}]" for i in range(8)]),
        ("DVI 视频", ["video_red[%d]" % i for i in range(3)] +
                    ["video_green[%d]" % i for i in range(3)] +
                    ["video_blue[%d]" % i for i in range(2)] +
                    ["video_clk", "video_hsync", "video_vsync", "video_de"]),
        ("BaseRAM", [f"base_ram_addr[{i}]" for i in range(20)] +
                    [f"base_ram_be_n[{i}]" for i in range(4)] +
                    [f"base_ram_data[{i}]" for i in range(32)] +
                    ["base_ram_ce_n", "base_ram_oe_n", "base_ram_we_n"]),
        ("ExtRAM", [f"ext_ram_addr[{i}]" for i in range(20)] +
                   [f"ext_ram_be_n[{i}]" for i in range(4)] +
                   [f"ext_ram_data[{i}]" for i in range(32)] +
                   ["ext_ram_ce_n", "ext_ram_oe_n", "ext_ram_we_n"]),
        ("串口", ["txd", "rxd"]),
        ("NOR Flash（本设计不用，仅保留约束）", [f"flash_a[{i}]" for i in range(23)] +
                                               [f"flash_d[{i}]" for i in range(16)] +
                                               ["flash_rp_n", "flash_vpen", "flash_ce_n",
                                                "flash_oe_n", "flash_we_n", "flash_byte_n"]),
        ("备用时钟", ["clk_11M0592"]),
    ]

    total = 0
    for title, ports in groups:
        lines.append(f"# ---------------- {title} ----------------")
        for p in ports:
            sig = pm[p]
            pin, io = table[sig]
            lines.append(f"set_property -dict {{PACKAGE_PIN {pin} IOSTANDARD {io}}} [get_ports {{{p}}}]")
            total += 1
        lines.append("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines).rstrip("\n") + "\n")

    print(f"生成 {OUT.relative_to(ROOT)}：{total} 个引脚，覆盖 {len(pm)} 个端口位")
    print(f"引脚唯一性检查通过，引脚表共 {len(table)} 项")


if __name__ == "__main__":
    main()
