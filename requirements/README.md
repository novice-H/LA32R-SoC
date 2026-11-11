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
| 交叉工具链 | loongarch32r-linux-gnusf GCC 8.3.0（**LA32 v2.0 / 2023-09-03**，见 3.0 节） |

> ### ⚠️ 版本变更：仓库里的工具链已换版（2026-11-11）
>
> 本文**初版**是按队内共享的 `loongarch32r-linux-gnusf-2022-05-20.tar.gz`（286 MB / 3956 文件）写的；
> 现在仓库通过 **Git LFS** 分发的是 **`loongarch32r-linux-gnusf-2.0.tar.gz`（LA32 v2.0 / 2023-09-03，112 MB）**。
> 两者 **gcc 主版本相同（8.3.0）**，但**目录结构、体积、附带组件都不同**，而且现版本**自带 `gdb`**。
> 按旧文档操作过的同学请先看 **3.0 节对照表**再动手，不要再去共享盘找 `-2022-05-20` 那个包。

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

# 2) 从 Git LFS 拉取工具链并解压（见第 3 节）

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
sudo apt install -y build-essential git git-lfs python3 ca-certificates verilator gtkwave
```

**Fedora**

```bash
sudo dnf install -y gcc gcc-c++ make git git-lfs python3 verilator gtkwave
```

**Arch**

```bash
sudo pacman -S --needed base-devel git git-lfs python verilator gtkwave
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
| `git-lfs` | 拉取存放在 LFS 里的交叉工具链压缩包 |
| `python3` | 把 `.bin` 转成 32 位字 `.mem`（见 6.2 节） |
| `verilator` | 把 SystemVerilog 编译为高速 C++ 仿真 |
| `gtkwave` | 查看 VCD/FST 波形 |

---

## 3. 获取交叉编译工具链

压缩包约 **112 MB**（解开 305 MB / 4000 个文件），存放在 **Git LFS** 里，跟仓库一起拉取，
不需要再找队友要文件。

> **注意：这份包与本文初版描述的 `-2022-05-20` 版不是同一个版本，先看 3.0 节对齐。**

### 3.0 版本变更说明（必读）

本文初版描述的包，和仓库现在分发的包**不是同一版本**。对齐版本请以本表为准：

| 对比项 | 旧版（README 初版 / 队内共享盘） | 现版本（仓库 Git LFS） |
| --- | --- | --- |
| 压缩包 | `loongarch32r-linux-gnusf-2022-05-20.tar.gz` | **`loongarch32r-linux-gnusf-2.0.tar.gz`** |
| 厂商版本 | 2022-05-20 | **LA32 v2.0（2023-09-03）** |
| 体积 | 286 MB / 3956 个文件 | 112 MB（gz）/ 305 MB / 4000+ 个文件（解开） |
| 获取方式 | 队内共享盘 / 群文件 | `git lfs pull` + `tar xzf`（3.1 节） |
| 解压后顶层 | `loongarch32r-linux-gnusf-2022-05-20/`，`bin/` 直接在顶层 | `loongarch32r-linux-gnusf-2.0/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/`，**多套一层** |
| gcc | 8.3.0 | 8.3.0（相同） |
| binutils | 2.31.1 | 2.31.1（相同） |
| glibc（sysroot） | 2.28 | 2.28（相同） |
| gdb | **不含** | **含** `loongarch32r-linux-gnusf-gdb` 8.1.50 |
| 目标侧根目录 | `sysroot/` | `loongarch32r-linux-gnusf/sysroot/` |
| 宿主端工具数 | 28 个 | 30 个 |
| 附加组件 | 无 | `picolibc/`（内含 `picolibc.tar.gz`） |
| 是否进 Git | 否（共享盘分发） | 是，**存 Git LFS**（单个 tarball） |

**对使用者的实际影响**

1. **编译命令不用改**：工具链前缀仍是 `loongarch32r-linux-gnusf-`，gcc / binutils / glibc 版本号与旧版一致，
   第 5 节的编译方式、第 9.1 节的选项速查、第 9.2 节的 Makefile 模板继续适用。
2. **路径要改**：`bin/` 多套了一层 `loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/`。
   除非你手上有写死旧路径的脚本，否则**直接用 `source requirements/env.sh`**（自动探测，见 3.1 节）。
3. **自带 gdb 了**：旧文档"没有 gdb"的说法作废（9.5 节已更正）；但 SoC 上没有调试代理，
   实际仍以 `objdump` 反汇编 / Verilator 仿真为主。
4. **别新旧混用**：本地若还留着 `loongarch32r-linux-gnusf-2022-05-20/`，建议删除。
   仓库里新旧目录都被 `.gitignore` 忽略（`requirements/loongarch32r-linux-gnusf*/`），不影响提交。

