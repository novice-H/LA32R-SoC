# 手动 2048（PC / 裸机移植准备）

第一版提供 WSL/Linux 终端试玩、规则测试和平台接口。达到 2048 或无合法移动时结束本局，R 重开，Q 或 Ctrl-C 退出。每次有效移动增加一步，合并生成的数字计入分数。自动游玩 AI 为选做，本版集中实现手动游戏。

## sw 全部文件规划

以下为手动游戏的软件文件规划。标注“已实现”的文件当前存在；“待实现”文件在对应开发阶段创建。目录中的 `.gitkeep` 用于保留空目录。构建对象、汇编清单、ELF 和镜像存放在 WSL 构建目录。

```text
sw/
├── README.md                  已实现：文件规划、算法、构建和移植说明
├── Makefile                   已实现：PC 构建/测试、LA32R 对象编译检查
├── app/
│   ├── game.h                 已实现：棋盘、方向、状态、规则函数声明
│   ├── game.cpp               已实现：初始化、移动合并、生成与胜负判断
│   └── main.cpp               已实现：平台无关的手动游戏主循环
├── hal/
│   ├── platform.h             已实现：方向/重开/退出事件、绘制、随机数接口
│   ├── platform_pc.cpp        已实现：WSL/Linux 终端后端
│   └── platform_la32r.cpp     待实现：开发板后端，连接驱动与游戏主循环
├── boot/
<<<<<<< HEAD
│   ├── crt0.S                 已实现：启动入口、栈、数据段初始化、调用 main
│   └── link.ld                已实现：入口、各段、栈和内存区域布局
├── drv/
│   ├── confreg.h              已实现：寄存器地址、位常量、对齐 32 位 volatile MMIO
│   ├── input.h                已实现：板载方向事件、游戏开关读取接口
│   ├── input.cpp              已实现：按键事件轮询及拨码电平读取
│   ├── framebuffer.h          已实现：RGB332 图元、后台缓冲与提交接口
│   ├── framebuffer.cpp        已实现：裁剪、32 位绘图、VSYNC 翻页及超时
│   └── font_digits.h          已实现：0～9 的 8×16 字模
=======
│   ├── crt0.S                 待实现：启动入口、栈、数据段初始化、调用 main
│   └── link.ld                待实现：入口、各段、栈和内存区域布局
├── drv/
│   ├── confreg.h              待实现：冻结后的寄存器地址、位域、MMIO 访问
│   ├── input.h                待实现：板载方向事件、游戏开关接口
│   ├── input.cpp              待实现：读取按键/拨码并转换为软件事件
│   ├── framebuffer.h          待实现：画点/矩形/数字、后台缓冲及提交接口
│   ├── framebuffer.cpp        待实现：RGB332 绘制和 VSYNC 翻页握手
│   └── font_digits.h          待实现：0～9 数字的只读字模
>>>>>>> 5f57701058e76b1bb6c4717c043f8e71cdb10eee
├── libc/
│   ├── memory.h               按需实现：memcpy/memmove/memset/memcmp 声明
│   └── memory.cpp             按需实现：链接确实需要的最小内存函数
├── tests/
│   ├── game_test.cpp          已实现：固定棋盘及随机序列的规则测试
│   ├── pc_test.py             已实现：输入回放、终端交互及恢复测试
<<<<<<< HEAD
│   ├── board_smoke.cpp        已实现：裸机 data/BSS/栈、LED/数码管和显存自检
│   ├── input_soc.cpp          已实现：12 场景、49 项输入驱动检查
│   ├── framebuffer_test.cpp   已实现：独立像素/字模模型与主机绘图测试
│   ├── framebuffer_pattern.h  已实现：两幅固定的显示测试图案
│   ├── framebuffer_soc.cpp    已实现：CPU 绘制、翻页、超时恢复测试
│   └── framebuffer_compare.py 已实现：逐像素比较和 PNG 预览导出
=======
│   └── board_smoke.cpp        待实现：板级最小自检，分阶段测 LED/输入/显示
>>>>>>> 5f57701058e76b1bb6c4717c043f8e71cdb10eee
└── third_party/
    └── 2048.cpp.LICENSE       已保存：上游 MIT 版权与许可
```

