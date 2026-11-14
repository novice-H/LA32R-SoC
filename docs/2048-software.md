# 2048 软件文件规划与实现逻辑

## 当前范围与文件职责

当前实现手动 2048、PC 规则测试、WSL/Linux 终端试玩、LA32R 板级后端与整机仿真入口。AI 为选做。核心参考 plibither8/2048.cpp 的规则代码，使用 C++11、固定数组和整数进行精简实现。

| 文件 | 职责 | 开发板移植时的处理 |
| --- | --- | --- |
| `sw/app/game.h` | 棋盘、方向、状态与规则函数声明 | 共用 |
| `sw/app/game.cpp` | 初始化、移动合并、随机生成、胜负判断 | 共用 |
| `sw/app/main.cpp` | 获取事件 → 移动 → 生成方块 → 绘制 | 共用；启动层调用 main |
| `sw/hal/platform.h` | 输入事件、开局等待、绘制、随机数接口 | 共用 |
| `sw/hal/platform_pc.cpp` | POSIX 终端按键、字符棋盘、伪随机数 | 板级构建选择新的后端 |
| `sw/hal/platform_la32r.cpp` | confreg 输入、KEY0 生命周期、硬件随机种子 | 已实现并通过整机游戏回放 |
| `sw/hal/board_render.cpp` | RGB332 棋盘、状态文字及 framebuffer 提交 | 已实现；最终游戏帧待整机比较 |
| `sw/tests/game_test.cpp` | 固定棋盘、固定随机序列的规则验证 | PC 回归；也可供仿真复用测试输入 |
| `sw/tests/pc_test.py` | 输入回放和伪终端交互检查 | PC 测试工具 |
| [`sw/boot/crt0.S`](../sw/boot/crt0.S) | 设置启动栈、复制 `.data`、清零 `.bss`、调用 `main`；`main` 返回后停在 `_boot_halt` | 已有启动层；当前由 SoC smoke image 验证 |
| [`sw/boot/link.ld`](../sw/boot/link.ld) | 将镜像链接到 BaseRAM `0x1C00_0000`，定义 data LMA/VMA、BSS、栈顶和边界断言 | 已有 smoke 链接布局；动态 C++ 初始化目前由断言禁用 |
| [`sw/tests/board_smoke.cpp`](../sw/tests/board_smoke.cpp) | 检查初始化 data、BSS 清零、栈读写、confreg 和 FB0 写入 | 独立自检入口，用于启动与硬件通路验收 |
| [`sw/drv/confreg.h`](../sw/drv/confreg.h) | 寄存器偏移/位域和对齐 32 位 volatile MMIO 访问 | 已实现，当前复位后的 uncached 配置下使用 |
| [`sw/drv/input.h`](../sw/drv/input.h) / [`input.cpp`](../sw/drv/input.cpp) | BTN 读清、软件 pending、四方向输出、KEY 电平 | 已在 CPU 输入整机测试验证 |
| [`sw/tests/input_soc.cpp`](../sw/tests/input_soc.cpp) | 由 CPU 执行 12 场景、49 项输入检查 | 独立输入自检固件 |
| [`sw/drv/framebuffer.h`](../sw/drv/framebuffer.h) / [`framebuffer.cpp`](../sw/drv/framebuffer.cpp) | RGB332 图元/数字、后台获取、翻页与超时 | host 与 CPU 完整图像测试通过 |
| [`sw/drv/font_digits.h`](../sw/drv/font_digits.h) | 0～9 的只读 8×16 字模，160 B | 独立 5×7 展开参考逐像素核验 |
| [`sw/tests/framebuffer_soc.cpp`](../sw/tests/framebuffer_soc.cpp) | CPU 实际绘图和提交/确认/超时恢复 | 两幅整帧比对、四次翻页通过 |
| [`sw/Makefile`](../sw/Makefile) | PC 构建/测试、交叉对象、启动 smoke 固件与 SoC 仿真入口 | `board-smoke-test` 目前验证 smoke image |
| `sw/third_party/2048.cpp.LICENSE` | 上游版权和 MIT 许可 | 随代码保留 |

平台抽象接口已在 [`sw/hal/platform.h`](../sw/hal/platform.h) 声明：`read_event()`、`render()`、`random_u32()` 和 `wait_for_start()`；事件包含 `Pause`。LA32R 后端、板级棋盘绘制和完整游戏固件均已接入，并通过 seed123 CPU 整机回放与生产镜像 live 测试。

## 数据与接口

`Game` 保存 `uint32_t tiles[4][4]`（0 表示空格，坐标顺序为行、列）、`score`、`moves`、`won` 和 `over`。本局合成 2048 后结束；应用主循环在胜负结束后继续接受重开和退出事件。

核心接口：

```cpp
void init(Game&, RandomFn, void* context);  // 清空状态并生成两个方块
bool move(Game&, Direction);               // 返回棋盘是否变化
bool spawn(Game&, RandomFn, void* context);// 在空位生成一个方块
bool can_move(const Game&);                // 检查空位或相邻同值
void refresh_status(Game&);                // 更新 over
```

