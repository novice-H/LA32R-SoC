#ifndef SW_APP_AI_MODE_H
#define SW_APP_AI_MODE_H

#include <stdint.h>

#include "game.h"

// 2048 AI 模式：在 Game（2/4/... 数值棋盘）与 ai（2 的指数棋盘）之间转换，
// 给板级后端提供"选一步 / 走一步"的接口。
//
// 平台后端只需要：
//   if (ai_mode::mode() == ai_mode::Mode::AI) {
//       if (ai_mode::step(game, platform::random_u32, nullptr)) platform::render(game);
//       continue;   // 跳过 read_event
//   }
// 模式切换由平台决定（建议拨码 SW1 或某个按键），调用 set_mode()/toggle()。
namespace ai_mode {

enum class Mode { Manual, AI };

void set_mode(Mode mode);
Mode mode();
void toggle();

// 每步搜索预算（展开节点数）与最大深度。默认 10000 / 8。
// 50 MHz 开 cache 时约 1410 拍/节点：10000 节点 ≈ 0.28 s/步；
// 不开 cache 约 11k 拍/节点：10000 节点 ≈ 2.2 s/步。
void set_node_budget(int nodes);
int node_budget();
void set_max_depth(int depth);
int max_depth();

// 最近一次 choose/step 实际展开的节点数（可用于状态显示）。
uint64_t last_nodes();

// Game 数值棋盘 -> AI 指数棋盘（0 空，1=2, 2=4, ...）。
void board_from_game(const game2048::Game& game, uint8_t out[16]);

// 用 AI 选一步：返回 0..3（上/右/下/左），无路可走返回 -1。
int choose_direction(const game2048::Game& game, uint64_t* nodes_used = nullptr);

// 选一步并落到 Game 上：move + spawn + refresh_status。
// 返回 false 表示无路可走或该步无效（此时不生成新方块）。
bool step(game2048::Game& game, game2048::RandomFn random, void* context,
          uint64_t* nodes_used = nullptr);

}  // namespace ai_mode

#endif  // SW_APP_AI_MODE_H
