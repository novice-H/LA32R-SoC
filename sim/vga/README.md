# VGA 验证环境（sim/vga）

一套**与 VGA 模块实现解耦**的验证环境：它负责准备测试数据、驱动时钟、像真实显示器一样
采集 `de/hsync/vsync/RGB`，重建整帧图片，并与"程序编译出的预期图"逐像素比对。

> **默认 DUT 仍是 `dut_placeholder.v`（占位实现）。** 正式帧缓冲核心 `soc/vga_fb.v`
> 已经入仓，配套包装器为 `vga/dut_vga_fb.v`，接法见第 5 节；testbench 无需改动。

---

## 1. 组成

```
ref/vga_pattern.c          # 生成测试图案：fb0.bin + expected.ppm（"程序编译的预期图片"）
sim/
├── Makefile               # 全流程入口
└── vga/
    ├── README.md          # 本文件
    ├── tb_vga_top.v       # 仿真顶层：真实存储链路 + CPU 噪声主机 + DVI 监视
    ├── cpu_noise.v        # 仿真用 CPU 主机：持续读写/校验，制造 ExtRAM 争用
    ├── dut_placeholder.v  # 【占位】最小可用 DUT，跑通环境用
    ├── tb_main.cpp        # Verilator tb：采集、重建 PPM、时序断言
    ├── gen_mem.py         # fb0.bin → fb0.hex（32 位小端字）
    └── compare.py         # 预期 vs 实测：并排图 + 差异图 + 一致率
```

数据流（**走的是真实存储链路，不是理想 RAM 模型**）：

```
ref/vga_pattern.c ──► fb0.bin/fb1.bin ──gen_mem.py──► fb0.hex ──$readmemh──► 异步 SRAM 模型
                                                                                  ▲
                          vga_dut ──DVI──► ext_ram_arbiter ──► ext_ram_ctrl ──────┘
                             ▲                      ▲
                        RGB/同步               cpu_noise（持续制造 CPU 争用）
                             │
                    tb_main.cpp（像显示器一样重建）
                             ▼
              actual0/1.ppm ──compare.py──► side_by_side.png / diff.png
```

即 `sim/mem/async_sram_model.v` + `soc/mem/ext_ram_ctrl.v`（2 拍延迟）
+ `soc/mem/ext_ram_arbiter.v`（DVI 优先仲裁），与上板路径一致。

**关键设计**：testbench 只看 DUT 的输出端口，不读任何内部信号。因此"画面与预期一致"
本身就意味着时序、地址、字节序全对。

---

## 2. DUT 契约（写 VGA 模块时按这个来）

模块名必须是 `vga_dut`（或者你自己写个同名包装模块，见第 5 节）。

| 端口 | 方向 | 位宽 | 说明 |
| --- | --- | --- | --- |
| `clk` | in | 1 | 系统时钟 = 像素时钟 = 50 MHz |
| `rst` | in | 1 | 高有效同步复位 |
| `fb_sel` | in | 1 | 0 = FB0（`0xA000_0000`），1 = FB1（`0xA008_0000`） |
| `ram_addr` | out | 20 | ExtRAM **字**地址 |
| `ram_req` | out | 1 | 读请求，单拍有效 |
| `ram_rdata` | in | 32 | 读数据，经仲裁器 + 控制器后 **2 拍**有效并被保持 |
| `vga_red` | out | 3 | RGB332 红 |
| `vga_green` | out | 3 | RGB332 绿 |
| `vga_blue` | out | 2 | RGB332 蓝 |
| `vga_hsync` | out | 1 | 行同步，正极性 |
| `vga_vsync` | out | 1 | 场同步，正极性 |
| `vga_de` | out | 1 | 有效像素区 |
| `vsync_start` | out | 1 | 进入垂直消隐区的单拍脉冲（`vcnt==600 && hcnt==0`），给 confreg 翻页用 |
| `dvi_next` | out | 1 | 提前一拍预告 `ram_req`，供仲裁器提前挡掉 CPU |

