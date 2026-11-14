// LA32R 裸机 AI 单步基准
//
// 固定中局棋盘，跑一次 best_move（10000 节点预算），
// 用 confreg STATUS 打开始/结束标记，由仿真统计周期数；
// 节点数与结果写到 ExtRAM 的不可缓存别名 0xA03F0000，供测试台读取。
#include "../app/ai.h"

extern "C" void boot_enable_caches(void);
extern "C" void boot_disable_caches(void);

#ifndef AI_BENCH_BUDGET
#define AI_BENCH_BUDGET 1000   // 仿真时长考虑；可与 PC 的 10000 对齐
#endif

extern "C" int main(void) {
    volatile uint32_t* cfg = (volatile uint32_t*)0xBFD00000u;

    // 指数表示：1=2, 2=4, ..., 10=1024
    uint8_t b[16] = {
        1, 2, 3, 4,
        5, 6, 7, 8,
        9, 10, 0, 0,
        0, 0, 0, 0,
    };

    // 打开 I/D-Cache：DMW0 映射 RAM（可缓存），DMW1 映射 confreg（不可缓存）
    boot_enable_caches();

    cfg[1] = 0x0020u;   // STATUS[5] = 开始标记（对应 LED[5]）

    uint64_t nodes = 0;
    int m = ai::best_move(b, AI_BENCH_BUDGET, 8, &nodes);

    // 结果写到 DMW1（0xA000_0000 段，MAT=0 不可缓存）的 ExtRAM 高地址，
    // 绕开 dcache 写回，测试台可直接从 RAM 模型读到。
    *(volatile uint32_t*)0xA03F0000u = (uint32_t)nodes;
    *(volatile uint32_t*)0xA03F0004u = (uint32_t)(m + 1);
    cfg[0] = (uint32_t)(nodes & 0xFFFu);
    cfg[1] = 0x2000u;   // STATUS[13] = 完成（对应 LED[13]）

    for (;;) {}
    return 0;
}
