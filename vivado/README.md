# Vivado 工程与 bitstream 生成

## 0. 本机现状（重要）

这台 Linux 上能找到的两份 Vivado **都是 Windows 安装**，Linux 无法执行，所以 bit 需要在
Windows 侧生成（或在 Linux 另装 Linux 版 Vivado）：

| 位置 | 版本 | 平台 |
| --- | --- | --- |
| `/media/zai-linux/Data/Xilinx/Vivado/2023.2` | 2023.2 | Windows（`bin/unwrapped` 只有 `win64.o`） |
| `/media/zai-linux/FP70/Xilinx/Vivado/2019.2` | 2019.2 | Windows（同上） |

本目录提供的是**与平台无关的工程 Tcl**，Windows / Linux 都能用。

## 1. Windows 一键生成

1. 确认 Vivado 可用：
   - 已在 `PATH` 里：直接下一步；
   - 没在 `PATH` 里：编辑 `build_bit.bat`，把 `VIVADO_BIN` 改成实际路径，例如
     `C:\Xilinx\Vivado\2023.2\bin\vivado.bat`。
2. 双击 `vivado\build_bit.bat`（或在 cmd 中运行）。
3. 产物：

```
vivado\build\thinpad\thinpad_top.bit
vivado\build\thinpad\reports\utilization.rpt
vivado\build\thinpad\reports\timing_summary.rpt
vivado\build\thinpad\reports\drc.rpt
```

日志在 `vivado\build_bit.log`。

## 2. 命令行方式（Windows 或 Linux）

```bat
vivado -mode batch -source vivado\build_bit.tcl -notrace
```

```bash
vivado -mode batch -source vivado/build_bit.tcl -notrace
```

## 3. 工程配置

| 项 | 值 |
| --- | --- |
| Part | `xc7a200tfbg676-2`（Artix-7 200T） |
| 顶层 | `thinpad_top` |
| RTL | `soc/` 下全部（含 `soc/cpu/open-la500/*.v`） |
| CPU cache IP | `soc/cpu/open-la500/IP/*.xcix`（自动 `upgrade_ip`） |
| 约束 | `constraints/thinpad_top.xdc`（由 `tools/gen_xdc.py` 从引脚表生成） |
| 时钟 | `clk_50M` = K21，`create_clock 20 ns` |

## 4. 常见问题

**Q1：IP 升级失败 / `.xcix` 不被识别**

脚本会自动回退：定义 `SIMU` 宏，`dcache.v` 使用可推断的行为 SRAM（能综合，但时序、面积、
频率与正式 IP 不同，仅建议用于先跑通）。修好 IP 后把 `build_bit.tcl` 里的
`USE_INFERRED_SRAM` 置 0 再跑一次。

**Q2：许可证**

设环境变量指向 license 文件：

```bat
set XILINXD_LICENSE_FILE=D:\Xilinx\vivado.lic
```

**Q3：Linux 上跑 Vivado 报缺 `libtinfo.so.5`**

Vivado 2019.2 依赖老库，在 Ubuntu 22.04+ 需要额外安装 `libtinfo5`/`libncurses5`
（或从旧发行版取库并设 `LD_LIBRARY_PATH`）。

**Q4：综合出不来 / 时序不收敛**

先看 `reports/utilization.rpt` 和 `reports/timing_summary.rpt`。当前是 50 MHz 单时钟域，
Apple 上没有额外 I/O 时序约束，若 SRAM/视频采样有问题再补 `set_output_delay`。

## 5. 生成完成后

1. 打开 Vivado → Hardware Manager → Open Target → Auto Connect；
2. Program Device 选 `thinpad_top.bit`；
3. 板子行为：
   - 数码管显示 STEP 的个位/十位，LED[4:0] 显示百位以上；
   - 屏幕应显示程序写入的测试图案（当前启动程序只画了粉色一行 + 红色 4 像素）；
   - `reset_btn`（BTN6）复位。

> 当前 `sim/soc/prog/start.S` 只是仿真用最小程序，上板后要换成正式的 `crt0.S` + 2048 软件，
> 否则屏幕内容就是几行测试色块。