各层的依赖关系为：`main → game + platform`；PC 平台使用终端服务，LA32R 平台使用 `drv`。游戏核心只接收方向和随机数，处理棋盘与状态。板级 `render` 绘制棋盘、更新步数/状态输出并提交后台帧缓冲。板级退出事件应根据开关约定处理；启动层需为 `main` 返回提供确定的停机行为。

<<<<<<< HEAD
`Makefile` 已有 `board-smoke` 固件/镜像和 `board-smoke-test` 整机仿真目标，完整游戏固件待接入板级后端。PC 与 LA32R 构建分别选择一个平台后端；板级自检与游戏分别选择各自入口。编译器辅助函数按最终链接结果处理，按需链接匹配的 `libgcc`。文件名和职责按此规划推进，具体新增以实际依赖为准。

开发顺序：核心/PC 游戏 → C++ 启动 → 输入驱动 → RGB332/数字/双缓冲驱动 → 平台后端与完整游戏联调。前四项已实现；当前验收记录见各项测试说明。硬件资源见 [soc/README.md](../soc/README.md)。AI 保持选做。

## 最小 C++ 裸机程序（已验证）

在仓库根目录执行（WSL bash）：

```bash
source requirements/env.sh
make -C sw board-smoke       # ELF/BIN/HEX、map、符号和反汇编
make -C sw board-smoke-test  # 编译后运行完整 mycpu SoC 仿真
make -C sw board-smoke-wave  # 导出启动自检波形 soc/soc.vcd
```

默认产物在 `${LA32R_BUILD:-$HOME/build/la32r}/sw/board-smoke/`。`smoke.elf` 是入口 `0x1C000000` 的静态 ELF32 LoongArch 可执行文件，`smoke.bin` 是从该地址加载的连续镜像，`smoke.hex` 是供 SRAM 模型 `$readmemh` 使用的 32 位小端字。板上加载流程需将 BIN 放入 BaseRAM 的这个入口，再按流程释放 CPU 复位。

`board-smoke-wave` 使用带 `--trace` 的模型，启用 C++ 初始化断言，记录到程序完成后 100 拍。在 WSL 用 `gtkwave <构建目录>/board-smoke/soc/soc.vcd -S /mnt/f/CursorProject/LA32R-SoC/sim/soc/boot_wave.tcl` 打开；脚本选择时钟、复位、写回 PC、SRAM 读写和 LED/数码管等信号并缩放全图。该短波形用于观察启动及输出写入，完整帧检查由 `board-smoke-test` 执行。

启动顺序：设置栈顶 `0x1C400000`（预留 16 KiB）→ 从镜像加载地址复制 `.data` 到运行地址 → 清零 `.bss` → 调用 `main` → 返回后停在 `_boot_halt`。入口沿用 CPU 复位后的直接地址和 uncached 模式。当前最小运行时支持静态常量初始化，链接脚本以断言拒绝动态全局构造器；异常、RTTI 和展开信息关闭。

自检使用 `volatile` 初始化全局值和 BSS 数组，调用独立函数在栈上读写四个数字，校验和为 `0xAA`。成功后写 STEP=1234、STATUS=0x2000，并在 FB0 写品红一行和红色四像素；失败显示错误步号 1/2/3，并设置 STATUS=0x4000。

测试台从最终 ELF 的符号表取得地址，在释放复位前将 `.data` 运行区和 `.bss` 污染成 `0xDEADBEEF`，随后检查 C++ 结果 `0x600D2048`、栈校验和、返回停机地址、LED/数码管及视频帧。2026-11-14 实测自检 7600 拍完成，`RESULT: PASS` / `SOC_SIM: PASS`；原汇编自检回归仍为 8132 拍并通过。本次镜像 468 B，最终 ELF 无未解析符号。本地交付为 `outputs/cpp-boot-20261114-v1/`。

本次实现运行在完整 RTL 仿真中；输入及显示驱动已实现，下一步连接平台后端和完整游戏。FPGA 板上本版 C++ 程序加载和实际运行另行验收。

### 初始化实现的依据

