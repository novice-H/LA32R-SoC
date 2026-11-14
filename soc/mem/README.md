# SRAM 控制器（soc/mem）

从 `loongsoncup2026-229ms-191.7MHz` 工程移植的板级异步 SRAM 控制器，用于给 2048 项目的
BaseRAM / ExtRAM 引脚提供可综合的访问时序。

参考实现（只读，不在本仓库）：

```
/media/zai-linux/Data/Desktop/FPGA/loongsoncup2026-229ms-191.7MHz/
  loongsoncup2026-229ms-191.7MHz/src/soc/
    thinpad_top.v   # 板级顶层
    CPU.sv          # CPU 顶层，直接带 RAM 引脚
    LSU.sv          # 地址域路由：BaseRAM / ExtRAM / UART
    BSE.sv          # BaseRAM 封装
    EXT.sv          # ExtRAM 封装（内含 EXT_CACHE）
    RAM.sv          # 共享的异步 SRAM 控制器
    EXT_CACHE.sv    # ExtRAM 写直达缓存（未移植）
```

---

## 1. 原设计里 BaseRAM/ExtRAM 是怎么接到 CPU 的

**`thinpad_top` 本身没有控制器**，它只是把板级引脚直连到 `CPU`：

```verilog
CPU u_CPU (
    .base_ram_data (base_ram_data), .base_ram_addr(base_ram_addr),
    .base_ram_be_n (base_ram_be_n), .base_ram_ce_n (base_ram_ce_n),
    .base_ram_oe_n (base_ram_oe_n), .base_ram_we_n (base_ram_we_n),
    .ext_ram_data  (ext_ram_data),  .ext_ram_addr (ext_ram_addr),
    ...
);
```

控制器在 CPU 内部，分三层：

```
thinpad_top                    板级引脚
    │  base_ram_* / ext_ram_*
    ▼
  CPU.sv                       顶层，直接持有两组 RAM 引脚
    │
    ▼
  LSU.sv                       地址域路由（含 IFU 取指 + XIU 访存两路）
    │  addr[24:22] 选域，addr[21:2] 是 4MB 内字地址
    ├── BSE.sv  ──► RAM.sv ──► base_ram_*    （纯控制器）
    ├── EXT.sv  ──► EXT_CACHE.sv ──► RAM.sv ──► ext_ram_*  （写直达缓存 + 控制器）
    └── URT.sv  ─────────────────────────────► 串口
```

原工程的地址域（`CFG.svh`）：

| 域 | 基址 | addr[24:22] |
| --- | --- | --- |
| BaseRAM（代码/数据） | `0x1C00_0000` | `3'b000` |
| ExtRAM | `0x1C40_0000` | `3'b001` |
| UART | `0x1F00_0000` | `3'b111` |

> 注意：这是该 CPU 自己的内存映射，和 2048 项目的 `0x8000_0000 / 0xA000_0000`
> 不同。**地址译码不属于控制器**，移植后由总线桥负责。

`BSE` 与 `EXT` 都只是薄封装：`BSE` 直接例化一个 `RAM`；`EXT` 例化 `EXT_CACHE` +
另一个 `RAM`。所以两片 SRAM 各有一个独立的控制器状态机，互不争用。

## 2. 异步 SRAM 的物理时序（原 `RAM.sv` 的实质）

板载 SRAM 是**异步器件**，没有时钟输入，靠控制信号电平完成访问：

| 信号 | 方向 | 说明 |
| --- | --- | --- |
| `addr[19:0]` | out | **字地址**（4 字节对齐） |
| `data[31:0]` | inout | 读时由 SRAM 驱动，写时由 FPGA 驱动，其余高阻 |
| `ce_n` | out | 片选，低有效 |
| `oe_n` | out | 输出使能（读），低有效 |
| `we_n` | out | 写使能，低有效 |
| `be_n[3:0]` | out | 字节使能，低有效（0 = 该字节参与） |

原设计的访问窗口按频率换算：

```systemverilog
RAM_CYC = ceil(CLK_FREQ / RAM_FREQ)   // 193 MHz / 67 MHz = 3 拍
```