调用者为 `init` 和 `spawn` 提供有效随机回调。随机源通过回调注入，测试可传固定序列；PC 后端使用 xorshift32，环境变量 `GAME2048_SEED` 控制种子。空格选择用随机值对空格数取模，方块数值按模 10 的一个结果生成 4、其余结果生成 2，目标比例约为 10% / 90%；取模具有微小分布偏差，适合当前手动游戏。

`move` 执行移动和合并，更新步数、分数及状态；`spawn` 单独执行生成，便于逐阶段验证。主循环在 `move` 返回 true 后调用一次 `spawn`，并绘制最终棋盘。无效移动保持步数、分数和随机序列。新方块生成后重新判断死局。

## 四个方向共用一套行处理

对每个方向，按照“靠近移动目的端 → 远离目的端”的次序提取四个数：

| 方向 | 提取次序 |
| --- | --- |
| 左 | 每行从左到右 |
| 右 | 每行从右到左 |
| 上 | 每列从上到下 |
| 下 | 每列从下到上 |

对提取出的每条线依次执行：

1. 去掉 0，将非零数按原顺序收集。
2. 从前往后扫描，遇到两个相邻同值就输出两倍值、累计得分，并跳过两个输入数；其他情况输出一个数。
3. 在尾部补 0 到四个数。
4. 按提取次序写回，并与原棋盘比较。

例如向左移动：`[2,0,2,4] → [2,2,4] → [4,4] → [4,4,0,0]`，得分增加 4。新合成的 4 已进入输出数组，本次扫描继续处理剩余输入，因此每个方块每步最多参与一次合并。

`[2,2,2,2] → [4,4,0,0]`，得分增加 8。`[2,2,4,0] → [4,4,0,0]`，得分增加 4。只要四条线中至少一条变化，步数加一，随后主循环生成一个新方块。

## 游戏循环与状态

```text
初始化两个方块 → 绘制
  → 获取单次方向 / 重开 / 退出事件
  → 重开：重新初始化；退出：结束进程
  → 本局进行中：处理方向移动
  → 棋盘变化：生成一个方块
  → 绘制棋盘和状态 → 等待下一事件
```

合并生成 2048 时设置 `won`。棋盘存在空格或上下/左右相邻同值时仍有机会移动；满盘且所有相邻块均不同则 `over=true`。第一版胜利移动也先完成生成与绘制，再冻结本局。

## 验证与板级接入

`make -C sw test` 运行核心用例和 PC 回放/伪终端测试，覆盖四方向、合并顺序、得分步数、胜负、随机生成、确定性、方向键、重开、退出及终端恢复。用同一随机种子与同一输入序列可复现问题。

### 已实现并通过 SoC 仿真的启动层

[`sw/boot/crt0.S`](../sw/boot/crt0.S) 将栈指针设为 `0x1C40_0000`，按 32 位字从 data 的加载地址复制到运行地址，清零 BSS，再调用 `main`；`main` 返回后进入 `_boot_halt`。链接脚本 [`sw/boot/link.ld`](../sw/boot/link.ld) 将镜像放入 4 MiB BaseRAM 窗口，data 运行地址按 4 KiB 对齐，BSS 和栈空间有边界断言，并要求 `.init_array` 为空。当前启动层按静态常量初始化的 freestanding 程序使用。

验证程序 [`sw/tests/board_smoke.cpp`](../sw/tests/board_smoke.cpp) 先检查初始化全局变量和 BSS，再通过 `noinline` 栈数组读写核对 `0xAA` 校验和，写入 FB0 测试图案及 STEP/STATUS 寄存器，最后从 `main` 返回。SoC 仿真在复位前将 data/BSS 目标区填为 `0xDEADBEEF`，验证启动复制和清零确实覆盖旧值。

记录在 [`outputs/cpp-boot-20261114-v1/cpp-smoke.log`](../outputs/cpp-boot-20261114-v1/cpp-smoke.log) 的完整 SoC 仿真报告 7600 拍后状态、LED、数码管、`_boot_halt` 返回地址、data/BSS/stack 检查以及完整帧像素抽查均通过。对应 [`manifest.json`](../outputs/cpp-boot-20261114-v1/manifest.json) 记录镜像大小 468 字节、BaseRAM 入口 `0x1C00_0000`、栈顶 `0x1C40_0000`、栈保留 16 KiB，并记录无未定义 ELF 符号。该验收覆盖的是 smoke 固件和 RTL 仿真模型。

### 当前实现与验收状态

