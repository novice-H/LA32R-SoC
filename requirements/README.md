# LA32R 工具链与 Verilator 仿真环境搭建指南

> 面向**从没装过开发环境的 Linux**。照着本文可以从零跑通：
> 装系统依赖 → 配交叉工具链 → 编译 C → 生成 FPGA 镜像 → Verilator 仿真。

本文所有命令均在以下环境实测通过：

| 项目 | 实测值 |
| --- | --- |
| 系统 | Ubuntu 24.04.4 LTS (x86_64) |
| 主机 GCC | 13.3.0 |
| Verilator | 5.020 (2024-01-01) |
| GTKWave | 3.3.116 |
| 交叉工具链 | loongarch32r-linux-gnusf GCC 8.3.0 |

---

## 0. 适用范围

| 你的情况 | 能不能用本文 |
| --- | --- |
| Ubuntu 22.04 / 24.04、Debian 12 | ✅ 直接照做 |
| Fedora / Arch | ✅ 见 2.2 节对应命令 |
| Windows | ⚠️ 请先装 **WSL2 + Ubuntu 24.04**，在 WSL 里照做 |
| macOS（尤其 Apple Silicon） | ❌ 工具链是 Linux **x86_64** 的 ELF 可执行文件，需 Docker/虚拟机套一层 |

**为什么必须是 x86_64 Linux**：`requirements/` 里的 `gcc`/`ld` 等是 x86_64 Linux 二进制，
在 ARM 或 macOS 上无法直接执行。

预计耗时：10 分钟（不含下载）。

---

## 1. 三步跑起来（TL;DR）

```bash
cd LA32R-SoC

# 1) 装系统依赖（会调用 sudo）
bash requirements/setup-deps.sh

# 2) 把交叉工具链压缩包放到 requirements/ 下并解压（见第 3 节）

# 3) 配置环境并验证
source requirements/env.sh
make -C requirements/verilator-smoke      # 应输出 q = 10
```

---

## 2. 安装系统依赖

### 2.1 一键脚本（推荐）

```bash
bash requirements/setup-deps.sh          # 安装并检查
bash requirements/setup-deps.sh --check  # 只检查，不安装
```

脚本会自动识别 `apt` / `dnf` / `pacman` / `zypper`，安装依赖后逐项检查版本并给出结论。

### 2.2 手动安装

**Ubuntu / Debian**

```bash
sudo apt update
sudo apt install -y build-essential git python3 ca-certificates verilator gtkwave
```

**Fedora**

```bash
sudo dnf install -y gcc gcc-c++ make git python3 verilator gtkwave
```

**Arch**

```bash
sudo pacman -S --needed base-devel git python verilator gtkwave
```

### 2.3 检查版本

```bash
verilator --version    # 需要 >= 5.0（Ubuntu 24.04 是 5.020）
gtkwave --version
gcc --version          # 主机编译器，用于编译 Verilator 生成的 C++
```

各发行版自带版本参考：

| 发行版 | verilator | 说明 |
| --- | --- | --- |
| Ubuntu 24.04 | 5.020 | ✅ 够用 |
| Debian 12 | 5.006 | ✅ 够用 |
| Ubuntu 22.04 | 4.038 | ⚠️ 低于 5.0，部分 SV 特性不可用，建议按下节源码编译 |
| Ubuntu 20.04 | 4.028 | ⚠️ 同上，建议升级系统或源码编译 |

### 2.4 Verilator 低于 5.0 时：源码编译

```bash
sudo apt install -y autoconf flex bison help2man

# GitHub 直连慢时用 gh-proxy 前缀（把 URL 包一层）
git clone --depth 1 --branch v5.020 \
    https://gh-proxy.com/https://github.com/verilator/verilator.git
cd verilator
autoconf
./configure --prefix="$HOME/.local/verilator"
make -j"$(nproc)"
make install

export PATH="$HOME/.local/verilator/bin:$PATH"   # 建议写进 ~/.bashrc
verilator --version
```

### 2.5 每个依赖是干什么的

| 软件包 | 作用 |
| --- | --- |
| `build-essential` / `g++` / `make` | Verilator 把 Verilog 转换成 C++ 后需要主机编译器编译 |
| `git` | 拉取仓库、拉取 Verilator 源码 |
| `python3` | 把 `.bin` 转成 32 位字 `.mem`（见 6.2 节） |
| `verilator` | 把 SystemVerilog 编译为高速 C++ 仿真 |
| `gtkwave` | 查看 VCD/FST 波形 |

