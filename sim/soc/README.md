# 全系统仿真（sim/soc）

CPU + AXI 桥 + 总线译码 + 两片 SRAM + confreg + VGA 的整机仿真。

当前硬件资源及接口见 [soc/README.md](../../soc/README.md)。板级 `thinpad_top` 已封装 `soc_top`，整机使用 `soc/bus/axi_slave_ref.v` 中的 `axi_slave_wrap`。

在仓库根目录执行（bash，产物放 WSL ext4）：

```bash
source requirements/env.sh
soc_build="${LA32R_BUILD:-$HOME/build/la32r}/soc"
make -C sim/soc BUILD="$soc_build" CROSS="${CROSS}"        # 完整测试
make -C sim/soc BUILD="$soc_build" CROSS="${CROSS}" prog   # 只生成 prog.hex
make -C sim/soc BUILD="$soc_build" CROSS="${CROSS}" lint   # 独立 lint
make -C sim/soc BUILD="$soc_build" CROSS="${CROSS}" wave   # 短运行波形
```

Makefile 的 `BUILD` 默认仍指向仓库 `build/soc`，上面显式覆盖。`CROSS` 显式使用 env.sh 选中的工具链，避开 Makefile 中旧版工具链路径优先选择。

波形用 `gtkwave "$soc_build/soc.vcd"` 打开：可看 CPU 的 AXI 读写握手、总线 2 拍应答、
两片 SRAM 的 CE/OE/WE、VGA 的 de/hsync/vsync 与 RGB。

运行耗时取决于主机；成功判定同时查看 `RESULT: PASS` 与 `SOC_SIM: PASS`。`wave` 使用 `+short` 提前结束，验收整帧需运行默认完整目标。

## 结构

```
core_top (openLA500, AXI3)
    │
    ▼
soc/bus/axi_slave_ref.v    ← 当前参考桥，模块名 axi_slave_wrap
    │  单拍 req/rsp
    ▼
soc/bus/soc_bus.v          ← 地址译码 + 固定 2 拍应答
    ├── base_ram_ctrl  → BaseRAM 引脚
    ├── ext_ram_arbiter → ext_ram_ctrl → ExtRAM 引脚
    └── confreg        → LED / 数码管 / 按键 / FB_CTRL
vga_fb ──DVI──► ext_ram_arbiter（DVI 优先，CPU 每 4 像素最多 1 拍）
```

顶层层级：

```
soc/thinpad_top.v   板级顶层：完整 thinpad 引脚，未用外设（串口/Flash/备用时钟）安全关闭
  └── soc/soc_top.v  SoC 核心：CPU + 桥 + 总线 + 存储器 + VGA + confreg
sim/soc/tb_soc_top.sv 直接例化 thinpad_top，RAM 模型接 board 引脚
```

## 地址映射

| 区域 | 地址 | 说明 |
| --- | --- | --- |
| BaseRAM | `0x1C00_0000`–`0x1C3F_FFFF` | openLA500 复位 PC 即此段（DA=1 直接地址） |
| BaseRAM 别名 | `0x8000_0000`–`0x803F_FFFF` | 兼容 `docs/design.md` 的 LA32R 窗口 |
| ExtRAM | `0x1C40_0000`–`0x1C7F_FFFF` | 帧缓冲 FB0 在 `0x1C40_0000` |
| ExtRAM 别名 | `0xA000_0000`–`0xA03F_FFFF` | 同上 |
| confreg | `0xBFD0_0000`–`0xBFD0_00FF` | |

当前自检程序链接到 CPU 复位入口 `0x1C00_0000`。兼容别名命中同一 SRAM；若改变入口需同时安排复位取指或跳转。cache 属性由 CPU CSR/DMW/TLB 等控制，软件应明确配置 MMIO 和帧缓冲的存储属性。

## AXI 桥接口契约（队友的正式桥按这个接）

模块名 `axi_slave_wrap`，文件 `soc/bus/axi_slave_ref.v` 是参考实现：

| 侧 | 信号 |
| --- | --- |
| AXI3 从设备 | `arid/araddr/arlen/arsize/arburst/arvalid/arready`、`rid/rdata/rresp/rlast/rvalid/rready`、`awid/awaddr/awlen/awsize/awburst/awvalid/awready`、`wid/wdata/wstrb/wlast/wvalid/wready`、`bid/bresp/bvalid/bready` |
| 简单总线主设备 | `m_addr[31:0]`（字节地址）、`m_req_valid/m_req_ready`、`m_we/m_be_n/m_wdata`、`m_rsp_valid/m_rsp_rdata` |

