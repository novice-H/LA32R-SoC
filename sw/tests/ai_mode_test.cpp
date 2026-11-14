// AI 模式层 PC 测试：完全走 Game + ai_mode::step，验证接口和棋力
//
//   ./ai_mode_test [games] [node_budget] [max_depth]
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <chrono>

#include "../app/ai_mode.h"
#include "../app/game.h"

namespace {

uint32_t next_rand(void* ctx) {
    uint32_t* s = (uint32_t*)ctx;
    uint32_t x = *s;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *s = x;
    return x;
}

struct Result {
    uint32_t max_tile;
    uint32_t score;
    uint32_t moves;
    uint64_t nodes;
    bool won;
};

Result play(uint32_t seed) {
    uint32_t state = seed;
    game2048::Game game;
    game2048::init(game, next_rand, &state);

    Result r = {0, 0, 0, 0, false};
    while (!game.won && !game.over) {
        uint64_t used = 0;
        if (!ai_mode::step(game, next_rand, &state, &used)) break;
        r.nodes += used;
        r.moves = game.moves;
        r.score = game.score;

        for (int row = 0; row < 4; row++)
            for (int col = 0; col < 4; col++)
                if (game.tiles[row][col] > r.max_tile)
                    r.max_tile = game.tiles[row][col];
    }
    r.won = game.won;
    r.score = game.score;
    r.moves = game.moves;
    return r;
}

}  // namespace

int main(int argc, char** argv) {
    int games = argc > 1 ? std::atoi(argv[1]) : 10;
    int budget = argc > 2 ? std::atoi(argv[2]) : 10000;
    int depth = argc > 3 ? std::atoi(argv[3]) : 8;
    if (games <= 0) games = 1;

    ai_mode::set_node_budget(budget);
    ai_mode::set_max_depth(depth);
    ai_mode::set_mode(ai_mode::Mode::AI);

    std::printf("AI mode: games=%d budget=%d depth=%d\n", games, budget, depth);

    int wins = 0;
    long long total_score = 0, total_moves = 0;
    unsigned long long total_nodes = 0;
    auto t0 = std::chrono::steady_clock::now();

    for (int g = 0; g < games; g++) {
        Result r = play((uint32_t)(g + 1));
        wins += r.won ? 1 : 0;
        total_score += r.score;
        total_moves += r.moves;
        total_nodes += r.nodes;
        std::printf("game %2d: max=%5u score=%6u moves=%4u nodes=%8llu %s\n",
                    g + 1, r.max_tile, r.score, r.moves,
                    (unsigned long long)r.nodes, r.won ? "WIN" : "-");
    }

    auto t1 = std::chrono::steady_clock::now();
    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    std::printf("----\n");
    std::printf("win2048: %d/%d (%.0f%%)\n", wins, games, 100.0 * wins / games);
    std::printf("avg score=%lld avg moves=%.0f nodes/move=%.0f total=%.1f s\n",
                total_score / games, (double)total_moves / games,
                total_moves ? (double)total_nodes / total_moves : 0.0,
                ms / 1000.0);

    // 模式开关自检
    ai_mode::toggle();
    bool manual = ai_mode::mode() == ai_mode::Mode::Manual;
    ai_mode::toggle();
    bool ai = ai_mode::mode() == ai_mode::Mode::AI;
    std::printf("mode toggle: %s\n", manual && ai ? "PASS" : "FAIL");
    return (manual && ai) ? 0 : 1;
}
