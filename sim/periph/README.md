# confreg 自检（sim/periph）

对 `soc/confreg.v` 的单元测试，纯 SystemVerilog + Verilator，不需要交叉工具链。

```bash
make            # 编译并运行
make lint       # Verilator -Wall
make clean
```

## 覆盖项

| 项 | 验证内容 |
| --- | --- |
| STEP | 写入 → `LED[4:0]`、数码管十位/个位 BCD 解码；4000 → 饱和 3199 |
| STATUS | `[15:13]`/`[12:5]` → LED 直连映射 |
| 字节使能 | 部分写只改使能字节，其余保持 |
| BTN | 两级同步 + 边沿检测 + 读后清零（长按只算一次） |
| KEY | 拨码开关电平 |
| TIME | 50 MHz / 50000 = 1 kHz，100000 拍涨 2 ms |
| RAND | 自由计数，连续两次读不同 |
| FB_CTRL | 写 1 置位 → `vsync_start` 原子翻转并清 0；整字写不覆盖 bit[16] |

## 总线接口约定

- `req_addr` 是**字节偏移**（0x00/04/08/0C/10/14/18）
- 单拍请求，`req_ready` 恒为 1，下一拍 `rsp_valid` 给数据
- **固定 2 拍应答由上层总线桥补齐**（本模块只占 1 拍），与 `docs/design.md` 2.2.3 一致

## 与视频侧的接口

`confreg.fb_sel` → `vga_fb.fb_sel`；`vga_fb.vsync_start` → `confreg.vsync_start`。
在 `vsync_start` 到来且 `FB_CTRL[0]` 挂起时，`fb_sel` 原子翻转并清请求位。
