# Verilator 最小仿真模板
#   make        -> 编译并运行仿真
#   make lint   -> 只做语法/告警检查
#   make trace  -> 带波形编译并运行，生成 counter.vcd
#   make wave   -> 用 GTKWave 打开波形
#   make clean
VERILATOR ?= verilator
TOP       := counter
SRCS      := $(abspath counter.sv tb_main.cpp)
VFLAGS    := --cc --exe --build -j 0 --top-module $(TOP) -O2 -Wno-fatal
ifeq ($(strip $(LA32R_BUILD)),)
OBJ       ?= obj_dir
TRACE_OBJ ?= obj_dir_trace
RUN_DIR   := $(CURDIR)
TRACE_RUN_DIR := $(CURDIR)
else
SMOKE_BUILD := $(abspath $(LA32R_BUILD)/smoke)
OBJ       ?= $(SMOKE_BUILD)/obj_normal
TRACE_OBJ ?= $(SMOKE_BUILD)/obj_trace
RUN_DIR   := $(SMOKE_BUILD)/run
TRACE_RUN_DIR := $(SMOKE_BUILD)/trace
endif
BIN       := $(abspath $(OBJ))/sim
TRACE_BIN := $(abspath $(TRACE_OBJ))/sim

all: run

$(BIN): $(SRCS)
	mkdir -p $(OBJ) $(RUN_DIR)
	$(VERILATOR) $(VFLAGS) $(SRCS) -o sim --Mdir $(OBJ)

run: $(BIN)
	cd $(RUN_DIR) && $(BIN)

lint:
	$(VERILATOR) --lint-only -Wall $(TOP).sv

$(TRACE_BIN): $(SRCS)
	mkdir -p $(TRACE_OBJ) $(TRACE_RUN_DIR)
	$(VERILATOR) $(VFLAGS) --trace $(SRCS) -o sim --Mdir $(TRACE_OBJ)

trace: $(TRACE_BIN)
	cd $(TRACE_RUN_DIR) && $(TRACE_BIN)

wave: trace
	gtkwave $(TRACE_RUN_DIR)/counter.vcd &

clean:
	rm -rf $(OBJ) $(TRACE_OBJ)
	rm -f $(RUN_DIR)/counter.vcd $(TRACE_RUN_DIR)/counter.vcd

.PHONY: all run lint trace wave clean
