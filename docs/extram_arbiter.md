# ExtRAM 仲裁器（`soc/mem/ext_ram_arbiter.v`）

> 本文按**仓库当前采用**的实现编写。
> `origin/extram-arbiter` 分支上的单模块版本（`soc/extram_arbiter.v`）接口与本实现不兼容，
> 已由本方案取代；该分支可删除。

## 结构

```
CPU 请求（简单总线，字地址）──┐
                             ├── ext_ram_arbiter ── ext_ram_ctrl ── 异步 SRAM 引脚
VGA / DVI 读请求（2 拍延迟）──┘
```

- `ext_ram_arbiter`：只做仲裁与响应路由；
- `ext_ram_ctrl`：异步 SRAM 控制器（`soc/mem/sram_ctrl.v` 的封装），50 MHz 下 1 拍访问、
  2 拍返回（发地址 → 访问窗口 → 响应）。

## 接口

| 侧 | 信号 | 说明 |
| --- | --- | --- |
| DVI | `dvi_req` | 单拍读请求 |
| | `dvi_next` | **提前一拍**预告 `dvi_req`，给仲裁器挡 CPU 用 |
| | `dvi_addr[19:0]` | ExtRAM **字地址** |
| | `dvi_ready` | 当拍授予（DVI 请求零等待） |
| | `dvi_rdata[31:0]` / `dvi_rsp_valid` | 请求后 2 拍返回；数据保持到下一次响应 |
| CPU | `cpu_req/cpu_ready` | 单拍握手；未授予时保持 `req` |
| | `cpu_addr[19:0]` | ExtRAM **字地址**（字节地址由总线译码器转换） |
| | `cpu_we/cpu_be_n/cpu_wdata` | 写控制，`be_n` 低有效 |
| | `cpu_rsp_valid/cpu_rsp_rdata` | 请求后 2 拍返回（读给数据，写给完成脉冲） |
| 控制器 | `mem_*` | 与 `ext_ram_ctrl` 直连 |

## 仲裁规则

1. **DVI 绝对优先**：`dvi_req` 当拍即授予，保证数据正好落在像素组开头；
2. **提前一拍挡 CPU**：`dvi_next` 为 1 的拍以及 `dvi_req` 拍都不授予 CPU，
   否则 CPU 事务会把控制器占住、导致 DVI 晚一拍；
3. **CPU 带宽**：每 4 个像素最多拿到 1 个空闲拍（约 25%）；未授予时 CPU 保持 `req` 即可；
4. **数据保持**：`dvi_rdata` 在响应当拍透传、其余时刻保持，CPU 响应插在像素组中间
   也不会改写正在扫描的字；
5. 同一时刻只有一个在途事务；响应按顺序回到对应主机。

## 仿真

```bash
# 集成验证（真实链路 + CPU 噪声争用 + VGA 采帧）
make -C sim/vga flip DUT="vga/dut_vga_fb.v ../soc/vga_fb.v"

# 仲裁器单元测试（CPU 读写 / 字节使能 / DVI 优先级、零丢弃、2 拍响应）
make -C sim/mem arb
```

实测指标：

| 项 | 结果 |
| --- | --- |
| DVI 请求/响应 | 480001 / 480001（集成）、零丢弃、零延迟错误 |
| CPU 争用读回 | 0 错误（约 70 万次授权） |
| 单元测试 DVI | 零丢弃、2 拍响应、数据正确 |
| 画面 | 两帧各 480000/480000 像素一致 |
