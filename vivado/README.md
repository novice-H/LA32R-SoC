# Vivado 工程与 bitstream 生成

## 0. 当前构建入口与验收状态（2026-11-14）

本目录提供工程 Tcl 与 Windows `.bat` 启动器。各机器的 Vivado 安装路径在本地配置；运行时选择安装平台对应的 Vivado 入口。硬件资源、地址映射和 SoC 状态见 [soc/README.md](../soc/README.md)。

当前 RTL 已集成为 `thinpad_top → soc_top`，整机汇编自检通过；XDC 静态检查为 249/249 端口位覆盖且无引脚重复。CPU cache 的两份 `.xcix` 文件已在仓库。硬件提交 `8ec0463` 已交付 [artifacts/thinpad_top.bit](artifacts/thinpad_top.bit)（9730760 B），并在提交记录中报告 WNS=+0.211 ns / WHS=+0.048 ns、0 failing endpoints。本次本机核对了 bit 与目标提交的 Git blob 一致性及文件头；未重跑 Vivado，具体资源使用量待综合报告，上板行为待实际验收。

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
vivado\artifacts\thinpad_top.bit
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
| RTL | 显式加入板级/SoC/confreg/视频，并加入 `soc/bus/*.v`、`soc/mem/*.v`、`soc/cpu/open-la500/*.v` |
| CPU cache IP | `soc/cpu/open-la500/IP/*.xcix`（自动 `upgrade_ip`） |
| 约束 | `constraints/thinpad_top.xdc`（引脚表生成）及 `constraints/config_vtg.xdc`（配置电压） |
| 时钟 | `clk_50M` = K21，`create_clock 20 ns` |
| 运行流 | `launch_runs synth_1`，再 `launch_runs impl_1 -to_step write_bitstream`，由 run 处理 cache IP 容器 |
| 实现策略 | `Performance_ExplorePostRoutePhysOpt`；实际应用情况和结果以 Vivado 日志及报告为准 |

当前脚本完成构建后复制 bit 到 `artifacts/` 并打印 WNS/WHS。负 WNS 会给出告警；验收时同时审阅 setup、hold、未约束路径及接口时序报告。

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
SRAM/视频等接口应结合器件与板级时序核对输入/输出约束，并审阅未约束路径及实际 timing 报告。

## 5. 生成完成后

1. 打开 Vivado → Hardware Manager → Open Target → Auto Connect；
2. Program Device 选 `thinpad_top.bit`；
3. 按板级调试方案将固件加载到 BaseRAM（当前启动地址 `0x1C000000`），在加载期间管理 CPU 复位，加载后再释放复位。此流程仍待实现与实机验证。
4. 加载并运行对应程序后检查板子行为：
   - 数码管显示 STEP 的个位/十位，LED[4:0] 显示百位以上；
   - 屏幕应显示程序写入的测试图案（当前启动程序只画了粉色一行 + 红色 4 像素）；
   - `reset_btn`（BTN6）复位。

`sim/soc/prog/start.S` 是原汇编自检，`sw/tests/board_smoke.cpp` 是已通过整机仿真的最小 C++ 自检。后者已有 `crt0.S` 和链接脚本，执行 `source requirements/env.sh`、`make -C sw board-smoke` 可生成 `smoke.elf/.bin/.hex`；自检会显示步数 1234、品红一行及红色四像素。程序来源、初始化验证和构建细节见 [sw/README.md](../sw/README.md)。

仿真通过 `$readmemh` 预装 BaseRAM；当前 Tcl 生成 bitstream 时未配置把软件初始化到板外 SRAM。实机需先完成并记录外部 SRAM 软件加载及复位流程，`smoke.bin` 的加载地址为 `0x1C000000`。验证最小自检后，再加载后续完整游戏固件。bitstream 下载和软件镜像加载分别验收。
