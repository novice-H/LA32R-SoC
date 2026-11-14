# openLA500 启用 Cache 加速的原理

> 结论：openLA500 复位后处于 **DA（直接地址）模式**，所有取指/访存都绕过 Cache，
> 每次只做一个字的 AXI 传输。把 CRMD 切到 **PG 模式**，再用两个 **DMW 窗口**
> 分别映射 RAM（可缓存）和 MMIO（不可缓存），即可打开 I/D-Cache。
> AI 单步实测从 **11,168,440 拍降到 1,409,794 拍（7.9×）**。

## 1. 为什么复位后很慢

openLA500 复位时 `csr.v` 把 CRMD 置为：

| 字段 | 复位值 | 含义 |
| --- | --- | --- |
| `DA` | 1 | 直接地址模式（VA = PA） |
| `PG` | 0 | 不做页表/DMW 映射 |
| `DATF` / `DATM` | 0 | 取指/数据都按"直接模式不缓存" |

RTL 中的判定（`if_stage.v`）：

```verilog
assign da_mode = csr_da && !csr_pg;
assign inst_uncache_en = (da_mode && (csr_datf == 2'b0)) ||
                         (dmw0_en && (csr_dmw0[`DMW_MAT] == 2'b0)) || ...
```

所以 `DA=1` 时取指 `inst_uncache_en=1`，**I-Cache 完全不参与**。
抓 AXI 波形可以看到 `arlen=0`——每条指令都单独发一次单字读，而不是 cache 行填充。
每次取指要经过 AXI 桥 → 总线译码 → SRAM 控制器（固定 2 拍应答），
一条指令大约 6–10 拍，这就是 AI 搜索慢的根源。

## 2. LoongArch 的两种地址模式

- **DA 模式**：`VA = PA`，不查 TLB/DMW，按 DATF/DATM 决定不使用 Cache。
- **PG 模式**：先查 DMW 窗口（命中则做段映射），否则查 TLB；
  最终由 MAT（Memory Access Type）决定是否可缓存。

DMW 寄存器位域（`csr.h`）：

| 位 | 字段 | 说明 |
| --- | --- | --- |
| 0 | `PLV0` | PLV0 可访问 |
| 3 | `PLV3` | PLV3 可访问 |
| 5:4 | `DMW_MAT` | 00 = 不缓存，非 0 = 可缓存（我们用 01） |
| 27:25 | `PSEG` | 物理段（对应 PA[31:29]） |
| 31:29 | `VSEG` | 虚拟段（对应 VA[31:29]） |

CRMD 位域（`csr.h`）：

| 位 | 字段 |
| --- | --- |
| 1:0 | `PLV` |
| 2 | `IE` |
| 3 | `DA` |
| 4 | `PG` |
| 6:5 | `DATF` |
| 8:7 | `DATM` |

## 3. 我们实际写入的配置

实现见 [`sw/boot/cache_enable.S`](../sw/boot/cache_enable.S)：

| CSR | 编号 | 值 | 作用 |
| --- | --- | --- | --- |
| `DMW0` | `0x180` | `0x0000_0011` | VSEG=0 → PSEG=0，**MAT=01 可缓存**，PLV0 |
| `DMW1` | `0x181` | `0xAA00_0001` | VSEG=5 → PSEG=5，**MAT=00 不可缓存**，PLV0 |
| `CRMD` | `0x0` | `0x0000_0010` | **PG=1、DA=0** |

```asm
li.w  $r4, 0x00000011
csrwr $r4, 0x180          /* DMW0：RAM 可缓存 */
li.w  $r4, 0xaa000001
csrwr $r4, 0x181          /* DMW1：confreg/ExtRAM 别名不可缓存 */
li.w  $r4, 0x00000010
csrwr $r4, 0x0            /* CRMD：PG=1, DA=0 */
ibar  0
```

为什么是这两个窗口：

| 地址 | VA[31:29] | 走哪个窗口 | 结果 |
| --- | --- | --- | --- |
| `0x1C00_0000` 代码 / `0x1C40_0000` 栈 | 0 | DMW0 | PA 不变，**可缓存** |
| `0xBFD0_0000` confreg | 5 | DMW1 | PA 不变，**不可缓存** |
| `0xA000_0000` ExtRAM 别名 | 5 | DMW1 | PA 不变，**不可缓存** |

> 注意：物理帧缓冲 `0x1C40_0000` 也在段 0，会走 DMW0 变成可缓存。
> 所以软件绘图改用 `0xA000_0000` / `0xA008_0000` 别名（DMW1，不缓存），
> VGA 才能立即读到新像素。见第 6 节。

## 4. RTL 里"是否缓存"的完整判定

取指（`if_stage.v`）：

```verilog
assign dmw0_en = ((csr_dmw0[`PLV0] && csr_plv == 2'd0) || ...)
                 && (fs_pc[31:29] == csr_dmw0[`VSEG]) && pg_mode;
assign inst_uncache_en = (da_mode && (csr_datf == 2'b0)) ||
                         (dmw0_en && (csr_dmw0[`DMW_MAT] == 2'b0)) ||
                         (dmw1_en && (csr_dmw1[`DMW_MAT] == 2'b0)) ||
                         (inst_addr_trans_en && (inst_tlb_mat == 2'b0)) ||
                         disable_cache;
```

访存（`mem_stage.v`）同理：`data_uncache_en` 由 DA/DATF、DMW 的 MAT、TLB 的 MAT
共同决定。

因此：

- **PG 模式 + DMW 命中 + MAT=1** → 访问走 Cache；
- **PG 模式 + DMW 命中 + MAT=0** → 仍然不缓存（MMIO 用）；
- `disable_cache` CSR 也可以全局关掉缓存（调试用，默认 0）。

## 5. 打开 Cache 后为什么快

openLA500 的 I/D-Cache 是 **2 路 × 256 组 × 16 B/行 = 8 KB**（每个 Cache）：

- 一次 cache miss 填充 16 B，即 **一次 AXI 事务拿 4 个指令字**，而不是 4 次单字读；
- 命中后取指基本 1 拍级，D-Cache 命中同样省掉总线往返；
- AI 搜索代码只有十几 KB，热路径能驻留 I-Cache，收益特别大。

实测（AI 固定中局、1000 节点预算、50 MHz）：

| 项 | DA（无 cache） | PG+DMW（开 cache） |
| --- | --- | --- |
| 周期数 | 11,168,440 | **1,409,794** |
| 每节点 | ~11,170 拍 | **~1,410 拍** |
| 单步耗时 | 0.22 s | **0.028 s** |
| 10k 节点/步 | ~2.2 s | **~0.28 s** |

加速 **7.9×**。对 2048 游戏：AI 每步从约 1 s 降到约 0.28 s（预算同时从 3000 提到 10000）。

## 6. Cache 一致性：什么时候不能缓存

D-Cache 是**写回（write-back）**的：CPU 写入可能只落在 Cache 里，没到 SRAM。
因此凡是"别的 master 也要读"的内存，必须用不可缓存路径：

| 场景 | 做法 |
| --- | --- |
| VGA 读帧缓冲 | 用 `0xA000_0000` / `0xA008_0000` 别名（DMW1，MAT=0） |
| confreg（BTN 读清、TIME、RAND） | 走 DMW1（MAT=0），绝不能缓存 |
| 仿真里的 `game_snapshot` | BaseRAM 可缓存，测试台从 RAM 模型读会读到旧值 → **仿真构建默认 `GAME_CACHE=0`** |
| 自己写的共享内存 | 写完做 `cacop` 写回/失效，或放到不可缓存别名 |

这也解释了为什么仿真测试默认不开 cache，而上板固件可以开：
上板时没有测试台去读 `game_snapshot`，帧缓冲又已经改走不可缓存别名。

## 7. 怎么用

固件构建时加 `GAME_CACHE=1`：

```bash
make -C sw firmware GAME_SEED=0 GAME_CACHE=1 GAME_DIR=build/sw/game-cache
```

`main.cpp` 会在最前面调用 `boot_enable_caches()`，并把 AI 预算从 3000 提到 10000。
裸机程序也可以直接调用：

```cpp
extern "C" void boot_enable_caches(void);
boot_enable_caches();
```

需要临时回到无 cache（调试/共享内存）时：

```cpp
extern "C" void boot_disable_caches(void);
boot_disable_caches();
```

> 注意：`boot_disable_caches()` 之后，之前留在 D-Cache 里的脏数据不会自动写回；
> 如果要保证内存一致，应先做 cache 写回，或把共享数据放在不可缓存窗口。

## 8. 已知限制

1. Cache 只有 8 KB/路，代码或数据工作集超过后会明显掉命中率；
2. 写回策略要求软件显式处理共享内存（见第 6 节）；
3. 打开 cache 是**纯软件 CSR 配置**，不需要改 RTL 或重新综合 bit；
4. 若实机出现黑屏/卡死，先回退无 cache 固件，再检查 DMW/CRMD 配置。

## 9. 参考

- `soc/cpu/open-la500/csr.h`：DMW/CRMD 位域定义
- `soc/cpu/open-la500/if_stage.v`：`inst_uncache_en`、`dmw0_en`
- `soc/cpu/open-la500/mem_stage.v`：`data_uncache_en`
- `soc/cpu/open-la500/csr.v`：DMW0/DMW1 的 CSR 编号（0x180/0x181）
- `sw/boot/cache_enable.S`：本项目的开关实现
- [`docs/ai-feasibility.md`](ai-feasibility.md)：完整的性能实测与优化过程