---

## 3. 获取交叉编译工具链

工具链约 **286 MB / 3956 个文件**，**不随仓库分发**（避免仓库膨胀），需要单独获取。

### 3.1 从队内共享位置取得

从队内共享盘 / 群文件拿到 `loongarch32r-linux-gnusf-2022-05-20.tar.gz`，然后：

```bash
cd requirements
tar xzf loongarch32r-linux-gnusf-2022-05-20.tar.gz
```

也可以直接把整个目录拷到 `requirements/` 下。

> **目录名必须保持 `loongarch32r-linux-gnusf-2022-05-20`**，`env.sh` 和 Makefile 模板都依赖它。

### 3.2 校验

```bash
requirements/loongarch32r-linux-gnusf-2022-05-20/bin/loongarch32r-linux-gnusf-gcc --version
# 期望：loongarch32r-linux-gnusf-gcc (GCC) 8.3.0
```

### 3.3 重要：它是可重定位的，不需要装到 /opt

网上的同类龙芯工具链通常硬编码 `/opt/...`，但这一份按**自身所在路径**查找
`lib` / `libexec` / `sysroot`，放在仓库里就能直接用，**不需要 root**。

验证：

```bash
requirements/loongarch32r-linux-gnusf-2022-05-20/bin/loongarch32r-linux-gnusf-gcc -print-search-dirs
# 输出的路径应该指向 requirements/... 而不是 /opt/...
```

### 3.4 目录结构

```
loongarch32r-linux-gnusf-2022-05-20/
├── bin/       # 交叉工具：gcc / g++ / as / ld / objcopy / objdump / readelf ...
├── lib/       # 编译器运行时（libgcc）
├── libexec/   # cc1 / cc1plus / lto1 等编译器后端
├── include/   # 主机侧头文件
├── sysroot/   # 目标侧根目录：glibc 2.28 的头文件与 lib32 库
└── share/     # 文档 / locale
```

`bin/` 共 28 个工具，**没有 `gdb`**，调试请用 `objdump` 反汇编或 Verilator 仿真。

---

## 4. 配置环境变量

### 4.1 用现成脚本（推荐）

```bash
source requirements/env.sh
```

脚本会按自身位置推导路径（换机器、换目录都不用改），把工具链加入 `PATH`，并导出 `CROSS` 前缀。

### 4.2 手动（效果等价）

```bash
export LA32_ROOT="$PWD/requirements/loongarch32r-linux-gnusf-2022-05-20"
export PATH="$LA32_ROOT/bin:$PATH"
export CROSS=loongarch32r-linux-gnusf-
```

### 4.3 让它长期生效

写进 `~/.bashrc`：

```bash
echo 'source '"$PWD"'/requirements/env.sh' >> ~/.bashrc
```

### 4.4 校验清单

| 命令 | 期望输出 |
| --- | --- |
| `loongarch32r-linux-gnusf-gcc --version` | GCC 8.3.0 |
| `loongarch32r-linux-gnusf-gcc -dumpmachine` | `loongarch32r-linux-gnusf` |
| `loongarch32r-linux-gnusf-as --version` | GNU assembler 2.31.1 |
| `verilator --version` | Verilator 5.x |

或者直接跑 `bash requirements/setup-deps.sh --check`，一次检查全部。

---

## 5. 第一次编译

### 5.1 Linux 用户态程序（默认：动态链接）

适合在主机侧验证算法，但 **SoC 上没有 Linux 和动态链接器，不能直接跑**。

```bash
cat > t.c <<'EOF'
int add(int a, int b) { return a + b; }
int main(void) { return add(1, 2); }
EOF

loongarch32r-linux-gnusf-gcc -O2 t.c -o t
file t
# t: ELF 32-bit LSB executable, LoongArch, dynamically linked, interpreter /lib32/ld.so.1
```

需要不依赖动态链接器时加 `-static`。

### 5.2 裸机程序（SoC 实际使用，**必须这样编**）

裸机没有 libc、没有启动代码，需要：

1. `-nostdlib -nostartfiles` —— 不链接 libc / crt
2. 自己的启动汇编 `crt0.S` —— 设置栈指针、跳转到 `main`
3. 链接脚本 `link.ld` —— 规定代码起始地址与内存布局

完整示例（起始地址按 `soc/` 实际映射修改）：

