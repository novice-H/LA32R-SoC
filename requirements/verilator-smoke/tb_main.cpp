#include "Vcounter.h"
#include "verilated.h"
#include <cstdio>
#if VM_TRACE
# include "verilated_vcd_c.h"
#endif

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vcounter* dut = new Vcounter;

#if VM_TRACE
  Verilated::traceEverOn(true);
  VerilatedVcdC* tfp = new VerilatedVcdC;
  dut->trace(tfp, 99);
  tfp->open("counter.vcd");
#endif
  vluint64_t t = 0;
  bool trace = false;
#if VM_TRACE
  trace = true;
#endif

  auto tick = [&]() {                      // 一个时钟周期：上升沿 -> 下降沿
    dut->clk = 1; dut->eval();
#if VM_TRACE
    if (trace) tfp->dump(t += 5);
#endif
    dut->clk = 0; dut->eval();
#if VM_TRACE
    if (trace) tfp->dump(t += 5);
#endif
  };

  // 复位：拉低 rst_n 一个周期
  dut->rst_n = 0; dut->en = 1; dut->clk = 0;
  dut->eval();
  tick();
  dut->rst_n = 1;

  for (int i = 0; i < 10; i++) tick();

  printf("after 10 enabled cycles, q = %d (expect 10)\n", (int)dut->q);
  int ok = (dut->q == 10);

#if VM_TRACE
  tfp->close();
  delete tfp;
#endif
  dut->final();
  delete dut;
  return ok ? 0 : 1;
}