- **读**：`CE_n=0, OE_n=0, WE_n=1`，维持 `RAM_CYC` 拍，在窗口最后一拍的时钟沿采样 `data`
- **写**：`CE_n=0, OE_n=1, WE_n=0`，`data` + `be_n` 在窗口内保持稳定
- 所有控制寄存器都标了 `(* iob = "true" *)`，让地址/控制直接落到 IOB，减少抖动

此外原控制器还有 2 项与 CPU 强相关的逻辑：**IFU/XIU 双请求端口 + 2 项 hold buffer**
和 **投机取消（cancel）**。这些属于 LSU 的取指/访存调度，不是 SRAM 协议本身。

---

## 3. 移植后的实现

| 文件 | 作用 |
| --- | --- |
| `sram_ctrl.v` | 异步 SRAM 控制器内核：单请求 valid/ready + 读数据/写完成 |
| `base_ram_ctrl.v` | BaseRAM 封装，引脚名与 `thinpad_top.v` 的 `base_ram_*` 一致 |
| `ext_ram_ctrl.v` | ExtRAM 封装，引脚名与 `ext_ram_*` 一致 |

### 3.1 接口

```verilog
sram_ctrl #(.CLK_FREQ(50_000_000), .RAM_FREQ(67_000_000)) u_ctrl (
    .clk, .rst,
    // 请求
    .req_valid, .req_ready,
    .req_addr,            // 20 位字地址
    .req_we,              // 1=写
    .req_be_n,            // 低有效字节使能
    .req_wdata,
    // 响应（读给数据，写给完成脉冲）
    .rsp_valid, .rsp_rdata,
    // 引脚
    .ram_data, .ram_addr, .ram_be_n, .ram_ce_n, .ram_oe_n, .ram_we_n
);
```

`RAM_CYC` 由参数自动算出，不需要手改：

| CLK_FREQ | RAM_FREQ | RAM_CYC |
| --- | --- | --- |
| 50 MHz（本工程系统时钟） | 67 MHz | **1** |
| 193 MHz（原工程） | 67 MHz | 3 |

### 3.2 与原实现的对应关系

| 原设计 | 移植后 | 说明 |
| --- | --- | --- |
| `RAM.sv` 的引脚时序 | `sram_ctrl.v` | 保留 IOB 寄存器、CE/OE/WE/BE 语义、`RAM_CYC` 参数 |
| `RAM.sv` 的 IFU/XIU 双端口 | — | 由上层总线桥提供单请求流 |
| hold buffer / cancel | — | 属于 LSU 调度，不属于 SRAM 协议 |
| `BSE.sv` | `base_ram_ctrl.v` | 引脚名保持 `base_ram_*` |
| `EXT.sv` + `EXT_CACHE.sv` | `ext_ram_ctrl.v` | **未移植缓存**，原因见下 |
| 读数据的字节选择/符号扩展 | — | 改为返回原始 32 位字，由总线桥处理 |

### 3.3 为什么没移植 EXT_CACHE

原工程在 ExtRAM 前挂了一个"写直达、无写分配"的缓存。本项目不采用：

1. openLA500 自带 dcache，再叠一层外部缓存收益低、路径长；
2. 帧缓冲写入须按明确的存储属性/一致性方案让 DVI 扫描器读到最新像素。当前直接地址为
   `0x1C400000`，`0xA0000000` 是总线译码兼容别名；cache 属性由 CPU CSR/DMW/TLB 配置决定；
3. 少一层缓存 = 少一份一致性验证负担。

如果后续确实需要，可以把 `EXT_CACHE.sv` 接在总线桥与本控制器之间，接口不变。

---

## 4. 当前 SoC 接入（2026-11-14 更新）

控制器提供板级 SRAM 时序；地址译码和仲裁分别由 `soc_bus`、`ext_ram_arbiter` 提供。当前 `thinpad_top → soc_top` 已接入以下链路：