```asm
/* crt0.S */
    .section .text.start
    .globl _start
_start:
    la.local $sp, _stack_top
    bl main
1:  b 1b
```

```ld
/* link.ld */
ENTRY(_start)
SECTIONS {
  . = 0x80000000;
  .text   : { *(.text.start) *(.text*) }
  .rodata : { *(.rodata*) }
  .data   : { *(.data*) }
  .bss    : { *(.bss*) }
  . = ALIGN(16);
  _stack_top = . + 0x4000;
}
```

```c
// main.c
int main(void) { volatile int s = 0; for (int i = 0; i < 10; i++) s += i; return s; }
```

```bash
loongarch32r-linux-gnusf-gcc -O2 -nostdlib -nostartfiles \
    -T link.ld crt0.S main.c -o app.elf

loongarch32r-linux-gnusf-objdump -d app.elf | head -20
```

实测反汇编（可作为工具链正常的标志）：

```
80000000 <_start>:
80000000:  1c000083  pcaddu12i  $r3, 4(0x4)
80000004:  02824063  addi.w     $r3, $r3, 144(0x90)
80000008:  54000800  bl         8(0x8)   # 80000010 <main>
8000000c:  50000000  b          0        # 8000000c <_start+0xc>
```

### 5.3 常用 binutils 命令

| 命令 | 用途 |
| --- | --- |
| `...-objdump -d app.elf` | 反汇编 |
| `...-objdump -d -S app.elf` | 反汇编 + 源码（需 `-g`） |
| `...-readelf -h app.elf` | ELF 头（确认 LoongArch / 小端 / 32 位） |
| `...-readelf -l app.elf` | 段布局（核对加载地址） |
| `...-size app.elf` | 各段大小 |
| `...-nm -n app.elf` | 按地址排序的符号表 |
| `...-objcopy -O binary/ihex/verilog` | 格式转换（见第 6 节） |
| `...-strip app.elf` | 去符号 |

---

## 6. 导出 FPGA 可加载的镜像

### 6.1 支持的格式

| 用途 | 命令 | 产物 |
| --- | --- | --- |
| 通用二进制 | `objcopy -O binary app.elf app.bin` | 纯二进制，无地址信息 |
| Intel HEX | `objcopy -O ihex app.elf app.hex` | 带地址的文本 |
| Verilog 十六进制 | `objcopy -O verilog app.elf app.v` | `@地址` + **按字节**的十六进制 |
| 32 位字 mem（推荐给 `$readmemh`） | 见 6.2 | 每行一个 32 位字 |

### 6.2 `.bin` → 32 位字 `.mem`（小端）

`objcopy -O verilog` 是**按字节**输出（每行 16 字节、地址是字节地址），直接喂给 32 位宽
存储器会错位。给 `soc/` 用请转成小端 32 位字：

```bash
loongarch32r-linux-gnusf-objcopy -O binary app.elf app.bin

python3 -c "
d = open('app.bin','rb').read()
for i in range(0, len(d), 4):
    w = (d[i:i+4] + b'\x00'*4)[:4]
    print(w[::-1].hex())
" > app.mem
```

Verilator 读入验证（实测 `word0=1c000083`，与反汇编一致）：

```systemverilog
initial $readmemh("app.mem", mem);
```

---

## 7. Verilator 仿真

### 7.1 模板位置

```
requirements/verilator-smoke/
├── counter.sv     # DUT：参数化计数器（8 位，带使能与异步复位）
├── tb_main.cpp    # C++ testbench：驱动时钟、断言 q==10、可选导出波形
├── Makefile       # 一键编译/运行/波形
└── obj_dir/       # 生成物（make clean 可删）
```

### 7.2 一键运行

```bash
cd requirements/verilator-smoke
make          # 编译并运行
make lint     # 只做语法与告警检查（-Wall）
make trace    # 带波形编译并运行，生成 counter.vcd
make wave     # 用 GTKWave 打开波形
make clean    # 清理 obj_dir 与波形
```

应输出：

```
after 10 enabled cycles, q = 10 (expect 10)
```

第一次运行约 2 秒（含编译）。

### 7.3 关键坑：`--binary` 与自定义 testbench 冲突

`verilator --binary` 会**自带一个 main 函数**。若同时提供含 `main` 的 C++ testbench，链接会报：

