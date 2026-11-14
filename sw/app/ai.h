#ifndef SW_APP_AI_H
#define SW_APP_AI_H

#include <stdint.h>

// 2048 expectimax AI（定点整数 + 4x4 数组棋盘）
//
// 棋盘表示：16 个字节，b[i] == 0 表示空格，否则存的是 2 的指数
// （1 -> 2, 2 -> 4, ..., 11 -> 2048）。这样 log2(tile) 就是 b[i] 本身，
// 完全不需要浮点。
namespace ai {

enum Direction { UP = 0, RIGHT = 1, DOWN = 2, LEFT = 3 };

// 向 dir 移动；返回是否发生变化，gain 返回本次合并得分（可为 nullptr）。
int move(const uint8_t in[16], int dir, uint8_t out[16], int* gain = nullptr);

// 静态评估（定点，约 ±10 万量级；越大越好）。
int eval(const uint8_t b[16]);

// 搜索一步棋；node_budget 是本次搜索允许展开的节点数上限，
// max_depth 是迭代加深的最大深度。返回 0..3，无路可走返回 -1。
// nodes_used 返回实际展开的节点数（可为 nullptr）。
int best_move(const uint8_t b[16], int node_budget, int max_depth,
              uint64_t* nodes_used = nullptr);

// xorshift32
uint32_t rng_next(uint32_t* s);
// 在随机空格生成 2（90%）或 4（10%）
void spawn(uint8_t b[16], uint32_t* s);

}  // namespace ai

#endif  // SW_APP_AI_H
