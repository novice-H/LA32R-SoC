# ---------------------------------------------------------------------------
# sim/Makefile —— VGA 验证环境
#
#   make            # 全流程：生成图案 -> 转 mem -> 仿真 -> 对比（出并排图）
#   make pattern    # 只生成测试图案（fb0.bin / expected.ppm）
#   make mem        # 只把 fb0.bin 转成 fb0.hex
#   make lint       # 只做 Verilator 语法/告警检查
#   make sim        # 编译 Verilator 模型
#   make run        # 跑仿真，输出 actual.ppm 与时序报告
#   make compare    # 对比 expected.ppm 与 actual.ppm
#   make wave       # 导出 6000 拍波形并用 GTKWave 打开
#   make clean
#
# 换待测模块：
#   make DUT=vga/dut_my_vga.v            # 单个文件
#   make DUT="vga/dut_my_vga.v ../soc/dvi_top.v"   # 多个文件
# ---------------------------------------------------------------------------
# 注意：Verilator 生成的子 make 在 --Mdir 目录里运行，相对路径会失效，
#       所以这里统一转成绝对路径。
ROOT      := $(abspath ..)
SIM       := $(abspath .)
BUILD     := $(ROOT)/build
VGA       := $(SIM)/vga
OBJ       := $(BUILD)/obj_vga
BIN       := $(OBJ)/Vtb_vga_top
OBJ_TRACE := $(BUILD)/obj_vga_trace
BIN_TRACE := $(OBJ_TRACE)/Vtb_vga_top

VERILATOR ?= verilator
CC        ?= cc

# 待测模块：默认用占位实现；换成自己的 VGA 模块时覆盖此变量
DUT ?= $(VGA)/dut_placeholder.v

VFLAGS := --cc --exe --build -j 0 --top-module tb_vga_top -O2 -Wno-fatal
RTL    := $(VGA)/tb_vga_top.v $(VGA)/ram_model.v $(DUT)
CSRC   := $(VGA)/tb_main.cpp

all: compare

$(BUILD):
	mkdir -p $(BUILD)

# ---------------------------------------------------------------- 测试图案
$(BUILD)/vga_pattern: $(ROOT)/ref/vga_pattern.c | $(BUILD)
	$(CC) -O2 -Wall -Wextra -o $@ $<

pattern: $(BUILD)/vga_pattern
	cd $(BUILD) && ./vga_pattern

# ---------------------------------------------------------------- 转 mem
$(BUILD)/fb0.hex: pattern
	python3 $(VGA)/gen_mem.py $(BUILD)/fb0.bin $(BUILD)/fb0.hex

mem: $(BUILD)/fb0.hex

# ---------------------------------------------------------------- 检查
lint: mem
	# -Wno-DECLFILENAME：DUT 包装文件与模块名 vga_dut 不同是契约要求
	$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME --top-module tb_vga_top \
	    $(VGA)/tb_vga_top.v $(VGA)/ram_model.v $(DUT)

# ---------------------------------------------------------------- 编译仿真
sim: mem
	$(VERILATOR) $(VFLAGS) $(RTL) $(CSRC) -o Vtb_vga_top --Mdir $(OBJ)

# ---------------------------------------------------------------- 运行
run: sim
	cd $(BUILD) && $(BIN) | tee vga_timing.txt

# ---------------------------------------------------------------- 对比
compare: run
	python3 $(VGA)/compare.py $(BUILD)/expected.ppm $(BUILD)/actual.ppm $(BUILD) | tee $(BUILD)/vga_compare.txt

# ---------------------------------------------------------------- 波形
wave: mem
	$(VERILATOR) $(VFLAGS) --trace $(RTL) $(CSRC) -o Vtb_vga_top --Mdir $(OBJ_TRACE)
	cd $(BUILD) && $(BIN_TRACE) +trace-cycles=6000
	gtkwave $(BUILD)/vga.vcd &

clean:
	rm -rf $(OBJ) $(OBJ_TRACE)
	rm -f $(BUILD)/vga_pattern $(BUILD)/fb0.bin $(BUILD)/fb0.hex \
	      $(BUILD)/expected.ppm $(BUILD)/actual.ppm \
	      $(BUILD)/side_by_side.png $(BUILD)/diff.png \
	      $(BUILD)/vga.vcd $(BUILD)/vga_timing.txt $(BUILD)/vga_compare.txt

.PHONY: all pattern mem lint sim run compare wave clean