> 遇到与本文不一致的现象时，**以工具实际输出为准**：
> `source requirements/env.sh` 后跑 `loongarch32r-linux-gnusf-gcc --version`、
> `"$LA32_ROOT/bin/loongarch32r-linux-gnusf-gcc" -print-search-dirs`、`cat "$LA32_ROOT/versions"`，
> 并把结果补进本文，方便下一个人对齐。

### 3.1 从 Git LFS 拉取并解压

```bash
# 每台机器装一次 LFS 客户端并启用（Ubuntu：sudo apt install git-lfs）
git lfs install

cd LA32R-SoC
git lfs pull      # 只下载 LFS 对象；普通 clone 不会自动拉全量 LFS 内容
tar xzf requirements/loongarch32r-linux-gnusf-2.0.tar.gz -C requirements/
```

解压得到 `requirements/loongarch32r-linux-gnusf-2.0/`，保持厂商原始结构：

```
loongarch32r-linux-gnusf-2.0/
├── loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/
└── picolibc/
```

> `env.sh` / `setup-deps.sh` 会自动搜索 `requirements/loongarch32r-linux-gnusf*/` 及其下一层
> 子目录里的 `bin/loongarch32r-linux-gnusf-gcc`，目录名或套几层都不影响使用。

压缩包里 `bin/`、`libexec/` 下文件权限为 `0755`，解压后直接可执行
（Windows 没有可执行位，所以分发的是保留权限的 tarball，而不是展开目录，原因见 9.4）。

### 3.2 校验

```bash
source requirements/env.sh
loongarch32r-linux-gnusf-gcc --version
# 期望：loongarch32r-linux-gnusf-gcc (GCC) 8.3.0
```

### 3.3 重要：它是可重定位的，不需要装到 /opt

网上的同类龙芯工具链通常硬编码 `/opt/...`，但这一份按**自身所在路径**查找
`lib` / `libexec` / `sysroot`，放在仓库里就能直接用，**不需要 root**。

验证（`source requirements/env.sh` 之后 `$LA32_ROOT` 指向工具链根目录）：

```bash
"$LA32_ROOT/bin/loongarch32r-linux-gnusf-gcc" -print-search-dirs
# 输出的路径应该指向 requirements/... 而不是 /opt/...
```

### 3.4 目录结构

```
loongarch32r-linux-gnusf-2.0/
└── loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/
    ├── bin/         # 30 个主机端交叉工具：gcc / g++ / as / ld / gdb / objcopy ...
    ├── lib/         # 编译器运行时（libgcc）
    ├── lib64/       # 主机端 64 位运行时
    ├── libexec/     # cc1 / cc1plus / lto1 等编译器后端
    ├── include/     # 主机侧头文件
    ├── loongarch32r-linux-gnusf/
    │   ├── bin/     # 目标侧工具（ar / as / ld ...）
    │   ├── lib/ lib32/
    │   └── sysroot/ # 目标根目录：glibc 2.28 的头文件与 lib32 库
    ├── share/       # 文档 / locale / gdb
    └── versions     # 版本清单（gcc 8.3.0 / binutils 2.31.1 / glibc 2.28 / gdb 8.1.50）
```

本版本（LA32 v2.0，2023-09-03）**自带 `gdb`**（`loongarch32r-linux-gnusf-gdb`），
也可以照旧用 `objdump` 反汇编或 Verilator 仿真调试。
旧版（`-2022-05-20`，本文初版描述的包）**不含 gdb**、且 `bin/` 直接在顶层——两者别混用，详见 3.0。

---

## 4. 配置环境变量

### 4.1 用现成脚本（推荐）

```bash
source requirements/env.sh
```

脚本会按自身位置推导路径（换机器、换目录都不用改），把工具链加入 `PATH`，并导出 `CROSS` 前缀。

### 4.2 手动（效果等价）