```
multiple definition of `main'; tb_main.o: ... first defined here
```

对照表：

| 场景 | 正确命令 |
| --- | --- |
| 纯 SystemVerilog testbench（无 C++ 文件） | `verilator --binary --top-module tb tb.sv dut.sv` |
| 自定义 C++ testbench（本模板） | `verilator --cc --exe --build --top-module dut dut.sv tb.cpp` |

### 7.4 波形

**C++ testbench**（本模板已实现，`VM_TRACE` 宏控制）：

```cpp
Verilated::traceEverOn(true);
VerilatedVcdC* tfp = new VerilatedVcdC;
dut->trace(tfp, 99);
tfp->open("counter.vcd");
// 每次 eval 之后：
tfp->dump(time += 5);
// 结束：
tfp->close();
```

**纯 SV testbench**：

```systemverilog
initial begin
  $dumpfile("tb.vcd");
  $dumpvars(0, tb);
end
```

两者都必须在命令行加 `--trace`（或 `--trace-fst`）重新编译，否则 dump 是空操作。

GTKWave：`make wave` 打开后，左侧选中 `TOP`，把 `clk`/`rst_n`/`q` 拖到波形区，
`Ctrl+Shift+F` 适配窗口，滚轮缩放到边沿看时序。

### 7.5 与 SoC 对接

完整链路：**C 源码 → ELF → 32 位字 mem → `$readmemh` → Verilator 加载 → 观察 PC / 写信号**。

```bash
# 1) 交叉编译
loongarch32r-linux-gnusf-gcc -O2 -nostdlib -nostartfiles -T link.ld \
    crt0.S main.c -o app.elf

# 2) 转为 32 位字 mem（同 6.2 节）
```

testbench 骨架：

```systemverilog
module soc_tb;
  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;              // 100 MHz

  reg [31:0] imem [0:65535];
  reg [31:0] dmem [0:65535];

  initial begin
    $readmemh("app.mem", imem);      // 指令存储器
    #20 rst_n = 1;                   // 释放复位
    #100000 $finish;                 // 超时保护
  end

  soc_top u_soc (.clk(clk), .rst_n(rst_n), /* ... */);

  // 可选：打印写回 / 访存，便于定位
  always @(posedge clk) if (u_soc.we) $display("mem[%h] <= %h", u_soc.addr, u_soc.wdata);