约定：

1. 简单总线在请求被接受后固定 2 拍应答，AXI 桥仍负责请求握手、等待响应及 AXI 协议状态；
2. `m_addr` 是字节地址，`soc_bus` 负责译码与字地址转换；
3. 当前 CPU 只发 32 位访问（`arsize=2`），参考桥未处理窄传输；
4. 读数据按拍返回、`rlast` 标最后一拍；写响应在最后一个 W 拍之后给一次 B。

后续若更换该 AXI 从桥，需要保持此接口或同步修改 `soc_top` 与构建源清单，再运行同一整机回归。仓库中的 `soc/sram_axi_bridge.v` 提供类 SRAM → AXI 主口接口，独立测试由 `sim/Makefile` 的 `bridge-test` 执行；该模块当前未在 `soc_top` 中例化。

## 启动程序

### CPU RGB332 与双缓冲显示测试

在仓库根目录执行：

```bash
source requirements/env.sh
make -C sw framebuffer-soc-test
```

该目标先运行独立主机像素/字模测试并生成 `expected0/1.hex`，再编译 `framebuffer_soc.cpp` 和实际驱动，传入 `+framebuffer-test`。测试由 [framebuffer_scenarios.svh](framebuffer_scenarios.svh) 驱动，CPU 分别在 FB1/FB0 清屏、画边框、数字和裁剪图元；每次提交完成后采集完整帧，各比对 480000 个像素，并导出 `actual0/1.hex`。

正常显示后，再在有效扫描中用零等待期限测试 present/begin 超时，等待硬件实际完成并恢复提交。最终 22 项固件检查通过，4 次请求对应 4 次 VSYNC 切换，244629 次 CPU 显存写入全部位于当前后台且为整字使能，三个缓冲边界哨兵保持不变。结果标记 `0x600DFB00`，main 返回 `_boot_halt`。

`FRAMEBUFFER_SYMBOLS` 提供固件符号表，`FRAMEBUFFER_GOLDEN` 指向两幅 golden 文件目录。`framebuffer_compare.py` 再核对 960000 像素并输出实际采样 PNG 与 `comparison.json`（依赖 Pillow，已列入项目环境要求）。完整产物见本地 [显示测试交付](../../outputs/framebuffer-20261114-v1/README.md)。输入与原启动测试仍可通过各自目标运行。

本轮借鉴参考提交 `2103134` 的 `start_v2.S`，保持当前 RTL。用户报告参考版本已实板验证 VGA；本版 C++ 驱动使用本轮 CPU 仿真与完整图像核验，实机验证记录单独补充。

### CPU 按键输入整机测试

在仓库根目录执行（WSL bash）：

```bash
source requirements/env.sh
make -C sw input-soc-test
```

构建源为 `sw/tests/input_soc.cpp`、`sw/drv/input.cpp` 和已验证的启动层。测试台使用 `+input-test` 进入 [input_scenarios.svh](input_scenarios.svh)，驱动板级按键和拨码引脚；CPU 通过完整 AXI/总线/confreg 链路读取 BTN/KEY。固件写 STEP 发起/完成阶段，测试台在事件稳定后设置 KEY 允许 CPU 检查，随后释放引脚并清 KEY。

| 阶段 | 输入与验证 |
| --- | --- |
| 1 | 上键持续按下，CPU 首次取得事件，之后重复轮询返回 None |
| 2～4 | 左、下、右单键，各报告一次后读清 |
| 5 | 四键同时按下，CPU 读到原始 `0xF`，读清后软件仍依次返回其余方向 |
| 6 | 上、下脉冲先后累积，CPU 读到 `0x5` 并分别消费 |
| 7～8 | 同方向两次未读事件合并为一位；释放后再按产生新事件 |
| 9～10 | clear 分别清除软件剩余位和硬件未读事件 |
| 11～12 | 拨码高位均为 1，KEY 低两位分别为 1/2，CPU 正确读取电平 |

实际结果：12 阶段、49 项固件检查通过，`input_test_result=0x600D1A00`、main 返回 `_boot_halt`，LED/数码管检查通过。测试台另外逐阶段核对 CPU 对 BTN 的读取次数、非零响应数量和原始位值。结果为 `RESULT: PASS (CPU input test)` / `SOC_SIM: PASS`；本用例集中验证输入，原汇编/C++ 启动模式保留完整帧检查。

