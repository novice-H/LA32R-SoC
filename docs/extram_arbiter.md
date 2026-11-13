# ExtRAM 地址仲裁器

`soc/extram_arbiter.v` 将 LA32R CPU 的自定义主机接口和 VGA/DVI 的读接口接到同一片 32 位 ExtRAM。

## 接口约定

CPU 使用 `cpu_addr/cpu_wdata/cpu_wstrb/cpu_req/cpu_we` 发起单字读写。`cpu_addr` 是字节地址，模块将 `0xA000_0000` 转换为 ExtRAM 字地址：

```text
ext_word_addr = (cpu_addr - 0xA000_0000) >> 2
```

VGA 使用 `vga_addr/vga_req` 发起读请求，`vga_rdata` 在请求后一拍更新，`vga_rvalid` 同时拉高一拍。当前 `soc/vga_fb.v` 的请求会在每四个有效像素时出现一次，因此仲裁器保证 VGA 单拍请求被接收。

## 仲裁规则

仲裁器只有一个 ExtRAM 活动事务。空闲时优先接受 VGA 请求；CPU 请求在没有 VGA 请求时接受。CPU 事务完成的同一拍可以直接接收新的 VGA 请求，所以连续视频读取不会出现额外空拍。CPU 请求保持到 `cpu_ack`，仲裁器用内部锁存位防止同一请求被重复接受。

## ExtRAM 控制信号

- `ext_ram_ce_n`：有事务时拉低。
- `ext_ram_oe_n`：读事务时拉低。
- `ext_ram_we_n`：CPU 写事务时拉低。
- `ext_ram_be_n`：低有效，写周期使用 `~cpu_wstrb`。
- `ext_ram_data`：只在 CPU 写周期驱动，读周期保持高阻。

## 仿真

```bash
iverilog -g2012 -s tb_extram_arbiter -o build/extram_arbiter.vvp \
    soc/extram_arbiter.v sim/tb_extram_arbiter.v
vvp build/extram_arbiter.vvp
```

仿真覆盖 CPU 全字写读、VGA 与 CPU 同拍请求时 VGA 优先，以及字节使能部分写。
