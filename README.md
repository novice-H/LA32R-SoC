# LA32R-SoC

## 当前状态（2026-11-14）

最新硬件提交 `8ec0463` 已通过 `eae1d4c` 合并至 `game2048`，交付首版 [thinpad_top.bit](vivado/artifacts/thinpad_top.bit) 并修复 Vivado 构建流程。当前 `thinpad_top` 已接入 `soc_top`，形成 openLA500 CPU、AXI 参考从桥、地址译码、BaseRAM/ExtRAM 控制器、显示仲裁器、confreg 和帧缓冲扫描的完整 RTL 链路。软件手动 2048 已通过 PC 测试与用户试玩；启动代码、链接脚本和最小 C++ 裸机程序已通过整机仿真，板级驱动及完整游戏固件待接入。

| 已接入资源 | 当前配置 |
| --- | --- |
| CPU | openLA500 / LA32R，含乘除法、cache、CSR/TLB；外部中断输入固定为 0 |
| 时钟 | 系统及视频均直接使用板载 50 MHz |
| 存储 | BaseRAM、ExtRAM 各提供 4 MiB 地址窗口；ExtRAM 由 CPU 与显示扫描共用 |
| 视频 | 800×600，RGB332，双缓冲；按扫描参数计算约 72.19 Hz |
| 输入 | 4 个方向按键事件、拨码低 2 位电平 |
| 输出 | 16 个 LED、2 个七段数码管 |
| 其他寄存器 | 毫秒计数、自由计数随机种子、VSYNC 翻页控制 |
| FPGA 工程目标 | `xc7a200tfbg676-2`，已有 XDC 和 Vivado Tcl 构建入口 |

完整的地址映射、寄存器、验证结果和待办见 **[SoC 硬件资源与状态](soc/README.md)**。整机测试说明见 [sim/soc/README.md](sim/soc/README.md)，软件规划见 [sw/README.md](sw/README.md)。本次核验结果以 SoC README 的验证表为准，FPGA 利用率和时序数据待综合/实现报告提供。

## 软件阶段与下一步

启动、自检实现与归档运行日志已核对：C++ 自检在完整 SoC 中 7600 拍完成，验证 data 搬移、BSS 清零、函数栈、main 返回、LED/数码管及显存输出；原汇编回归为 8132 拍。原始结果见本地 [C++ 日志](outputs/cpp-boot-20261114-v1/cpp-smoke.log)，可用 `source requirements/env.sh` 后执行 `make -C sw board-smoke-test` 复验。

confreg/MMIO 和按键输入驱动已实现，CPU 输入整机测试的 12 个场景、49 项 C++ 检查通过，覆盖四方向、持续按下、多键、读清和 KEY 电平。实现见 [input.cpp](sw/drv/input.cpp)，测试入口为 `make -C sw input-soc-test`，原始结果见本地 [输入测试日志](outputs/input-soc-20261114-v1/input-soc.log)。

RGB332 绘制、8×16 数字字模和双缓冲翻页驱动已实现。CPU 完整采集两幅画面共 960000 像素并全部匹配参考，4 次 VSYNC 翻页和超时恢复通过，结果见本地 [显示测试交付](outputs/framebuffer-20261114-v1/README.md)。实现借鉴用户已报告上板 VGA 验证的提交 `2103134`，本轮保持当前 RTL。

下一阶段实现 `platform_la32r.cpp` 并链接完整手动游戏。具体文件、依赖和验收条件见 [软件下一阶段计划](sw/README.md#下一阶段手动游戏板级接入)。AI 为选做；板上本版 C++ 程序的 SRAM 加载、复位和实机显示继续单独验收。

## 目录总览

```
.
├── README.md
├── AGENTS.md      # 项目规则：跨平台（Windows/Linux、pwsh/bash）协作约定
├── docs/
├── soc/
│   └── accel/
├── sim/
├── sw/
│   ├── boot/
│   ├── libc/
│   ├── drv/
│   ├── hal/
│   └── app/
├── ref/
└── tools/
```

## 目录职责

| 目录 | 职责 |
| --- | --- |
| `docs/` | 设计说明、接口契约、架构图、调试码对照表 |
| `soc/` | 全部 Verilog RTL，可综合 |
| `soc/accel/` | （P2 可选）行移动引擎等 AI 硬件加速 |
| `sim/` | Verilator / iverilog testbench，单元级与整机级 |
| `sw/boot/` | 已实现并仿真验证：启动、数据段初始化、栈和链接脚本 |
| `sw/libc/` | 按实际链接需求补充的最小内存函数 |
| `sw/drv/` | 已实现 confreg/MMIO、输入、RGB332 图元、数字字模和双缓冲翻页 |
| `sw/hal/` | 已有统一接口与 PC 后端；目标板后端待实现 |
| `sw/app/` | 已实现：手动 2048 规则内核与公共主循环；AI 为选做 |
| `ref/` | PC 端 oracle、行移动表生成器、一致性回归脚本 |
| `tools/` | 构建入口、烧写脚本、验证脚本 |

## 开发规范

本地配置与协作内容的分类、目录规划和提交检查见 [本地与协作文件管理](docs/local-and-shared.md)。
环境变量模板为 [env.example.sh](requirements/env.example.sh)，本机说明模板为
[LOCAL.example.md](LOCAL.example.md)。环境安装和验证见 [requirements/README.md](requirements/README.md)。
根目录 `LOCAL.md` 用于导航本机记录；详细环境实例保存在被忽略的 `requirements/local/README.md`。

跨平台协作（Windows / WSL / Linux，PowerShell 7 / bash）的统一约定见 [**AGENTS.md**](AGENTS.md)：
换行符 CRLF/LF、可执行位、文件编码、路径与文件名大小写、shell 语法对照、构建产物陷阱、
提交前自检清单。改脚本或配置前先扫一眼，能省掉大部分"在我机器上是好的"。
