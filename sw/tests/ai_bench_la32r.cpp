// LA32R 裸机 AI 单步基准
//
// 固定中局棋盘，跑一次 best_move（10000 节点预算），
// 用 confreg STATUS 打开始/结束标记，由仿真统计周期数；
// 节点数与结果写到 BaseRAM 0x1C3FF000，供测试台读取。
#include "../app/ai.h"

#ifndef AI_BENCH_BUDGET
#define AI_BENCH_BUDGET 1000   // 仿真时长考虑；可与 PC 的 10000 对齐
#endif

extern "C" void ai_bench_main(void) {
    volatile uint32_t* cfg = (volatile uint32_t*)0xBFD00000u;

    // 指数表示：1=2, 2=4, ..., 10=1024
    uint8_t b[16] = {
        1, 2, 3, 4,
        5, 6, 7, 8,
        9, 10, 0, 0,
        0, 0, 0, 0,
    };

    cfg[1] = 0x0020u;   // STATUS[5] = 开始标记（对应 LED[5]）

    uint64_t nodes = 0;
    int m = ai::best_move(b, AI_BENCH_BUDGET, 8, &nodes);

    *(volatile uint32_t*)0x1C3FF000u = (uint32_t)nodes;
    *(volatile uint32_t*)0x1C3FF004u = (uint32_t)(m + 1);
    cfg[0] = (uint32_t)(nodes & 0xFFFu);
    cfg[1] = 0x2000u;   // STATUS[13] = 完成（对应 LED[13]）

    for (;;) {}
}