实现位置为 [crt0.S](boot/crt0.S)、[link.ld](boot/link.ld) 和 [board_smoke.cpp](tests/board_smoke.cpp)，原始结果见本地 [自检日志](../outputs/cpp-boot-20261114-v1/cpp-smoke.log) 与 [ELF 段信息](../outputs/cpp-boot-20261114-v1/smoke.elf-info.txt)。该归档记录当时的源码哈希；当前测试台增加输入/显示分支后，启动行为由本轮回归日志核验，波形目标由当前 Makefile 定义。

GNU ld 将输出段的运行地址称为 VMA、镜像加载地址称为 LMA，`AT(...)` 指定 LMA；官方示例同时说明了启动时的数据复制和 BSS 清零。这里的 `link.ld` 使用相同机制，并在直接地址模式下把 data 运行区与紧凑镜像分开放置。参见 [GNU ld：Output Section LMA](https://sourceware.org/binutils/docs/ld/Output-Section-LMA.html)。该链接机制说明与当前程序通过 RTL 仿真的结果分别作为工具行为和项目验证依据。

## 下一阶段：手动游戏板级接入

以下均为待实施工作，按依赖顺序推进：

| 顺序 | 文件与工作 | 验收条件 |
| --- | --- | --- |
| 1 | `hal/platform_la32r.cpp`：接入已有输入/显示驱动与伪随机源；配合公共循环实现游戏开关生命周期 | 拨码关闭后保留等待状态，再开启可重新开始；胜负后可重开；手动版 AI 位保持 0；固定种子可重复操作结果 |
| 2 | `Makefile`：新增完整游戏 ELF/BIN/HEX 目标，复用 boot 和公共游戏核心 | 最终 ELF 入口正确、无未解析符号；在实际 CPU 链路验证函数指针/GOT、整数运算和访存；同种子同输入与 PC 棋盘、分数和步数一致 |
| 3 | 板级加载说明及验收记录：下载 bit、管理复位、加载 SRAM 程序、释放复位 | 先运行最小 C++ 自检，再运行完整手动游戏；确认显示、四方向、重开和持续运行结果 |

输入寄存器事实见 [confreg.v](../soc/confreg.v)：BTN 是读清事件位，KEY 为拨码低两位；现有 [platform.h](hal/platform.h) 定义方向、Restart、Quit、None，现有 [main.cpp](app/main.cpp) 在 Quit 时返回。板级游戏开关的等待/重新开启行为需与平台事件和主循环一同实现并测试。RAND 自由计数可用于初始化软件伪随机状态，回归测试使用固定种子。

### 输入驱动（已实现并通过 CPU 整机测试）

`drv/confreg.h` 定义 `0xBFD00000` 基址及 `Step/Status/Buttons/Keys/Time/Random/Framebuffer` 七个实际寄存器，提供对齐 32 位 volatile `read`/`write`。`drv/input.h/.cpp` 提供四方向事件、KEY 电平读取和调用者持有的软件 pending 状态。调用者以 `input::State state{};` 初始化；轮询为单线程用法：

```cpp
input::State state{};
input::clear(state);  // 清软件 pending，并读 BTN 丢弃旧硬件事件

const input::Button event = input::poll(state);
if (event == input::Button::Up) {
    // 处理一次向上事件
}

const std::uint32_t switches = input::keys();
const bool game_enabled = (switches & confreg::kGameEnable) != 0;
const bool ai_enabled = (switches & confreg::kAiEnable) != 0;
```

BTN 一次读取取得并清除硬件累积位；`poll` 将读取到的位保存在 `State::pending`，按 Up、Left、Down、Right 顺序每次交付一个方向。硬件每个方向只有一位，未读期间同方向的多次事件会合并。RTL 中若 BTN 读取与新按键 edge 落在同一时钟沿，读清赋值覆盖事件累积赋值，该 edge 会被清除。驱动采用 BTN 位掩码加调用者的软件 pending 状态，读取操作不形成原子快照队列。RTL 只在按键上升沿产生事件，因此长按期间首次报告后，后续轮询持续返回 `None`，直到新的按下沿到来。KEY 返回 `dip_sw[1:0]` 的当前电平。

在 WSL 仓库根目录运行 RTL CPU 输入回归：

```bash
source requirements/env.sh
make -C sw input-soc-test
```

`input-soc` 构建输入固件；`input-soc-test` 运行 `tests/input_soc.cpp` 的 12 个场景：

| 场景 | 检查内容 |
| --- | --- |
| 1–4 | Up、Left、Down、Right 单方向事件；Up 持续按下时连续轮询不重复 |
| 5 | 四键同时到达时按位序交付；独立 BTN 读清硬件后软件 pending 仍完整 |
| 6 | Up 与 Down 预先累积后均可交付 |
| 7–8 | 两个未读 Up edge 合并为一位；释放后重新按下可再次报告 |
| 9–10 | `clear` 分别清除软件 pending 和未读硬件事件 |
| 11–12 | KEY 仅返回低两位，分别检查值 1、2；同时确认无按键事件 |

2026-11-14 最终 CPU 整机测试通过：12 场景、49 项 C++ 检查，`input_test_result=0x600D1A00`，`main` 返回并停在 `_boot_halt`；BIN 为 2272 B。稳定日志位于 WSL `/home/caohw/build/la32r/input-20261114/input-soc.log`；C++ 启动和原汇编回归仍分别为 7600 / 8132 拍并通过。本地交付 [input-soc-20261114-v1](../outputs/input-soc-20261114-v1/README.md) 包含 ELF、BIN、HEX、反汇编、三份通过日志和 manifest。

本项验收覆盖 RTL CPU 仿真中的 `touch_btn` 与 `dip_sw` 输入路径。FPGA 实板输入尚待验收。显示驱动完成后，将这些接口接入板级平台后端与游戏固件。

### RGB332、数字与双缓冲驱动

实现见 [framebuffer.h](drv/framebuffer.h)、[framebuffer.cpp](drv/framebuffer.cpp)、[font_digits.h](drv/font_digits.h)。固定 800×600，四个低字节优先的 RGB332 像素打包为一个 32 位字；`rgb(r,g,b)` 从 RGB888 截取 R/G/B 的高 3/3/2 位。`Surface` 指向一个缓冲；`clear/pixel/fill_rect` 提供填充和裁剪，首尾不足四像素时进行对齐的 32 位读改写。负坐标、极端 int 尺寸和越界图形经过裁剪。

数字字模为 8×16、共 160 B，`digit` 支持 0～9，`number` 支持十进制 0～4294967295；整数放大倍数为 1～16。数字采用透明背景，调用者先填充底色。范围外数字或倍数保持图像。

```cpp
framebuffer::Frame frame{};
if (framebuffer::begin(frame)) {
    framebuffer::clear(frame.surface, framebuffer::rgb(0, 0, 255));
    framebuffer::fill_rect(frame.surface, 20, 20, 200, 100, 0xef);
    framebuffer::number(frame.surface, 40, 40, 2048, 3, 0xff);
    if (!framebuffer::present(frame)) {
        // 记录超时；下一帧重新 begin。
    }
}
```

`begin` 等待上一请求结束、读取前台页号并获取另一页；`present` 校验 Frame，先执行 `dbar 0` 再写翻页请求，等待 bit0 清零且 bit16 变为提交页。默认等待期限为 TIME 计数的 100 ms。超时后该 Frame 失效，硬件已收到的请求继续处理；再次 `begin` 等待请求结束并重新获取后台。使用条件是单线程唯一提交者、当前 reset 后的 uncached 数据访问。绘制期间保持前台与后台的所有权，提交后通过新一次 `begin` 获取下一帧。

`dbar 0` 的架构要求见本地[LA32R 手册](../docs/龙芯架构32位精简版参考手册.pdf) 2.2.6.1（PDF 第 34 页）；当前 CPU 的解码/等待条件见 `id_stage.v` 的 `inst_dbar`、`pipeline_no_empty` 和 `dbar_stall`。完整 cache 属性变化后的维护方案另行验证。

```bash
source requirements/env.sh
make -C sw framebuffer-test      # 独立逐像素参考、字模、裁剪及 golden 图
make -C sw framebuffer-soc       # 只生成 C++ 显示固件 ELF/BIN/HEX
make -C sw framebuffer-soc-test  # mycpu 绘制/翻页、画面比对和 PNG 导出
```

host 测试以独立像素模型和独立 5×7 字形展开为参考，再导出两幅 golden 图；SoC 测试实际采集每幅 480000 像素，监测 CPU 只写后台、整字使能及翻页时机，并验证无效 Frame 和超时后的恢复。本次还运行了 AddressSanitizer/UndefinedBehaviorSanitizer 检查。固件、golden/实测帧、结果和 PNG 预览归档于本地 `outputs/framebuffer-20261114-v1/`。

实际结果：22 项固件检查通过，两幅画面合计 960000/960000 像素一致，4 次请求对应 4 次 VSYNC 翻页，244629 次显存写入均为后台地址且整字使能，缓冲间及末尾哨兵保持不变。超时测试在有效扫描中令 `present(...,0)` 和 `begin(...,0)` 返回失败，再等待并重新获取缓冲恢复提交；最终结果 `0x600DFB00`，`main` 正常返回。

参考提交 `210313455329849aa7fc2d73eb6550c1abfb21d5` 提供 `start_v2.S` 的整屏背景/边框示例，其 `soc/` 与当前 HEAD 一致。这里借鉴 FB0 地址、800 B 行跨度和 32 位写入方式；用户已报告该参考版本 VGA 在实板验证通过。本版 C++ 驱动的结果以本次 SoC 运行日志为依据，实机验收单独记录。

显示接口事实见 [vga_fb.v](../soc/vga_fb.v) 和 [soc_top.v](../soc/soc_top.v)：FB0/FB1 的直接地址为 `0x1C400000` / `0x1C480000`，RGB332、800 字节行跨度；FB_CTRL bit0 提交，bit16 表示当前显示页。首次实现优先按 32 位打包四像素写入，并保持当前复位后的 uncached 存储属性。页面切换、按键驱动与完整游戏的测试应各有明确输入和结果记录。
=======
`Makefile` 后续增加完整固件、板级自检和镜像目标。PC 与 LA32R 构建分别选择一个平台后端；板级自检与游戏分别选择各自入口。编译器辅助函数按最终链接结果处理，按需链接匹配的 `libgcc`。文件名和职责按此规划推进，具体新增以实际依赖为准。

开发顺序：核心及 PC 验证（已完成）→ 统一硬件启动/地址契约 → 最小启动和 LED 自检 → 按键与显示驱动 → 手动游戏整机联调。AI 保持选做。
>>>>>>> 5f57701058e76b1bb6c4717c043f8e71cdb10eee

## 游戏核心算法

### 状态与初始化

`Game` 内保存 `uint32_t tiles[4][4]`、分数 `score`、有效步数 `moves`、胜利标记 `won` 和死局标记 `over`。`tiles[row][col] == 0` 表示空格。`init` 清零棋盘和计数/状态，再调用两次 `spawn` 生成初始方块。

### 四方向移动与合并

`move` 按方向提取四条线，每条线按“靠近移动目的端 → 远离目的端”排序：左/右为正序/逆序行，上/下为正序/逆序列。每条线共用如下处理：

1. 将非零数字按原顺序放进临时数组 `compact[4]`。
2. 从前往后扫描 `compact`：相邻同值时输出两倍数、累计合并得分并跳过两个输入；其他情况输出当前数字。
3. 输出数组尾部补零，再按方向映射写回棋盘。
4. 比较写回前后的数字，任意位置变化则返回 true，并将步数加一。

示例（向左）：

```text
[2,0,2,4] → 去零 [2,2,4] → 合并 [4,4] → 写回 [4,4,0,0]，增加 4 分
[2,2,2,2] → [4,4,0,0]，增加 8 分
[2,2,4,0] → [4,4,0,0]，增加 4 分
```

合并结果写入独立输出数组，扫描继续处理剩余输入，因此一个方块每步最多参与一次合并。每次移动处理 16 个格子，临时存储为两个长度 4 的数组；当前固定棋盘下的时间与空间开销均有固定上界。

### 随机生成与胜负

`spawn` 统计空位，通过随机回调选择一个空位，再用下一随机值选择 2 或 4，目标比例约 90% / 10%。使用取模映射，具有微小分布偏差。随机回调可替换为固定序列以复现测试。

合并产生 2048 时设置 `won`。`can_move` 检查空格和上下/左右相邻同值块；满盘且无相邻同值块时 `over=true`。主循环在有效移动后调用一次 `spawn`，并在生成后重新判断死局。无效移动保持棋盘、分数、步数和随机序列。

### 公共主循环

```text
init → render → read_event
                  ├─ 重开：init → render
                  ├─ 退出：main 返回
                  └─ 方向：本局进行中时 move
                             ├─ 有效移动：spawn → render
                             └─ 无效移动：render
```

胜利移动完成生成与绘制后冻结本局。胜负结束后继续接受重开和退出。

## 在 WSL 中运行

在仓库根目录执行（bash）：

```bash
make -C sw test
make -C sw play
# 可复现的开局与输入序列：
GAME2048_SEED=123 make -C sw play
```

WASD 或方向键即时移动，无需回车。进程结束时恢复终端配置。输入重定向也受支持，EOF 正常退出。重开继续使用当前随机数序列；重新启动进程并传入相同种子可重复开局。

构建目录默认是 `~/build/la32r/sw`；设置 `LA32R_BUILD` 后使用 `$LA32R_BUILD/sw`，也可传 `BUILD=/绝对路径`。源代码保留在 Windows 仓库，WSL 构建产物放在 ext4。

交叉编译检查（bash，仓库根目录）：

```bash
source requirements/env.sh
make -C sw cross-check
```

<<<<<<< HEAD
该目标编译核心和公共主循环为目标架构 `.o`，用于检查编译器及语言兼容性。启动代码和链接脚本已由最小 C++ 自检验证；完整游戏还需板级平台后端和程序加载验收。

### 生成 mycpu 目标编译产物

在仓库根目录执行（bash）：

```bash
source requirements/env.sh
make -C sw cross-artifacts
```

产物在 `${LA32R_BUILD:-$HOME/build/la32r}/sw/la32r/`（也可通过 `BUILD` 覆盖基础构建目录）：

| 文件 | 用途 |
| --- | --- |
| `game.o` / `main.o` | 游戏核心与公共主循环的 ELF32 LoongArch 可重定位对象 |
| `game.s` / `main.s` | 编译器输出的 LA32R 汇编源 |
| `game.dis` / `main.dis` | 对象文件反汇编，展示实际指令编码 |
| `libgame2048.a` | 只包含游戏核心的静态库 |
| `elf-headers.txt` | 目标架构、字节序和对象类型检查 |
| `undefined-symbols.txt` | 后续链接所需符号清单 |

明确采用 `-march=loongarch32r -mabi=ilp32s`、C++11、`-O2`、freestanding，关闭异常、RTTI、PIC/PIE 和栈保护。此阶段 `.o` 保留重定位，入口地址由后续固件链接设为 `0x1C000000`。核心对象已完成独立编译；主循环的游戏函数由核心提供，平台函数由板级后端提供，工具链产生的 GOT 等链接符号由最终链接器处理。完整固件生成时检查最终 ELF 的未解析符号、段布局和实际指令执行。

2026-11-14 本次导出的产物、源文件 SHA256、编译参数及验证说明存放在本地 `outputs/mycpu-la32r-20261114-v1/`，供查看和后续链接使用。此目录属于本地交付，协作源码仍在 `sw/`。
=======
该目标编译核心和公共主循环为目标架构 `.o`，用于检查编译器及语言兼容性。板上运行还需实现启动代码、链接脚本、板级平台后端、地址映射与程序加载，并完成 SoC 联调。
>>>>>>> 5f57701058e76b1bb6c4717c043f8e71cdb10eee

## LA32R 汇编、机器码与执行位置

本机 WSL 的宿主架构为 `x86_64`。普通 `g++` 生成在 WSL Linux 中运行的 PC 程序；`loongarch32r-linux-gnusf-g++` 生成供 LA32R CPU 执行的目标代码。WSL 在本项目中提供编译器、PC 测试和 RTL 仿真工具的运行环境。

| 阶段                       | 产物                        | 用途                             |
| -------------------------- | --------------------------- | -------------------------------- |
| 交叉编译 `-S`            | `game.la32r.s`            | 阅读目标汇编，核对手册及指令使用 |
| 交叉编译 `-c`            | `game.la32r.o` 等         | 可重定位机器码，供链接使用       |
| 链接启动、核心、平台及驱动 | `game.elf`（后续）        | 完整程序、地址和符号信息         |
| 镜像转换                   | `.bin` / `.mem`（后续） | 按板级加载或仿真方案选择格式     |
| CPU 执行                   | RTL 仿真 / FPGA             | CPU 取指运行游戏固件             |

生成核心汇编和反汇编（bash，在仓库根目录）：

```bash
source requirements/env.sh
sw_build="${LA32R_BUILD:-$HOME/build/la32r}/sw"
mkdir -p "$sw_build"
"${CROSS}g++" -std=c++11 -O2 -march=loongarch32r -mabi=ilp32s \
  -ffreestanding -fno-exceptions -fno-rtti \
  -S sw/app/game.cpp -o "$sw_build/game.la32r.s"
make -C sw cross-check
"${CROSS}objdump" -d -C "$sw_build/game.la32r.o" > "$sw_build/game.la32r.dis"
```

当前工具链默认目标经检查为 `loongarch32r`、ABI `ilp32s`，FPU 为 `none`。生成的指令可对照 [龙芯架构32位精简版参考手册](../docs/龙芯架构32位精简版参考手册.pdf) 阅读。目标对象编译通过后，还需在实际 CPU 上验证指令实现与执行结果。汇编源通常由编译器内部调用汇编器生成对象；日常构建可直接从 C++ 生成 `.o`。

<<<<<<< HEAD
在 WSL 中执行 `make -C sw play` 可运行当前 PC 版。目标 LA32R 固件的执行方式为：WSL 启动完整 SoC 的 Verilator 等仿真程序，由仿真的 LA32R CPU 执行固件；或将程序加载到 FPGA 系统，由板上 CPU 执行。选用指令集模拟器时，还要核对其 LA32R、ABI 与板级外设支持。当前 SoC 已通过汇编与最小 C++ 自检；完整游戏固件、板级驱动及板上加载仍待实现和验证。

### 当前启动和地址约定（2026-11-14 更新）

当前 `if_stage.v` 使复位后首条取指地址为 `0x1C000000`；新增 `soc_bus.v` 已实现 BaseRAM `0x1C000000` 和 ExtRAM `0x1C400000` 的译码，并兼容旧设计中的 `0x80000000` / `0xA0000000` 别名。现有 `sim/soc/prog/link.ld` 已将汇编自检链接在 `0x1C000000`。

当前启动层、按键及 RGB332/双缓冲驱动均已完成对应整机测试。下一步由 LA32R 平台后端连接现有驱动与游戏主循环。MMIO 基址为 `0xBFD00000`，FB0/FB1 使用直接地址 `0x1C400000` / `0x1C480000`。cache 属性依据 CPU 模式及 CSR/DMW/TLB 配置确定。完整资源表和最新验证状态见 [SoC README](../soc/README.md)。
=======
在 WSL 中执行 `make -C sw play` 可运行当前 PC 版。目标 LA32R 固件的执行方式为：WSL 启动完整 SoC 的 Verilator 等仿真程序，由仿真的 LA32R CPU 执行固件；或将程序加载到 FPGA 系统，由板上 CPU 执行。选用指令集模拟器时，还要核对其 LA32R、ABI 与板级外设支持。项目当前仍需补齐完整固件及 SoC 接入。

### 下一步先统一启动和地址约定

当前 `soc/cpu/open-la500/if_stage.v` 将复位 PC 设置为 `0x1BFFFFFC`，使下一取指地址为 `0x1C000000`；`docs/design.md` 的启动方案给出 `0x80000000`。下一步应结合 CPU 复位/地址转换、BaseRAM 译码和实际加载方式统一入口地址，再实现 `crt0.S` 与 `link.ld`，先跑通最小 LED 自检。随后接入输入、帧缓冲和游戏。该项会影响程序能否取到第一条指令。
>>>>>>> 5f57701058e76b1bb6c4717c043f8e71cdb10eee

文件职责、规则算法、测试及移植步骤见 [软件实现说明](../docs/2048-software.md)。

## 开源参考

规则实现参考 [plibither8/2048.cpp](https://github.com/plibither8/2048.cpp) 的 `src/gameboard.cpp`（2026-11-14 查阅 master）。本项目采用固定数组和统一四方向处理，平台依赖由 `hal` 提供。上游 MIT 版权及许可全文保存在 [2048.cpp.LICENSE](third_party/2048.cpp.LICENSE)。
