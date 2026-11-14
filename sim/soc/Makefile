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


# ---------------------------------------------------------------- 冒烟程序 v2
$(BUILD)/start_v2.elf: prog/start_v2.S prog/link.ld
	mkdir -p $(BUILD)
	$(CROSS)gcc -nostdlib -nostartfiles -T prog/link.ld prog/start_v2.S -o $@

$(BUILD)/start_v2.bin: $(BUILD)/start_v2.elf
	$(CROSS)objcopy -O binary $< $@

$(BUILD)/prog_v2.hex: $(BUILD)/start_v2.bin bin2hex.py
	$(PYTHON) bin2hex.py $< $@

prog2: $(BUILD)/prog_v2.hex

sim-v2: prog2
	mkdir -p $(BUILD)/obj_v2
	$(VERILATOR) $(VFLAGS) -DTB_V2 $(HERE)/tb_soc_top.sv $(RTL) \
	    --Mdir $(BUILD)/obj_v2 -o VtbV2

run-v2: sim-v2
	cd $(BUILD) && ./obj_v2/VtbV2 | tee log_v2.txt
	@grep -q "RESULT: PASS" $(BUILD)/log_v2.txt && echo "SOC_SIM_V2: PASS" || (echo "SOC_SIM_V2: FAIL"; exit 1)

# ---------------------------------------------------------------- AI 单步基准
AI_OBJS := $(BUILD)/ai_crt0.o $(BUILD)/ai_core.o $(BUILD)/ai_bench.o $(BUILD)/ai_mem.o $(BUILD)/ai_cache.o
AI_CXXFLAGS := -std=c++11 -O2 -march=loongarch32r -mabi=ilp32s -ffreestanding \
               -fno-exceptions -fno-rtti -fno-builtin -fno-pic -fno-pie \
               -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables \
               -Wall -Wextra

$(BUILD)/ai_crt0.o: $(ROOT)/sw/boot/crt0.S
	mkdir -p $(BUILD)
	$(CROSS)gcc -march=loongarch32r -mabi=ilp32s -fno-pic -fno-pie -c $< -o $@

$(BUILD)/ai_core.o: $(ROOT)/sw/app/ai.cpp $(ROOT)/sw/app/ai.h
	$(CROSS)g++ $(AI_CXXFLAGS) -c $< -o $@

$(BUILD)/ai_bench.o: $(ROOT)/sw/tests/ai_bench_la32r.cpp $(ROOT)/sw/app/ai.h
	$(CROSS)g++ $(AI_CXXFLAGS) -c $< -o $@

$(BUILD)/ai_mem.o: $(ROOT)/sw/libc/memory.cpp
	$(CROSS)g++ $(AI_CXXFLAGS) -c $< -o $@

$(BUILD)/ai_cache.o: $(ROOT)/sw/boot/cache_enable.S
	$(CROSS)gcc -march=loongarch32r -mabi=ilp32s -fno-pic -fno-pie -c $< -o $@

$(BUILD)/ai.elf: $(AI_OBJS) $(ROOT)/sw/boot/link.ld
	$(CROSS)g++ -march=loongarch32r -mabi=ilp32s -static -no-pie -nostdlib -nostartfiles \
	    -Wl,--build-id=none -T $(ROOT)/sw/boot/link.ld $(AI_OBJS) -lgcc -o $@

$(BUILD)/ai.bin: $(BUILD)/ai.elf
	$(CROSS)objcopy -O binary $< $@

$(BUILD)/ai.hex: $(BUILD)/ai.bin bin2hex.py
	$(PYTHON) bin2hex.py $< $@

prog-ai: $(BUILD)/ai.hex

sim-ai: prog-ai
	mkdir -p $(BUILD)/obj_ai
	$(VERILATOR) $(VFLAGS) -DTB_AI $(HERE)/tb_soc_top.sv $(RTL) \
	    --Mdir $(BUILD)/obj_ai -o VtbAi

run-ai: sim-ai
	cd $(BUILD) && ./obj_ai/VtbAi | tee log_ai.txt
	@grep -q "RESULT: PASS" $(BUILD)/log_ai.txt && echo "SOC_AI_SIM: PASS" || (echo "SOC_AI_SIM: FAIL"; exit 1)

clean:
	rm -rf $(BUILD)

.PHONY: all prog prog2 lint sim run sim-v2 run-v2 wave prog-ai sim-ai run-ai clean boot-config