### 2.1 时序规格（与 `thinpad_top.v` 的 `vga #(12,800,856,976,1040,600,637,643,666,1,1)` 一致）

| 参数 | 值 |
| --- | --- |
| 行有效 / 同步起止 / 总长 | 800 / 856–976 / 1040 |
| 场有效 / 同步起止 / 总长 | 600 / 637–643 / 666 |
| 刷新率 | 50e6 / (1040 × 666) = **72.19 Hz** |
| `hsync` 宽度 / 周期 | 120 / 1040 拍 |
| `vsync` 宽度 / 周期 | 6 行 = 6240 拍 / 692640 拍 |

`vga_de` 必须恰好覆盖 800×600 个有效像素，且不能与消隐区重叠。

### 2.2 帧缓冲格式

- 1 字节/像素，`{R[2:0], G[2:0], B[1:0]}`，`PITCH = 800` 字节
- 4 个连续像素打包进 1 个 32 位字，**小端**：像素 `x` 的字节在 `x % 4` 道
- 像素 `(x, y)` 的字偏移 = `(y*800 + x) / 4`（FB 内相对偏移）
- FB1 的字偏移比 FB0 大 `131072`（`0x80000/4`）

### 2.3 读时序约定

仿真与上板一致：`vga_dut → ext_ram_arbiter → ext_ram_ctrl → 异步 SRAM`，控制器是
**2 拍延迟**（发地址 → 访问窗口 → 响应）。因此 DUT 要在像素组第 3 拍
（`hcnt%4==2`）就发出下一组地址，数据正好在下一组开头前到位并被保持。

`dvi_next` 提前一拍给出预警，仲裁器据此把 CPU 请求挡在 DVI 请求前一拍之外，
保证 DVI 零等待；CPU 只能在每 4 拍的窗口里拿到空闲拍。

---

## 3. 运行

```bash
cd sim

make            # 全流程：图案 -> mem -> 仿真 -> 对比
make pattern    # 只生成 build/fb0.bin 与 build/expected.ppm
make lint       # Verilator -Wall 语法/告警检查
make run        # 仿真，输出 build/actual.ppm + 时序报告
make compare    # 只做图片对比
make flip       # 翻页测试：先采 FB0，再在 vsync 翻到 FB1 采第二帧，两帧都比对
make wave       # 导出 6000 拍波形并用 GTKWave 打开
make clean
```

产物都在 `build/`（已被 `.gitignore` 忽略）：

| 文件 | 内容 |
| --- | --- |
| `expected.ppm` | 程序（`ref/vga_pattern.c`）画的预期图 |
| `actual.ppm` | 从 VGA 信号重建的实测图 |
| `side_by_side.png` | 左预期 / 右实测，**肉眼对比用** |
| `diff.png` | 差异放大 4 倍（黑=一致） |
| `vga_timing.txt` | 时序报告 |
| `vga_compare.txt` | 一致率报告 |
| `vga.vcd` | 波形（仅 `make wave`） |

实测（占位 DUT）：时序 4 项 PASS，图片 **480000/480000 像素一致**，仿真耗时约 0.2 秒。

---

## 4. 判定标准

1. `hsync` 宽 120、周期 1040；`vsync` 宽 6240、周期 692640 → 全 PASS
2. 每行 800 个有效像素，共 600 行，无异常行
3. `actual.ppm` 与 `expected.ppm` 逐像素一致（`compare.py` 返回 0）
4. `make flip`：`actual0.ppm` 对 `expected.ppm`、`actual1.ppm` 对 `expected1.ppm`
   都要逐像素一致——这一条专门验证 `fb_sel` 翻页后**整帧**来自新缓冲
5. `vsync_start`：每帧恰好 1 个脉冲、宽 1 拍、周期 692640
6. **DVI 请求零丢弃**：每个 `dvi_req` 都拿到授权；响应严格 2 拍后到达
   （`req_cnt == rsp_cnt`、`stall == 0`、`latency_err == 0`）
