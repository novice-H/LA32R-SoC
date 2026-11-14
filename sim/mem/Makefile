# ---------------------------------------------------------------------------
# sim/mem/Makefile —— SRAM 控制器（soc/mem）自检
#
#   make        # 编译并运行
#   make lint   # 只做语法/告警检查
#   make clean
# ---------------------------------------------------------------------------
ROOT  := $(abspath ../..)
MEM   := $(ROOT)/soc/mem
HERE  := $(abspath .)
BUILD := $(ROOT)/build/mem

VERILATOR ?= verilator

SRCS := $(HERE)/tb_sram_ctrl.sv $(HERE)/async_sram_model.v \
        $(MEM)/sram_ctrl.v $(MEM)/base_ram_ctrl.v $(MEM)/ext_ram_ctrl.v

VFLAGS := --binary --timing -DSIMU -Wno-fatal --top-module tb_sram_ctrl -O2

ARB_SRCS := $(HERE)/tb_arbiter.sv $(MEM)/sram_ctrl.v $(MEM)/base_ram_ctrl.v \
            $(MEM)/ext_ram_ctrl.v $(MEM)/ext_ram_arbiter.v $(HERE)/async_sram_model.v

all: run arb

lint:
	$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME -Wno-BLKSEQ --timing -DSIMU --top-module tb_sram_ctrl $(SRCS)

sim:
	mkdir -p $(BUILD)/obj
	$(VERILATOR) $(VFLAGS) $(SRCS) --Mdir $(BUILD)/obj -o Vtb

run: sim
	$(BUILD)/obj/Vtb | tee $(BUILD)/log.txt
	@grep -q "RESULT: PASS" $(BUILD)/log.txt && echo "MEM_SIM: PASS" || (echo "MEM_SIM: FAIL"; exit 1)

arb:
	mkdir -p $(BUILD)/obj_arb
	$(VERILATOR) --binary --timing -DSIMU -Wno-fatal --top-module tb_arbiter -O2 \
	    $(ARB_SRCS) --Mdir $(BUILD)/obj_arb -o VtbArb
	$(BUILD)/obj_arb/VtbArb | tee $(BUILD)/arb.log
	@grep -q "RESULT: PASS" $(BUILD)/arb.log && echo "ARB_SIM: PASS" || (echo "ARB_SIM: FAIL"; exit 1)

clean:
	rm -rf $(BUILD)

.PHONY: all lint sim run arb clean
