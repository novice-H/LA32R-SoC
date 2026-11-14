# ---------------------------------------------------------------------------
# sim/soc/Makefile —— 全系统仿真（CPU + AXI 桥 + 总线 + 存储器 + confreg + VGA）
#
#   make        # 编译裸机程序并跑完整仿真
#   make prog   # 只编译启动程序（生成 build/soc/prog.hex）
#   make lint   # Verilator -Wall
#   make clean
# ---------------------------------------------------------------------------
ROOT  := $(abspath ../..)
HERE  := $(abspath .)
BUILD := $(ROOT)/build/soc
CPU   := $(ROOT)/soc/cpu/open-la500

TOOLCHAIN := $(ROOT)/requirements/loongarch32r-linux-gnusf-2022-05-20
CROSS     := $(TOOLCHAIN)/bin/loongarch32r-linux-gnusf-
ifeq ($(wildcard $(CROSS)gcc),)
  CROSS := loongarch32r-linux-gnusf-
endif

VERILATOR ?= verilator
PYTHON    ?= python3
PROGRAM_HEX ?=
SMOKE_SYMBOLS ?=
INPUT_SYMBOLS ?=
FRAMEBUFFER_SYMBOLS ?=
FRAMEBUFFER_GOLDEN ?=
GAME_SYMBOLS ?=
GAME_GOLDEN ?=
RUN_ARGS ?=

RTL := $(ROOT)/soc/thinpad_top.v $(ROOT)/soc/soc_top.v \
       $(ROOT)/soc/bus/soc_bus.v $(ROOT)/soc/bus/axi_slave_ref.v \
       $(ROOT)/soc/mem/sram_ctrl.v $(ROOT)/soc/mem/base_ram_ctrl.v \
       $(ROOT)/soc/mem/ext_ram_ctrl.v $(ROOT)/soc/mem/ext_ram_arbiter.v \
       $(ROOT)/soc/confreg.v $(ROOT)/soc/vga_fb.v \
       $(ROOT)/sim/mem/async_sram_model.v \
       $(wildcard $(CPU)/*.v)

VFLAGS := --binary --timing -DSIMU -Wno-fatal -Wno-DECLFILENAME \
          +incdir+$(CPU) +incdir+$(HERE) --top-module tb_soc_top -O2

all: run

# ---------------------------------------------------------------- 启动程序
$(BUILD)/start.elf: prog/start.S prog/link.ld
	mkdir -p $(BUILD)
	$(CROSS)gcc -nostdlib -nostartfiles -T prog/link.ld prog/start.S -o $@

$(BUILD)/start.bin: $(BUILD)/start.elf
	$(CROSS)objcopy -O binary $< $@

ifeq ($(strip $(PROGRAM_HEX)),)
.PHONY: default-program
default-program:
$(BUILD)/prog.hex: $(BUILD)/start.bin bin2hex.py default-program
	$(PYTHON) bin2hex.py $< $@
else
# Recopy when switching images even if their timestamps are older.
.PHONY: external-program
external-program:
$(BUILD)/prog.hex: $(PROGRAM_HEX) external-program
	mkdir -p "$(BUILD)"
	cp "$<" "$@"
endif

prog: $(BUILD)/prog.hex

boot-config:
ifneq ($(strip $(GAME_SYMBOLS)),)
	mkdir -p "$(BUILD)"
	$(PYTHON) boot_symbols.py "$(GAME_SYMBOLS)" "$(BUILD)/game-symbols.hex" game
ifneq ($(strip $(GAME_GOLDEN)),)
	cp "$(GAME_GOLDEN)/game-expected.hex" "$(BUILD)/game-expected.hex"
	cp "$(GAME_GOLDEN)/game-frame.hex" "$(BUILD)/game-frame.hex"
endif
endif
ifneq ($(strip $(SMOKE_SYMBOLS)),)
	mkdir -p "$(BUILD)"
	$(PYTHON) boot_symbols.py "$(SMOKE_SYMBOLS)" "$(BUILD)/boot-symbols.hex"
endif
ifneq ($(strip $(INPUT_SYMBOLS)),)
	mkdir -p "$(BUILD)"
	$(PYTHON) boot_symbols.py "$(INPUT_SYMBOLS)" "$(BUILD)/input-symbols.hex" input
endif
ifneq ($(strip $(FRAMEBUFFER_SYMBOLS)),)
	mkdir -p "$(BUILD)"
	$(PYTHON) boot_symbols.py "$(FRAMEBUFFER_SYMBOLS)" "$(BUILD)/framebuffer-symbols.hex" framebuffer
	cp "$(FRAMEBUFFER_GOLDEN)/expected0.hex" "$(BUILD)/expected0.hex"
	cp "$(FRAMEBUFFER_GOLDEN)/expected1.hex" "$(BUILD)/expected1.hex"
endif

# ---------------------------------------------------------------- 仿真
lint: prog
	$(VERILATOR) --lint-only -Wall --timing -DSIMU -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
    -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-EOFNEWLINE -Wno-PINCONNECTEMPTY -Wno-UNUSEDPARAM -Wno-UNDRIVEN -Wno-BLKSEQ -Wno-UNUSEDSIGNAL +incdir+$(CPU) +incdir+$(HERE) --top-module tb_soc_top \
	    $(HERE)/tb_soc_top.sv $(RTL)

sim: prog boot-config
	mkdir -p $(BUILD)/obj
	$(VERILATOR) $(VFLAGS) $(HERE)/tb_soc_top.sv $(RTL) --Mdir $(BUILD)/obj -o Vtb

run: sim
	cd $(BUILD) && ./obj/Vtb $(RUN_ARGS) | tee log.txt
	@grep -q "RESULT: PASS" $(BUILD)/log.txt && echo "SOC_SIM: PASS" || (echo "SOC_SIM: FAIL"; exit 1)

wave: prog boot-config
	mkdir -p $(BUILD)/obj_wave
	$(VERILATOR) $(VFLAGS) --trace $(HERE)/tb_soc_top.sv $(RTL) \
	    --Mdir $(BUILD)/obj_wave -o VtbWave
	cd $(BUILD) && ./obj_wave/VtbWave +wave +short $(RUN_ARGS)
	@ls -lh $(BUILD)/soc.vcd

clean:
	rm -rf $(BUILD)

.PHONY: all prog lint sim run wave clean boot-config