7. **CPU 不被饿死**：`cpu_noise` 授权数 > 0，且读写校验 0 错误

> 这套判定是"有效"的：已经用它抓到并修复了两个真实 bug——
> ① 翻页后首字仍来自旧缓冲（差 4 像素）；② 上电瞬间控制器误写内存 0 号字
> （`SIMU` 防误写保护未开启，导致 FB0 左上角变黑）。

---

## 5. 接入你自己的 VGA 模块

仓库当前提供了一个按本契约实现的正式帧缓冲核心：`../soc/vga_fb.v`，以及对应的仿真包装器：`vga/dut_vga_fb.v`。可以直接用下面的命令验证：

```bash
make clean
make lint DUT="vga/dut_vga_fb.v ../soc/vga_fb.v"
make run  DUT="vga/dut_vga_fb.v ../soc/vga_fb.v"
make flip DUT="vga/dut_vga_fb.v ../soc/vga_fb.v"   # 翻页：FB0 -> FB1
```

这个核心实现了 800x600@72.19 Hz 扫描、RGB332 四像素打包、FB0/FB1 选择和 RAM 一拍读延迟。接入整机时，`ram_addr/ram_req/ram_rdata` 需要连接到 CPU/DVI 共用的 ExtRAM 仲裁器。

1. 把正式的 VGA / DVI 模块写在 `soc/` 下（按 `docs/design.md` 2.2.7）
2. 在 `sim/vga/` 新建一个包装文件，例如 `dut_my_vga.v`：

```verilog
`default_nettype none
module vga_dut (
    input  wire        clk, rst, fb_sel,
    output wire [19:0] ram_addr,
    output wire        ram_req,
    input  wire [31:0] ram_rdata,
    output wire [2:0]  vga_red,
    output wire [2:0]  vga_green,
    output wire [1:0]  vga_blue,
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire        vga_de
);
    my_dvi_top u_dut (
        /* 把你的模块端口接过来 */
    );
endmodule
`default_nettype wire
```

3. 运行：

```bash
make clean
make DUT="vga/dut_my_vga.v ../soc/my_dvi_top.v"
```

多个文件用引号包起来即可。testbench、图案生成、比对脚本都不用改。

---

## 6. 已知限制（后续阶段再补）

1. **没有 2 行 FIFO 乒乓预取**：靠"提前一拍请求 + 仲裁器挡 CPU"保证实时性，
   CPU 在每组 4 拍里只能拿到 1 个空闲拍（约 25% 带宽）。若以后 CPU 带宽不够，
   再补 FIFO，接口不用变。
2. **翻页**：测试台直接拨 `fb_sel` 模拟 confreg；`vga_fb` 已能处理翻页（补取新基址
   word0）并输出 `vsync_start`，接 confreg 时把两者对接即可。
3. **CPU 争用已覆盖**：`cpu_noise` 持续读写高地址区，仿真校验其读回正确且不被饿死，
   同时两帧图像必须 100% 一致。
5. **vsync_start 已输出**：`(hcnt==0 && vcnt==600)` 的单拍脉冲，周期与场周期一致，
   仿真里已逐项校验；confreg 接进来后直接用它翻转 `fb_sel`。
6. 图案配色沿用 `docs/design.md` 的 `0x6D / 0xEF / 0x00`。注意：按
   `{R[2:0],G[2:0],B[1:0]}` 位定义，`0xEF` 展开是 (255,109,255) **品红**，
   文档里写的 "R224 G224 B192 米白" 实际对应 `0xFF`——上板前建议统一口径。

---

## 7. 下一步

- Phase 2：把 `vga_dut` 换成正规模块，接 `thinpad_top.v`（需要 PLL/UART/SEG7 的仿真 stub）
- Phase 3：接入 CPU + confreg 的 `fb_sel`/`vsync_start`，验证双缓冲翻页
- 可选：动画测试（连续多帧 + 翻页），把 `tb_main.cpp` 扩成多帧采集与逐帧比对
