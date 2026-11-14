# 全系统仿真（sim/soc）

CPU + AXI 桥 + 总线译码 + 两片 SRAM + confreg + VGA 的整机仿真。

```bash
make        # 编译启动程序 + 编译 Verilator 模型 + 运行
make prog   # 只编译启动程序（build/soc/prog.hex）
make lint   # Verilator -Wall
make clean
make wave   # 生成 build/soc/soc.vcd（程序跑完即停，不采整帧）
make run-v2 # 跑 v2 冒烟程序（整屏填充 + 边框）
```

波形用 `gtkwave build/soc/soc.vcd` 打开：可看 CPU 的 AXI 读写握手、总线 2 拍应答、
两片 SRAM 的 CE/OE/WE、VGA 的 de/hsync/vsync 与 RGB。

一次运行约 20 秒编译 + 1 秒仿真，最终打印 `RESULT: PASS`。

## 结构

```
core_top (openLA500, AXI3)
    │
    ▼
soc/bus/axi_slave_wrap.v   ← 参考桥（队友正式桥到位后替换这个文件）
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

> **注意**：openLA500 的复位 PC 固定在 `0x1C00_0000`，所以代码必须链接到这里；
> `0x8000_0000`/`0xA000_0000` 只是别名，方便沿用原设计文档。

## AXI 桥接口契约（队友的正式桥按这个接）

模块名 `axi_slave_wrap`，文件 `soc/bus/axi_slave_ref.v` 是参考实现：

| 侧 | 信号 |
| --- | --- |
| AXI3 从设备 | `arid/araddr/arlen/arsize/arburst/arvalid/arready`、`rid/rdata/rresp/rlast/rvalid/rready`、`awid/awaddr/awlen/awsize/awburst/awvalid/awready`、`wid/wdata/wstrb/wlast/wvalid/wready`、`bid/bresp/bvalid/bready` |
| 简单总线主设备 | `m_addr[31:0]`（字节地址）、`m_req_valid/m_req_ready`、`m_we/m_be_n/m_wdata`、`m_rsp_valid/m_rsp_rdata` |

约定：

1. 总线**固定 2 拍应答**（`soc_bus` 已实现），桥不要自己做等待状态；
2. `m_addr` 是字节地址，`soc_bus` 负责译码与字地址转换；
3. 当前 CPU 只发 32 位访问（`arsize=2`），参考桥未处理窄传输；
4. 读数据按拍返回、`rlast` 标最后一拍；写响应在最后一个 W 拍之后给一次 B。

替换方式：把正式桥写成 **同名模块 `axi_slave_wrap`**（或改 `soc/soc_top.v` 的例化），
其余文件不用动。

## 启动程序

| 版本 | 源文件 | 上板 bin | 内容 |
| --- | --- | --- | --- |
| v1 | `prog/start.S` | `build/soc/start.bin` | 顶行粉 + 第 1 行 4 像素红（其余区域是 ExtRAM 上电随机值） |
| v2 | `prog/start_v2.S` | `build/soc/start_v2.bin` | 整屏填蓝 + 粉色顶边 + 白色底边/左右列（整屏干净） |

`prog/start.S`：链接在 `0x1C00_0000`，无栈、无 TLB：

1. `STEP = 1234` → LED[4:0]=12、数码管 34
2. FB0 第 0 行填 `0xEFEFEFEF`（品红）
3. FB0 第 200 字填 `0xE0E0E0E0`（红）
4. `STATUS[13] = 1`（WIN 标志，仿真据此判定程序跑完）

### 工具链坑（重要）

本仓库默认的 **2022-05-20 工具链**会把伪指令 `bnez` 编成 **0x13 操作码**，而
openLA500 只实现最终 LA32R 的 `bne`（0x17）——`bnez` 会被译成非法指令，PC 跳到
`EENTRY=0` 死循环。**汇编里请写 `bne $rj, $r0, label`**，不要用 `bnez`。

> 如果升级到 README 里的 LA32 v2.0 工具链（Git LFS），该问题应消失，但需另行验证。

## 判定标准

- `STATUS[13]` 在超时前置 1（程序跑完）
- `STEP=1234` → `LED[4:0]=12`、数码管 33/34 段码正确
- 采一整帧 VGA：`(0,0)`/`(3,0)` 为 `0xEF`，`(0,1)`/`(3,1)` 为 `0xE0`，`(4,1)` 为 0
- 无 `RESULT: FAIL`

## 后续

1. 队友正式 AXI 桥到位后替换 `axi_slave_ref.v`，跑同一套仿真
2. 把 `thinpad_top.v` 改成对 `soc_top` 的封装（接 PLL/复位/未用引脚）
3. 加 `crt0.S`（栈、`.bss` 清零、DMW/TLB 配置）与真正的 2048 软件
