# Verilator 最小仿真模板
#   make        -> 编译并运行仿真
#   make lint   -> 只做语法/告警检查
#   make trace  -> 带波形编译并运行，生成 counter.vcd
#   make wave   -> 用 GTKWave 打开波形
#   make clean
VERILATOR ?= verilator
TOP       := counter
SRCS      := counter.sv tb_main.cpp
VFLAGS    := --cc --exe --build -j 0 --top-module $(TOP) -O2 -Wno-fatal
OUT       := sim
OBJ       := obj_dir

all: run

$(OUT): $(SRCS)
	$(VERILATOR) $(VFLAGS) $(SRCS) -o $(OUT) --Mdir $(OBJ)

run: $(OUT)
	./$(OBJ)/$(OUT)

lint:
	$(VERILATOR) --lint-only -Wall $(TOP).sv

trace: $(SRCS)
	$(VERILATOR) $(VFLAGS) --trace $(SRCS) -o $(OUT) --Mdir $(OBJ)
	./$(OBJ)/$(OUT)

wave: counter.vcd
	gtkwave counter.vcd &

clean:
	rm -rf $(OBJ) counter.vcd

.PHONY: all run lint trace wave clean
