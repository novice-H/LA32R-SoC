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

1. 在远程实验平台的 FPGA 配置界面选择并下载 `thinpad_top.bit`；本项目使用远程实验平台，不需要本机 JTAG。
2. 在平台提供的外部 SRAM 装载界面上传固件 `game.bin`。先执行 `source requirements/env.sh && make -C sw firmware`，生产固件默认位于 `${LA32R_BUILD:-$HOME/build/la32r}/sw/game/game.bin`。
3. 固件链接入口与 CPU 复位取指物理地址为 BaseRAM `0x1C000000`，即 BaseRAM 相对偏移 0。按远程平台实际界面填写地址/偏移字段；字段语义和格式需在实际上传界面核对。保持 CPU 复位，完成 BIN 上传后按平台流程释放复位。
4. 记录平台/板卡标识、bitstream、BIN 文件名与大小、上传地址字段和复位操作，并检查 VGA 游戏画面、四方向按键、KEY0 关闭清屏/清 LED/清旧事件、KEY0 重新开启新局及持续运行。此处作为验收清单；当前没有本轮远程上板结果。

`sim/soc/prog/start.S` 是原汇编自检，`sw/tests/board_smoke.cpp` 是已通过整机仿真的最小 C++ 自检。执行 `source requirements/env.sh`、`make -C sw board-smoke` 可生成 `smoke.elf/.bin/.hex`；自检会显示步数 1234、品红一行及红色四像素。完整手动游戏使用 `make -C sw firmware` 构建 `game.bin`；`game-soc-test` 固定 seed123 CPU 回放、输入生命周期、后台缓冲监控及完整 VGA 比较均通过，`game-live-test` 生产镜像测试也通过。数字字模常量修正后，最终 BIN 对应首局全帧及生产镜像 live 复测状态由交付 manifest 记录。程序来源、初始化验证和构建细节见 [sw/README.md](../sw/README.md)。

仿真通过 `$readmemh` 预装 BaseRAM；bitstream 不包含板外 SRAM 中的程序镜像。远程实验平台分别下载 bitstream 和上传 SRAM 镜像：完整游戏上传文件为生产目录的 `game.bin`，BaseRAM 物理入口为 `0x1C000000`。UART 与 Flash 未接入该加载流程。远程验收记录平台 UI 地址字段、上传文件标识、复位启动结果、VGA、按键与 KEY0 开关行为；远程实机运行待上传验收。
