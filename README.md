# LA32R-SoC

## 目录总览

```
.
├── README.md
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
| `sw/boot/` | `crt0.S` 启动、`.bss` 清零、链接脚本 |
| `sw/libc/` | `memcpy` / `memset` / `printf` 等最小实现（仅整数） |
| `sw/drv/` | `confreg`、帧缓冲绘制、输入层、字模 |
| `sw/hal/` | `platform.h` 统一接口 + 目标板后端 + PC 模拟后端 |
| `sw/app/` | 2048 规则内核、界面绘制、Expectimax AI、主循环 |
| `ref/` | PC 端 oracle、行移动表生成器、一致性回归脚本 |
| `tools/` | 构建入口、烧写脚本、验证脚本 |