1. **平台与主循环**：`platform_la32r.cpp` 将 KEY0 低电平映射到 `Pause`，等待开局时清除旧输入事件、清 LED 状态并清屏；KEY0 开启后按硬件 RAND 初始化 xorshift 状态。KEY1 当前忽略。主循环在外层等待开局、初始化新棋局，内层消费按键；暂停后返回外层等待。AI 为选做。
2. **固件构建**：在 WSL 仓库根目录执行 `source requirements/env.sh && make -C sw firmware`。`GAME_SEED` 默认 0 表示从硬件计数器取种子；产物在 `${LA32R_BUILD:-$HOME/build/la32r}/sw/game/`，包括 `game.elf`、`game.bin`、`game.hex`、map、反汇编、符号表与 ELF 信息。ELF 链接入口为 BaseRAM 物理地址 `0x1C000000`；`game.bin` 是远程实验平台上传的固件文件。
3. **整机回放**：最终生产镜像 `game-live-test` 通过 CPU 启动、初始双 tile、Left 后 3 tiles/`moves=1`/`score=0` 检查，`RESULT: PASS`；仿真时间 332 ms，wall time 220.768 s。固定 `GAME_SEED=123` 的完整 `game-soc-test` 返回 `RESULT: PASS` / `SOC_SIM: PASS`：Up/Left/Down/Right 至 serial 5、Up 长按仅产生 serial 6、KEY0 关闭后 inactive=0、standby Right 被清除后重开至 serial 7，KEY=3（KEY0/KEY1 均为 1）时手动 AI=0。每次 20 个 CPU 状态字段快照匹配 host；后台显存写入与 VSYNC 监控通过，完整 VGA 480000 像素 `different_pixels=0`。Golden 回放是普通棋局，`won`、`over` 均为 false；胜利与死局规则由 host `game_test` 覆盖。仿真时长约 1 s，wall time 721.498 s。数字字模修正后，`GAME_RUN_ARGS=+game-image-test` 首局画面测试返回 `RESULT: PASS` / `SOC_SIM: PASS`，仿真 172 ms、wall time 111.236 s、480000 像素差异为 0，目视确认标题“2048”和棋盘正常。`glyph-diff.json` 记录新旧 seed123 固件仅 30 B 标题 5×7 数字表不同，其余 bytes 完全相同。最终生产 `game.bin` 为 7080 B，SHA256 `c81c4d1df53d7da12d9015cd5b42b55aa90776740246e8cf61027a2afac4928e`；完整文件/哈希及各测试关系见交付 manifest。
4. **远程实验平台与实机验收**：先将 bitstream 下载到 FPGA，再由远程实验平台的 SRAM 装载入口上传生产固件 `game.bin`，配置 BaseRAM 物理地址 `0x1C000000`/复位入口并按平台流程管理 CPU 复位。平台 UI 的加载字段和 SRAM 偏移填写方式需对照实际界面确认；地址 `0x1C000000` 对应 BaseRAM 偏移 0。无需本机 JTAG。当前没有本轮远程上板记录，需实测 VGA 棋盘、四方向按键、KEY0 暂停/清屏/新局和连续运行后再登记结果。UART 和 Flash 当前均未接入固件下载路径。

AI 为选做功能，安排在基本输入、渲染和完整游戏镜像通过 SoC 与板上验收之后；AI 搜索策略、运行时间和棋盘结果需单独建立用例及资源测量。

### 已验证的输入驱动

调用者持有 `input::State{}`，`clear()` 清除软件待处理位并读取 BTN 丢弃旧事件；`poll()` 在软件位为空时读取 BTN，然后按上、左、下、右顺序每次返回一项。`keys()` 返回 KEY 低两位电平。`input::Button` 的值是方向位掩码，后续板级平台通过显式映射转换为 `platform::Event`。

原始测试见 [input_soc.cpp](../sw/tests/input_soc.cpp) 与 [input_scenarios.svh](../sim/soc/input_scenarios.svh)。测试台驱动真实板级 touch_btn/dip_sw，CPU 执行交叉编译的固件和驱动，通过 STEP/KEY 握手推进场景。12 场景覆盖四方向、长按、多键顺序、跨时刻不同方向累积、同方向事件合并、释放再按、软件/硬件 clear 和 KEY 电平，共 49 项固件检查；测试台另核对真实 BTN 读响应及次数。日志见本地 [input-soc.log](../outputs/input-soc-20261114-v1/input-soc.log)。C++ 启动及原汇编回归分别保持 7600 / 8132 拍通过。

当前 RTL 的 BTN 读清与新同步边沿同拍时清零优先，输入测试通过稳定期握手覆盖普通读取路径；该并发条件作为硬件后续修复/验证项记录在 [SoC README](../soc/README.md)。

### 已验证的显示驱动

`Surface` 固定对应 800×600 RGB332 字缓冲。图元在裁剪后按整字写入，非四像素对齐的首尾采用字内掩码读改写，数字按透明 8×16 字模放大绘制。`Frame` 在 `begin` 成功后取得后台页；`present` 检查页号/指针/请求状态，执行 DBAR 0 后申请翻页，并等待请求清除和目标页显示。单线程提交、当前 uncached 配置下使用；超时后重新 `begin` 等待硬件完成并取下一后台。

主机测试使用独立像素和字形参考，检查裁剪、字节 lane、全屏填充、0～9、十进制 0/2048/uint32 最大值和放大倍数；并通过 ASan/UBSan。CPU 测试实际绘制两幅图，以显示 RGB 端口采集的结果和 golden 逐像素比较，监控前后台写地址、字使能、VSYNC 切换、边界哨兵，验证零等待期限超时及恢复。原始结果与实际画面见本地 [framebuffer-20261114-v1](../outputs/framebuffer-20261114-v1/README.md)。
