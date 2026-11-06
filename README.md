# LA32R-SoC

在龙芯 **LoongArch32 Reduced（LA32R）** 软核上搭建 SoC，实现**可游玩的 2048** 与 **Expectimax 自动求解 AI**。

> 本 README 只介绍**仓库骨架**：目录职责、文件落位、放置约定。
> 硬件与软件的全部设计原理（地址映射、寄存器定义、视频时序、AI 算法、验证方法）见 **[`docs/design.md`](docs/design.md)**。

---

## 目录总览

```
.
├── README.md               # 本文件：只说明仓库骨架
├── docs/                   # 设计文档与架构图
├── soc/                    # RTL 源码（可综合）
│   └── accel/              #   （P2）AI 硬件加速
├── sim/                    # 仿真 testbench
├── sw/                     # 目标板固件（LA32R 裸机）
│   ├── boot/               #   启动代码与链接脚本
│   ├── libc/               #   精简 libc
│   ├── drv/                #   外设驱动与绘制库
│   ├── hal/                #   硬件抽象层（含 PC 模拟后端）
│   └── app/                #   应用层：游戏逻辑 + 渲染 + AI
├── ref/                    # PC 端参考实现（oracle）与代码生成器
└── tools/                  # 构建、烧写、校验脚本
```

---

## 各目录职责

| 目录 | 职责 | 主责 |
| --- | --- | --- |
| `docs/` | 设计说明、接口契约、架构图、调试码对照表 | 全员 |
| `soc/` | 全部 Verilog RTL，可综合，端口与板卡顶层模板严格一致 | 队员 1 |
| `soc/accel/` | （P2 可选）行移动引擎等 AI 硬件加速 | 队员 1 |
| `sim/` | Verilator / iverilog testbench，单元级与整机级 | 队员 1 |
| `sw/boot/` | `crt0.S` 启动、`.bss` 清零、链接脚本 | 队员 2 |
| `sw/libc/` | `memcpy` / `memset` / `printf` 等最小实现（仅整数） | 队员 2 |
| `sw/drv/` | `confreg`、帧缓冲绘制、输入层、字模 | 队员 2 |
| `sw/hal/` | `platform.h` 统一接口 + 目标板后端 + PC 模拟后端 | 队员 2 |
| `sw/app/` | 2048 规则内核、界面绘制、Expectimax AI、主循环 | 队员 3 |
| `ref/` | PC 端 oracle、行移动表生成器、一致性回归脚本 | 队员 3 |
| `tools/` | 构建入口、烧写脚本、验证脚本 | 全员 |

**分层铁律**：`sw/app/` 内**禁止出现任何 MMIO 地址常量**，硬件访问一律经 `sw/hal/platform.h`。
这样同一份应用代码既能编到板子上（`TARGET=la32r`），也能在 PC 上跑（`TARGET=pc`，SDL 或终端后端），三人不会互相阻塞。

---

## 文件落位表

状态：✅ 已存在　⬜ 待实现

### `soc/` —— RTL

| 文件 | 内容 | 状态 |
| --- | --- | --- |
| `top.v` | 顶层，端口与板卡模板顶层严格一致 | ⬜ |
| `la32r_wrap.v` | 赛方 CPU IP 封装：时钟复位接入、接口归一化 | ⬜ |
| `bus.v` | 地址译码 + 固定 2 拍应答 | ⬜ |
| `sram_ctrl.v` | BaseRAM / ExtRAM 控制器 + 双主机仲裁 | ⬜ |
| `confreg.v` | `STEP` / `STATUS` / `BTN` / `KEY` / `TIME` / `RAND` / `FB_CTRL` | ⬜ |
| `dvi_timing.v` | 800×600@72 Hz 时序发生（与 `clk_sys` 同域） | ⬜ |
| `dvi_fb.v` | 帧缓冲读出 + 4px 打包 + FIFO + 双缓冲 | ⬜ |

### `sim/` —— testbench

| 文件 | 内容 | 状态 |
| --- | --- | --- |
| `tb_soc.v` | 整机冒烟：取指、访存、外设 | ⬜ |
| `tb_sram.v` | SRAM 读写与字节使能 | ⬜ |
| `tb_confreg.v` | 寄存器读写、按键脉冲、BCD 解码 | ⬜ |
| `tb_dvi.v` | 视频时序与帧缓冲读出 | ⬜ |

### `sw/boot/`、`sw/libc/`

| 文件 | 内容 | 状态 |
| --- | --- | --- |
| `boot/crt0.S` | 入口、栈初始化、`.bss` 清零、跳 `main` | ⬜ |
| `boot/link.ld` | 内存布局（BaseRAM 4 MB，栈顶 `0x8040_0000`） | ⬜ |
| `libc/string.c` | `memcpy` / `memset` / `memmove` / `str*`（4 字节对齐特化） | ⬜ |
| `libc/printf.c` | `printf` / `vsnprintf`（**仅整数，不链 `%f`**） | ⬜ |

### `sw/drv/`

