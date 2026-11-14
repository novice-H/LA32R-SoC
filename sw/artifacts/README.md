# 2048 上板发布文件

## BaseRAM

| 文件 | 加载位置 | 说明 |
| --- | --- | --- |
| `game_baseram.bin` | BaseRAM 偏移 0（CPU 物理地址 `0x1C00_0000`） | 完整 2048 固件（手动 + AI 模式） |

## ExtRAM

**不需要初始化**：帧缓冲 FB0/FB1（物理 `0x1C40_0000` / `0x1C48_0000`，别名
`0xA000_0000` / `0xA008_0000`）由游戏绘制时整屏覆盖，上电内容无关。
若平台强制要求 ExtRAM 初始化文件，上传任意全零 4 MB 文件即可（本仓库不收录大文件）。

## 操作

| 输入 | 功能 |
| --- | --- |
| KEY0 | 游戏使能 / 暂停（关闭回外层等待画面） |
| KEY1 | AI 模式开关（LED15 亮表示 AI） |
| BTN1 | 上 |
| BTN2 | 下 |
| BTN3 | 左 |
| BTN4 | 右 |

## 构建信息

- 构建：`make -C sw firmware GAME_SEED=0`（硬件随机种子，默认不开 cache）
- 入口：`0x1C00_0000`
- 无 ExtRAM 初始化依赖

## 重新生成

```bash
make -C sw firmware GAME_SEED=0
cp build/sw/game/game.bin sw/artifacts/game_baseram.bin
```

AI 模式想更快可在板级构建时开 cache（约 8 倍）：

```bash
make -C sw firmware GAME_SEED=0 GAME_CACHE=1 GAME_DIR=build/sw/game-cache
```

> 注意：`GAME_CACHE=1` 的镜像只建议上板用；仿真测试依赖 BaseRAM 中的
> `game_snapshot`，开 cache 后测试台会读到旧值。