```
openLA500 (AXI3)
      │
      ▼
axi_slave_wrap ──► soc_bus ──┬──► base_ram_ctrl ──► BaseRAM 引脚
                            ├──► ext_ram_arbiter ──► ext_ram_ctrl ──► ExtRAM 引脚
                            └──► confreg       ▲
vga_fb ───────────────────────────────────────┘
```

对接时注意：

1. `req_addr` 是**字地址**：`byte_addr[21:2]`，不要直接给字节地址；
2. 读返回原始 32 位字，CPU 访存单元完成字节/半字提取和符号扩展；当前参考 AXI 从桥的窄传输支持需专项验证；
3. 写用 `be_n` 掩码，未使能字节保持不变；
4. ExtRAM 有 CPU 与 DVI 两个读/写主，仲裁后只让一个进控制器；
5. `CLK_FREQ` 填实际系统频率（2048 是 50 MHz），`RAM_CYC` 会自动变成 1。

当前采用 `bus/axi_slave_ref.v` 中的 `axi_slave_wrap`。地址映射及最新整机验证记录见 [SoC README](../README.md) 和 [sim/soc/README.md](../../sim/soc/README.md)。

---

## 5. 自检仿真

```bash
make -C sim/mem        # 编译并运行
make -C sim/mem lint   # Verilator -Wall 检查
```

覆盖：

- `RAM_CYC=1`（50 MHz）读写、初始值、字节使能
- `RAM_CYC=3`（193 MHz）读写，并**逐事务检查 `CE_n` 低电平拍数**（1 拍 / 3 拍）
- BaseRAM 与 ExtRAM 两个实例互相独立
- 上电不产生"幽灵写"（`SIMU` 下的 initial 保护，原设计同款）

输出 `RESULT: PASS` 即通过。

---

## 6. ExtRAM 仲裁器（`ext_ram_arbiter.v`）

ExtRAM 有两个主机：CPU（读写）和 DVI（每 4 像素读 1 字）。控制器是单口的，
所以两者之间需要一个仲裁器。

### 6.1 端口

```verilog
ext_ram_arbiter u_arb (
    .clk, .rst,
    // DVI 侧
    .dvi_req, .dvi_next, .dvi_addr, .dvi_ready, .dvi_rdata, .dvi_rsp_valid,
    // CPU 侧
    .cpu_req, .cpu_addr, .cpu_we, .cpu_be_n, .cpu_wdata,
    .cpu_ready, .cpu_rsp_rdata, .cpu_rsp_valid,
    // 控制器侧
    .mem_req, .mem_addr, .mem_we, .mem_be_n, .mem_wdata,
    .mem_ready, .mem_rsp_valid, .mem_rsp_rdata
);
```

### 6.2 仲裁策略

- **DVI 绝对优先**：`dvi_req` 当拍即授予，保证响应 2 拍后正好落在像素组开头；
- **提前一拍预警**：`dvi_next` 是 `dvi_req` 的前一拍；CPU 在 `dvi_next` 和 `dvi_req`
  这两拍都不许启动，否则会把控制器占住、让 DVI 晚一拍拿到数据；
- **CPU 结果**：每 4 个像素最多拿到 1 个空闲拍（约 25% 带宽），足够刷 2048 的静态棋盘；
  请求通过 `cpu_ready` 单拍握手，未授予时保持 `req` 即可；
- **数据保持**：`dvi_rdata` 是"响应当拍透传、其余保持"的寄存器输出，CPU 的响应即使插在
  像素组中间，也不会改写 DVI 正在扫描的那个字。

### 6.3 已验证的指标

`sim/vga` 用真实链路（`vga_fb + 仲裁器 + 控制器 + 异步 SRAM`）+ CPU 噪声主机验证：

- DVI 请求 480001 次，全部授权，0 次被丢，0 次延迟错误；
- CPU 噪声 70 万次授权，读写校验 0 错误；
- 两帧画面 100% 匹配预期。

> 注意：仲裁器假设 `fb_sel` 翻页发生在消隐区（confreg 在 `vsync_start` 翻转），
> 与 `docs/design.md` 2.2.7.3 的约定一致。
