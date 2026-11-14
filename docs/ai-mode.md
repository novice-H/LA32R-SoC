# 2048 AI 模式接入说明

AI 模式层（`sw/app/ai_mode.{h,cpp}`）把现有 `Game` 与 `ai` 搜索粘在一起，
**不需要改 `main.cpp`、`platform_la32r.cpp` 或任何驱动**；板级后端只要在游戏循环里
加一个分支。

## 分层

```
Game（2/4/... 数值棋盘）  ←→  ai_mode（换算 + 模式/预算）  ←→  ai（2 的指数棋盘 + expectimax）
```

`ai_mode` 不分配内存、不调用 libc、无浮点，可在裸机/PC 两侧使用。

## 接口（`sw/app/ai_mode.h`）

| 函数 | 说明 |
| --- | --- |
| `set_mode(Mode)` / `mode()` / `toggle()` | 手动 / AI 模式切换 |
| `set_node_budget(int)` / `node_budget()` | 每步搜索节点预算，默认 10000 |
| `set_max_depth(int)` / `max_depth()` | 迭代加深上限，默认 8 |
| `last_nodes()` | 最近一步实际展开的节点数（可显示/统计） |
| `board_from_game(game, out[16])` | `Game` 数值棋盘 → AI 指数棋盘 |
| `choose_direction(game, &nodes)` | 只选方向，不落子；返回 0=上 1=右 2=下 3=左，-1=无路 |
| `step(game, random, ctx, &nodes)` | 选方向 + `move` + `spawn` + `refresh_status`，返回是否走成功 |

## 板级集成（`platform_la32r.cpp` 里加分支）

```cpp
#include "../app/ai_mode.h"

// 模式来源：板级 KEY1（confreg 的 kAiEnable = bit1）
const bool want_ai = platform::ai_mode_requested();
ai_mode::set_mode(want_ai ? ai_mode::Mode::AI : ai_mode::Mode::Manual);

// 主循环
const platform::Event e = platform::read_event();   // 必须是轮询，不能阻塞
if (e == platform::Event::Quit) return 0;
if (e == platform::Event::Restart) {
    game2048::init(game, platform::random_u32, nullptr);
    platform::render(game);
    continue;
}
if (game.won || game.over) continue;

if (ai_mode::mode() == ai_mode::Mode::AI) {
    uint64_t nodes = 0;
    if (ai_mode::step(game, platform::random_u32, nullptr, &nodes)) {
        platform::render(game);       // 每步刷新一次，0.28 s/步 可接受
    }
} else {
    // 原有手动事件处理
}
```

要点：

1. **AI 模式下 `read_event()` 仍要调用**，用于处理 Restart/Quit；板级的
   `read_event()` 必须是非阻塞轮询。
2. 胜负判断沿用 `game.won` / `game.over`，`step()` 内部会 `refresh_status`。
3. 模式切换用 **KEY1**（`confreg::kAiEnable`，bit1）；KEY0 仍是游戏使能/暂停。
4. `board_render` 会把 `STATUS.AI`（bit15）置位，对应 **LED[15]** 指示 AI 模式；
   `ai_mode::last_nodes()` 可显示搜索量。
5. 已接入 `main.cpp`：AI 模式下仍先处理 Restart/Pause/Quit，再走 AI 落子。

## 预算 vs 时间（50 MHz）

| 节点预算 | 开 cache（≈1410 拍/节点） | 不开 cache（≈11170 拍/节点） | 棋力 |
| --- | --- | --- | --- |
| 1,000 | 28 ms/步 | 0.22 s/步 | 弱 |
| 3,000 | 84 ms/步 | 0.67 s/步 | 中 |
| **10,000（默认）** | **0.28 s/步** | 2.2 s/步 | PC 实测 90% 到 2048 |
| 20,000 | 0.56 s/步 | 4.5 s/步 | 略强 |

一局约 1000 步：默认预算下开 cache 约 **5 分钟**，不开 cache 约 **37 分钟**。

## Cache 与帧缓冲

固件默认 **不开 cache**（仿真测试依赖 BaseRAM 里的 `game_snapshot`，开 cache 后
dcache 写回会让测试台读到旧值）。板级构建用：

```bash
make -C sw firmware GAME_CACHE=1 GAME_DIR=.../game-cache
```

此时 `main()` 会调用 `boot_enable_caches()`，并把 AI 预算提到 10000；默认（无 cache）
预算 3000。

- RAM（代码/栈/BaseRAM）可缓存，confreg 与 ExtRAM 别名（`0xA000_0000`）不缓存；
- 帧缓冲常量已改为 **`0xA000_0000` / `0xA008_0000`**（不可缓存别名），
  开 cache 时 VGA 也能立即读到新像素；
- 不开 cache 也能跑，只是 AI 慢约 8 倍。

## 测试

```bash
make -C sw ai-mode-test          # PC：Game + ai_mode 完整对局，默认 10 局
```

当前 PC 结果：**9/10 到 2048**，平均 19958 分、965 步、约 9.9k 节点/步；
`mode toggle` 自检 PASS。

`ai_mode.cpp` 已通过 LA32R 交叉编译检查（`-ffreestanding -fno-exceptions -fno-rtti`），
无浮点、无 libc 依赖。