endmodule
```

编译运行（无 C++ 文件，所以用 `--binary`）：

```bash
verilator --binary --trace -Wno-fatal -O2 --top-module soc_tb \
    soc_tb.sv soc_top.v soc/*.v -o soc_sim
./obj_dir/soc_sim
gtkwave dump.vcd
```

建议在 `sim/` 里按此组织：`sim/tb/` 放 testbench、`sim/Makefile` 封装编译运行、
`sim/out/` 放产物（`out/` 已在 `.gitignore` 中忽略）。

### 7.6 常用参数速查

| 参数 | 说明 |
| --- | --- |
| `--cc --exe --build` | 生成 C++ 模型 + 可执行文件并编译（自定义 tb） |
| `--binary` | 生成自带 main 的可执行文件（纯 SV tb） |
| `--trace` / `--trace-fst` / `--trace-vcd` | 打开波形支持（FST 更省空间） |
| `--timing` | 支持 `#delay` 等延时语句（否则被忽略） |
| `-Wall` | 打开全部告警；`-Wno-fatal` 让警告不中断 |
| `-O0/-O2/-O3` | 仿真优化等级；调试用 `-O0` |
| `-j 0` | 用全部 CPU 核并行编译 |
| `--assert` | 支持 SVA 断言 |
| `--coverage` | 行/翻转覆盖率统计 |
| `-CFLAGS` / `-LDFLAGS` | 透传给 C++ 编译器 / 链接器 |

---

## 8. 常见问题 FAQ

**Q1：`loongarch32r-linux-gnusf-gcc: command not found`**
没 `source requirements/env.sh`，或工具链没解压到 `requirements/` 下。
用 `bash requirements/setup-deps.sh --check` 定位。

**Q2：`multiple definition of 'main'`**
`--binary` 与自定义 C++ testbench 冲突，见 7.3。

**Q3：Verilator 报 `--timing` 不支持 / SV 语法错误**
版本低于 5.0，见 2.4 源码编译。

**Q4：产物 `dynamically linked, interpreter /lib32/ld.so.1`，SoC 跑不了**
默认链接了 glibc，裸机必须加 `-nostdlib -nostartfiles`，见 5.2。

**Q5：`Permission denied` 执行 `build/` 下的程序**
某些挂载点带 `noexec`（如部分 U 盘/网络盘），把工程放到 `$HOME` 下。

**Q6：`git clone` GitHub 很慢**
```bash
git clone https://gh-proxy.com/https://github.com/用户/仓库.git
```

**Q7：Verilator 编译时报缺 `python3` / `perl`**
补装：`sudo apt install python3 perl`。

**Q8：GTKWave 在 Wayland 下打不开**
先设 `GDK_BACKEND=x11 gtkwave x.vcd`。

**Q9：Windows 拷过来的文件报 `bash^M`**
换行符问题：`sed -i 's/\r$//' 文件`，建议 git 配 `core.autocrlf=input`。

---

## 9. 附录

### 9.1 编译选项速查

| 选项 | 说明 |
| --- | --- |
| `-march=loongarch32r` | 指令集（默认） |
| `-mabi=ilp32s` | 32 位 ABI + 软浮点（默认） |
| `-msoft-float` | 软件浮点（默认，无硬件 FPU） |
| `-mstrict-align` | 严格对齐，禁止非对齐访存（默认） |
| `-O0/-O1/-O2/-Os` | 优化等级；调试用 `-O0 -g` |
| `-nostdlib -nostartfiles` | **裸机必加** |
| `-T <script>` | 指定链接脚本 |
| `-ffreestanding` | 表明无宿主环境（裸机建议加） |
| `-fno-builtin` | 禁用内建函数（自己的 libc 场景） |
| `-ffunction-sections` + `-Wl,--gc-sections` | 裁剪未用代码，缩小镜像 |

### 9.2 Makefile 模板

```makefile
LA32_ROOT := $(CURDIR)/requirements/loongarch32r-linux-gnusf-2022-05-20
CROSS     := $(LA32_ROOT)/bin/loongarch32r-linux-gnusf-
CC        := $(CROSS)gcc
OBJCOPY   := $(CROSS)objcopy
OBJDUMP   := $(CROSS)objdump

CFLAGS  := -O2 -ffreestanding -fno-builtin -nostdlib -nostartfiles \
           -ffunction-sections -fdata-sections -Wall
LDFLAGS := -T link.ld -Wl,--gc-sections

SRCS := crt0.S main.c
TARGET := app

all: $(TARGET).elf $(TARGET).bin

$(TARGET).elf: $(SRCS) link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRCS) -o $@

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

dis: $(TARGET).elf
	$(OBJDUMP) -d -S $< | less

clean:
	rm -f $(TARGET).elf $(TARGET).bin $(TARGET).mem

.PHONY: all dis clean
```

### 9.3 本目录文件清单

```
requirements/
├── README.md                              # 本文件
├── env.sh                                 # source 后配置 PATH
├── setup-deps.sh                          # 安装/检查系统依赖
├── loongarch32r-linux-gnusf-2022-05-20/   # 交叉工具链（286 MB，不进 git）
└── verilator-smoke/                       # Verilator 仿真模板
```

### 9.4 关于版本管理与协作

工具链体积大（286 MB / 3956 个文件），**不要提交进 git**。仓库的 `.gitignore` 已加好：

```gitignore
# 大体积交叉工具链，队友按第 3 节自行放置
requirements/loongarch32r-linux-gnusf-*/
# Verilator 生成物
requirements/verilator-smoke/obj_dir/
requirements/verilator-smoke/*.vcd
```

因此仓库里只有 `README.md`、`env.sh`、`setup-deps.sh` 和 `verilator-smoke/`（模板源码），
队友按第 3 节把工具链放到 `requirements/` 下即可。

### 9.5 环境已知的约束

1. **没有 newlib、没有 gdb**：`printf`、`memcpy`、`memset` 需自己实现（对应 `sw/libc/`）；
   浮点运算调用 `libgcc` 的软件模拟例程，性能低。
2. **严格对齐**：结构体与 `memcpy` 实现注意 4 字节对齐。
3. **起始地址**：`link.ld` 的 `0x80000000` 只是示例，必须与 `soc/` 指令存储器映射、
   `thinpad_top.v` 一致（见 `docs/design.md` 的地址映射一节）。
4. **`$readmemh` 字宽**：32 位存储器必须用 32 位字格式（6.2 节）。
5. 目录名统一为 `requirements`（全拼），脚本与文档中均使用该名称。