产物默认在 `${LA32R_BUILD:-$HOME/build/la32r}/sw/input-soc/`，包括 ELF、BIN、HEX、map、符号、反汇编；日志在 `soc/log.txt`。`INPUT_SYMBOLS` 指向固件符号表，`boot_symbols.py ... input` 生成结果、检查计数和停机地址的元数据。归档见本地 [input-soc-20261114-v1](../../outputs/input-soc-20261114-v1/README.md)。

按键边沿经同步稳定后 CPU 才读取；当前 RTL 的读清/新边沿同拍清零行为记录于 [SoC README](../../soc/README.md)，该组合待硬件专项处理。测试中持续高电平覆盖多次 CPU 读取，机械触点抖动和实际按键时长在板上另行验收。

### C++ 裸机启动自检（2026-11-14）

在仓库根目录执行：

```bash
source requirements/env.sh
make -C sw board-smoke-test
make -C sw board-smoke-wave
```

该目标构建 `sw/boot/crt0.S`、`sw/boot/link.ld` 与 `sw/tests/board_smoke.cpp`，将生成的 HEX 通过 `PROGRAM_HEX` 接入本测试。`SMOKE_SYMBOLS` 指向 `nm -n` 符号表，`boot_symbols.py` 提取 data/BSS/结果/停机符号；`RUN_ARGS=+cpp-smoke` 启用初始化污染及 C++ 专项断言。原默认汇编入口保持可用。

`board-smoke-wave` 输出到软件构建目录的 `board-smoke/soc/soc.vcd`，记录程序完成后 100 拍即结束。`boot_wave.tcl` 是 GTKWave 启动视图脚本，通过 `gtkwave <VCD路径> -S /mnt/f/CursorProject/LA32R-SoC/sim/soc/boot_wave.tcl` 加载。`wave` 目标会传递 `RUN_ARGS`，因此这里仍执行 C++ 专项断言。

测试台先将 data 运行区及 BSS 写为 `DEADBEEF`，然后复位启动，检查初始化全局值、BSS 清零、真实函数栈校验、返回 `_boot_halt`、LED/数码管和视频帧。实测 7600 拍完成，结果标记 `600D2048`、栈校验 `AA`，所有断言通过。原汇编自检回归也通过（8132 拍）。详见 [sw/README.md](../../sw/README.md)。

### 原汇编自检

`prog/start.S`：链接在 `0x1C00_0000`，无栈、无 TLB：

1. `STEP = 1234` → LED[4:0]=12、数码管 34
2. FB0 第 0 行填 `0xEFEFEFEF`（品红）
3. FB0 第 200 字填 `0xE0E0E0E0`（红）
4. `STATUS[13] = 1`（WIN 标志，仿真据此判定程序跑完）

### 工具链与验证范围

当前团队分发 LA32 v2.0（2023-09-03 / GCC 8.3.0），通过 `source requirements/env.sh` 加载。现有自检使用显式 `bne $r8, $r0, label`。旧 README 记录过旧工具链 `bnez` 编码兼容问题，当前测试覆盖的是该自检程序实际使用的指令序列。

测试台时钟为 100 MHz、按周期检查功能；硬件设计及 XDC 使用 50 MHz。测试台按键/拨码输入固定 0，ExtRAM 初始填零。完整回归采集 480000 个有效像素并抽查 5 个位置。波形短运行目标跳过整帧。CPU 主动读取按键、执行 FB_CTRL 翻页以及 C++ 游戏固件均需后续测试。

## 判定标准

- `STATUS[13]` 在超时前置 1（程序跑完）
- `STEP=1234` → `LED[4:0]=12`、数码管显示 34 的段码正确
- 采一整帧 VGA：`(0,0)`/`(3,0)` 为 `0xEF`，`(0,1)`/`(3,1)` 为 `0xE0`，`(4,1)` 为 0
- 无 `RESULT: FAIL`

## 后续

2026-11-14 本次复验：LA32 v2.0 工具链、Verilator 5.032，`RESULT: PASS` / `SOC_SIM: PASS`。程序 8132 拍完成，LED/数码管、480000 像素采集及 5 个抽查像素通过。编译存在既有位宽警告，默认构建使用 `-Wno-fatal`；独立 `lint`、综合及时序验收分别执行。本次日志在 WSL `/home/caohw/build/la32r/soc-review-20261114/log.txt`。

1. 已完成最小 C++ 启动层和 data/BSS/栈自检；后续程序沿用已验证的入口和内存布局。
2. 输入及显示驱动已通过 CPU 测试；下一步接入 LA32R 平台后端并用完整游戏镜像回归。
3. 接入现有 2048 核心，固定种子回放并完成板级 SRAM 加载/复位/显示验收。
