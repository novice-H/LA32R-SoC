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

RTL := $(ROOT)/soc/thinpad_top.v $(ROOT)/soc/soc_top.v \
       $(ROOT)/soc/bus/soc_bus.v $(ROOT)/soc/bus/axi_slave_ref.v \
       $(ROOT)/soc/mem/sram_ctrl.v $(ROOT)/soc/mem/base_ram_ctrl.v \
       $(ROOT)/soc/mem/ext_ram_ctrl.v $(ROOT)/soc/mem/ext_ram_arbiter.v \
       $(ROOT)/soc/confreg.v $(ROOT)/soc/vga_fb.v \
       $(ROOT)/sim/mem/async_sram_model.v \
       $(wildcard $(CPU)/*.v)

VFLAGS := --binary --timing -DSIMU -Wno-fatal -Wno-DECLFILENAME \
          +incdir+$(CPU) --top-module tb_soc_top -O2

all: run

# ---------------------------------------------------------------- 启动程序
$(BUILD)/start.elf: prog/start.S prog/link.ld
	mkdir -p $(BUILD)
	$(CROSS)gcc -nostdlib -nostartfiles -T prog/link.ld prog/start.S -o $@

$(BUILD)/start.bin: $(BUILD)/start.elf
	$(CROSS)objcopy -O binary $< $@

$(BUILD)/prog.hex: $(BUILD)/start.bin bin2hex.py
	$(PYTHON) bin2hex.py $< $@

prog: $(BUILD)/prog.hex

# ---------------------------------------------------------------- 仿真
lint: prog
	$(VERILATOR) --lint-only -Wall --timing -DSIMU -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
	    -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-EOFNEWLINE -Wno-PINCONNECTEMPTY -Wno-UNUSEDPARAM -Wno-UNDRIVEN -Wno-BLKSEQ -Wno-UNUSEDSIGNAL +incdir+$(CPU) --top-module tb_soc_top \
	    $(HERE)/tb_soc_top.sv $(RTL)

sim: prog
	mkdir -p $(BUILD)/obj
	$(VERILATOR) $(VFLAGS) $(HERE)/tb_soc_top.sv $(RTL) --Mdir $(BUILD)/obj -o Vtb

run: sim
	cd $(BUILD) && ./obj/Vtb | tee log.txt
	@grep -q "RESULT: PASS" $(BUILD)/log.txt && echo "SOC_SIM: PASS" || (echo "SOC_SIM: FAIL"; exit 1)

wave: prog
	mkdir -p $(BUILD)/obj_wave
	$(VERILATOR) $(VFLAGS) --trace $(HERE)/tb_soc_top.sv $(RTL) \
	    --Mdir $(BUILD)/obj_wave -o VtbWave
	cd $(BUILD) && ./obj_wave/VtbWave +wave +short
	@ls -lh $(BUILD)/soc.vcd

clean:
	rm -rf $(BUILD)

.PHONY: all prog lint sim run wave clean