| 文件 | 内容 | 状态 |
| --- | --- | --- |
| `confreg.c` | 寄存器读写、`time_ms`、`rng_next` | ⬜ |
| `fb.c` | `fb_fill_rect` / `fb_blit_glyph` / `fb_end_frame` | ⬜ |
| `fb.h` | 帧缓冲常量（FB0/FB1 基址、`PITCH`）、三色调色板 | ⬜ |
| `kbd.c` | 按键单拍事件、`key[0]` 两阶段上升沿检测 | ⬜ |
| `font8x16.h` | 8×16 字模，**仅 `0`~`9`**（10 字 × 16 B = 160 B） | ⬜ |

### `sw/hal/`

| 文件 | 内容 | 状态 |
| --- | --- | --- |
| `platform.h` | `platform_t` 接口表，应用层唯一可见的硬件能力 | ⬜ |
| `la32r.c` | 目标板后端（直接 MMIO） | ⬜ |
| `pc_sim.c` | PC 模拟后端（SDL2 窗口，或终端 ASCII 降级） | ⬜ |

### `sw/app/`

| 文件 | 内容 | 状态 |
| --- | --- | --- |
| `main.c` | 主循环与状态机（PLAYING / WIN / LOSE） | ⬜ |
| `game2048.c` / `.h` | 规则内核：压缩-合并-再压缩、生成、胜负判定 | ⬜ |
| `view.c` / `.h` | 800×600 全屏 4×4 棋盘绘制 | ⬜ |
| `ai_board.c` | 位板（`uint32_t row[4]`）与行移动查表 | ⬜ |
| `ai_heur.c` | 启发式函数（空格 / 单调 / 平滑 / 最大块，整数化） | ⬜ |
| `ai_search.c` | Expectimax 递归、概率剪枝 | ⬜ |
| `ai_cache.c` | 转置表（直接映射哈希） | ⬜ |
| `ai_ctrl.c` | 迭代加深、时间预算、深度自适应 | ⬜ |
| `autoplay.c` | AI 接管调度（`key[1]` 电平驱动） | ⬜ |

### `ref/`、`tools/`

| 文件 | 内容 | 状态 |
| --- | --- | --- |
| `ref/ref_ai.py` | PC 端 oracle，批量输出「局面 → 最佳方向」数据集 | ⬜ |
| `ref/gen_rowtable.py` | 预生成 `next_row[65536]` + `row_score[65536]`，打包进镜像 | ⬜ |
| `tools/Makefile` | 构建入口：`make TARGET=la32r` / `make TARGET=pc` | ⬜ |
| `tools/README.md` | 工具链、烧写、仿真流程说明 | ⬜ |

### `docs/`

| 文件 | 内容 | 状态 |
| --- | --- | --- |
| `design.md` | 设计说明：目标一（2048）→ 目标二（AI）全量原理 | ✅ |
| `2048硬件架构.drawio` / `.png` | 硬件架构图 | ✅ |
| `interface.md` | 冻结的接口契约（地址映射 / 寄存器 / HAL / 绘制坐标对齐） | ⬜ |
| `isa-probe.md` | LA32R 指令子集实测结论 | ⬜ |
| `led-codes.md` | `LED[12:5]` 调试码对照表 | ⬜ |

---

## 放置约定

1. **RTL 一律进 `soc/`**，testbench 一律进 `sim/`，不与固件混放。
2. **`docs/` 下的 PDF 不进版本库**。赛方与厂商文档版权受限（龙芯手册明确禁止公开传播），已在 `.gitignore` 中排除，请勿用 `git add -f` 强行加入。
3. **构建产物不入库**：`build/`、`*.o`、`*.elf`、`*.bin`、`*.bit`、Vivado 的 `*.dcp` / `.runs/` 等均已在 `.gitignore` 中排除。
4. **换行符由 `.gitattributes` 统一**（仓库内存 LF，二进制文件不做转换）。请勿单独改编辑器换行设置，否则会产生满屏无意义 diff。
5. **绘制横坐标必须是 4 的倍数**：LA32R 要求访存地址对齐，帧缓冲用 32 位写，非对齐访问会直接触发地址异常。详见 `docs/design.md` §2.3.5。
6. **提交信息前缀**：`[hw]`（RTL/仿真）、`[bsp]`（boot/drv/hal）、`[app]`（游戏/AI）、`[doc]`、`[fix]`。
7. **分支**：`main` 保持可综合、可交付；各人在 `dev-hw` / `dev-bsp` / `dev-app` 上开发，合入前自测通过。

---

## 相关资源

- 龙芯架构 32 位精简版参考手册（`A03`，本地 `docs/`，不入库）
- 计算机系统能力培养远程实验平台 组成与介绍 / 原理图（`A04`/`A05`，本地 `docs/`，不入库）
- 2026 年山东省集成电路设计竞赛赛题详细说明（本地 `docs/`，不入库）
- 参考仓库：[tiehuis/2048-cli](https://github.com/tiehuis/2048-cli)（C 终端版 2048）、[ovolve/2048-AI](https://github.com/ovolve/2048-AI)（Expectimax AI）
