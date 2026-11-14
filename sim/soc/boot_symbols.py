"""Convert the linked smoke-test symbols into testbench metadata."""
from pathlib import Path
import sys

mode = sys.argv[3] if len(sys.argv) == 4 else "boot"
name_sets = {
    "input": ("input_test_result", "input_test_checks", "_boot_halt"),
    "framebuffer": ("framebuffer_test_result", "framebuffer_test_checks", "_boot_halt"),
    "boot": ("__data_start", "__data_end", "__bss_start", "__bss_end",
             "smoke_result", "smoke_stack_checksum", "_boot_halt"),
}
if mode not in name_sets:
    raise SystemExit(f"unknown symbol metadata mode: {mode}")
names = name_sets[mode]
symbols = {}
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    fields = line.split()
    if len(fields) == 3 and fields[2] in names:
        symbols[fields[2]] = int(fields[0], 16)
for name in names:
    if name not in symbols:
        raise SystemExit(f"missing ELF symbol: {name}")
    if symbols[name] % 4 or not 0x1C000000 <= symbols[name] < 0x1C400000:
        raise SystemExit(f"invalid smoke-test address: {name}")
if mode == "boot" and not symbols["__data_start"] < symbols["__data_end"] <= symbols["__bss_start"] < symbols["__bss_end"]:
    raise SystemExit("invalid data/BSS layout")
Path(sys.argv[2]).write_text("".join(f"{symbols[name]:08x}\n" for name in names),
                            encoding="utf-8", newline="\n")
