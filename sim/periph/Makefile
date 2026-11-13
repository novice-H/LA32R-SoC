# ---------------------------------------------------------------------------
# sim/periph/Makefile —— confreg 自检
#
#   make        # 编译并运行
#   make lint   # Verilator -Wall 检查（寄存器只用到部分位，屏蔽 UNUSEDSIGNAL）
#   make clean
# ---------------------------------------------------------------------------
ROOT  := $(abspath ../..)
HERE  := $(abspath .)
BUILD := $(ROOT)/build/periph

VERILATOR ?= verilator
SRCS := $(HERE)/tb_confreg.sv $(ROOT)/soc/confreg.v
VFLAGS := --binary --timing -DSIMU -Wno-fatal --top-module tb_confreg -O2

all: run

lint:
	$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-UNUSEDSIGNAL --timing -DSIMU \
	    --top-module tb_confreg $(SRCS)

sim:
	mkdir -p $(BUILD)/obj
	$(VERILATOR) $(VFLAGS) $(SRCS) --Mdir $(BUILD)/obj -o Vtb

run: sim
	$(BUILD)/obj/Vtb | tee $(BUILD)/log.txt
	@grep -q "RESULT: PASS" $(BUILD)/log.txt && echo "CONFREG_SIM: PASS" || (echo "CONFREG_SIM: FAIL"; exit 1)

clean:
	rm -rf $(BUILD)

.PHONY: all lint sim run clean