```bash
# 注意：$LA32_ROOT 必须指向真正含 bin/ 的那一层目录
export LA32_ROOT="$PWD/requirements/loongarch32r-linux-gnusf-2.0/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0"
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

> **Windows 上生成 `.mem` 要注意换行**：`print` 重定向会写出 CRLF，`$readmemh` 可能解析错。
> 用 `python3 ... | tr -d '\r' > app.mem`，或直接 `open('app.mem','w',newline='\n')` 写入。
> 详见 `AGENTS.md` 第 8 节。

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
没 `source requirements/env.sh`，或没执行 `git lfs pull` / 没解压 tarball（见第 3 节）。
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
换行符问题。仓库已在 `.gitattributes` 里把 `*.sh` 固定为 `eol=lf`，正常 clone 不会再出问题；
本地旧文件修一次即可：`sed -i 's/\r$//' requirements/*.sh`（或把 `core.autocrlf` 设为 `input`）。

**Q10：找不到 `loongarch32r-linux-gnusf-2022-05-20`，或版本/路径对不上**
本文初版描述的是队内共享盘上的旧包；仓库现在通过 Git LFS 分发的是
**LA32 v2.0（2023-09-03）** 的 `loongarch32r-linux-gnusf-2.0.tar.gz`，目录结构也不同。
**以 3.0 节对照表为准**，不要再去找 `-2022-05-20` 那个包。

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
# 指向真正含 bin/ 的那一层目录；也可用 make LA32_ROOT=... 覆盖
LA32_ROOT ?= $(CURDIR)/requirements/loongarch32r-linux-gnusf-2.0/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0
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
├── README.md                                # 本文件
├── env.sh                                   # source 后配置 PATH
├── setup-deps.sh                            # 安装/检查系统依赖
├── loongarch32r-linux-gnusf-2.0.tar.gz      # 交叉工具链（112 MB，存 Git LFS）
├── loongarch32r-linux-gnusf-2.0/            # 解压产物（305 MB，被 .gitignore 忽略）
└── verilator-smoke/                         # Verilator 仿真模板
```

### 9.4 关于版本管理与协作

工具链解开有 305 MB / 4000 个文件，**绝不直接提交目录**，而是打成保留权限的
`loongarch32r-linux-gnusf-2.0.tar.gz`（112 MB）提交到 **Git LFS**：

```gitattributes
requirements/*.tar.gz  filter=lfs diff=lfs merge=lfs -text
```

```gitignore
# 解压出来的工具链目录不进 git（压缩包本身走 LFS）
requirements/loongarch32r-linux-gnusf*/
# Verilator 生成物
requirements/verilator-smoke/obj_dir/
requirements/verilator-smoke/*.vcd
```

仓库里因此只有压缩包 + `README.md` / `env.sh` / `setup-deps.sh` / `verilator-smoke/`。
队友 `git lfs pull` 后按 3.1 解压即可。

**为什么发 tarball 而不是展开目录**

| 直接提交展开目录 | 提交 tarball（当前做法） |
| --- | --- |
| 4000+ 个 LFS 对象，clone / pull 慢、请求多 | 1 个 LFS 对象 |
| Windows 无文件可执行位（`core.filemode=false`），gcc / ld 会以 `100644` 入库，Linux 上拉下来**没有执行权限**，还得 `chmod` | 权限固化在归档内，解压即用 |
| 305 MB | 112 MB |

维护者更新 / 更换工具链版本：

```bash
git lfs track "requirements/*.tar.gz"      # 只需首次执行
git add requirements/loongarch32r-linux-gnusf-2.0.tar.gz
git commit -m "chore(requirements): 更新交叉工具链"
git push
```

换版本时**必须同步更新本文**，至少改以下几处，否则队友会对齐不上：

1. 文首的实测环境表 + 版本变更提示块；
2. **3.0 版本变更对照表**（新旧包名、体积、目录结构、组件差异）；
3. 3.1 的 `tar xzf` 文件名、3.4 的目录结构；
4. 9.6 变更记录追加一行。

`env.sh` / `setup-deps.sh` 会按 `requirements/loongarch32r-linux-gnusf*/` 自动探测 `bin/`，
**换版本不必改脚本**（仅当新包结构与上述两种布局都不同时才需要动）。

### 9.5 环境已知的约束

1. **没有 newlib**：`printf`、`memcpy`、`memset` 需自己实现（对应 `sw/libc/`）；
   浮点运算调用 `libgcc` 的软件模拟例程，性能低。现版本（v2.0）自带 gdb
   （`loongarch32r-linux-gnusf-gdb`，旧版 2022-05-20 则没有），但 SoC 上没有调试代理，
   实际仍以 `objdump` 反汇编 / Verilator 仿真定位为主。
2. **严格对齐**：结构体与 `memcpy` 实现注意 4 字节对齐。
3. **起始地址**：`link.ld` 的 `0x80000000` 只是示例，必须与 `soc/` 指令存储器映射、
   `thinpad_top.v` 一致（见 `docs/design.md` 的地址映射一节）。
4. **`$readmemh` 字宽**：32 位存储器必须用 32 位字格式（6.2 节）。
5. 目录名统一为 `requirements`（全拼），脚本与文档中均使用该名称。

### 9.6 文档与工具链变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-11-11 | 工具链切到 **LA32 v2.0（2023-09-03）**，打包为 `loongarch32r-linux-gnusf-2.0.tar.gz`（112 MB）改由 **Git LFS** 分发；`env.sh` / `setup-deps.sh` 改为自动定位工具链、新增 `git-lfs` 检查；新增 3.0 版本对照节；更正目录结构、体积、`gdb` 有无等与旧版不一致的描述 |
| 初版 | 依据队内共享的 `loongarch32r-linux-gnusf-2022-05-20.tar.gz`（286 MB / 3956 文件，无 gdb）编写 |
