// PC 端 AI 棋力/开销测试
//
//   ./ai_test [games] [node_budget] [max_depth]
//
// 默认 10 局、每步 10000 节点、最大深度 8。
// 输出每局的最高方块/得分/步数/节点数，以及汇总的到 2048 成功率。
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <chrono>

#include "../app/ai.h"

namespace {

struct GameResult {
    int max_exp;
    int score;
    int moves;
    uint64_t nodes;
    bool won;
};

bool has_move(const uint8_t b[16]) {
    uint8_t nb[16];
    for (int d = 0; d < 4; d++)
        if (ai::move(b, d, nb, nullptr)) return true;
    return false;
}

GameResult play_game(uint32_t seed, int budget, int max_depth) {
    uint8_t b[16] = {0};
    uint32_t s = seed;
    ai::spawn(b, &s);
    ai::spawn(b, &s);

    GameResult r = {0, 0, 0, 0, false};
    while (true) {
        uint64_t n = 0;
        int m = ai::best_move(b, budget, max_depth, &n);
        r.nodes += n;
        if (m < 0) break;

        uint8_t nb[16];
        int gain = 0;
        if (!ai::move(b, m, nb, &gain)) break;
        for (int i = 0; i < 16; i++) b[i] = nb[i];
        r.score += gain;
        r.moves++;
        ai::spawn(b, &s);

        int mx = 0;
        for (int i = 0; i < 16; i++)
            if (b[i] > mx) mx = b[i];
        if (mx > r.max_exp) r.max_exp = mx;
        if (mx >= 11) { r.won = true; break; }
        if (!has_move(b)) break;
    }
    return r;
}

}  // namespace

int main(int argc, char** argv) {
    int games = argc > 1 ? std::atoi(argv[1]) : 10;
    int budget = argc > 2 ? std::atoi(argv[2]) : 10000;
    int max_depth = argc > 3 ? std::atoi(argv[3]) : 8;
    if (games <= 0) games = 1;

    std::printf("games=%d budget=%d depth=%d\n", games, budget, max_depth);

    int wins = 0;
    long long total_score = 0, total_moves = 0;
    unsigned long long total_nodes = 0;
    auto t0 = std::chrono::steady_clock::now();

    for (int g = 0; g < games; g++) {
        GameResult r = play_game((uint32_t)(g + 1), budget, max_depth);
        wins += r.won ? 1 : 0;
        total_score += r.score;
        total_moves += r.moves;
        total_nodes += r.nodes;
        std::printf("game %2d: max=%5d score=%6d moves=%4d nodes=%8llu %s\n",
                    g + 1, 1 << r.max_exp, r.score, r.moves,
                    (unsigned long long)r.nodes, r.won ? "WIN" : "-");
    }

    auto t1 = std::chrono::steady_clock::now();
    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    double per_move = total_moves ? (double)total_nodes / total_moves : 0.0;

    std::printf("----\n");
    std::printf("win2048: %d/%d (%.0f%%)\n", wins, games, 100.0 * wins / games);
    std::printf("avg score=%lld  avg moves=%.0f  nodes/move=%.0f  total=%.1f s\n",
                total_score / games, (double)total_moves / games, per_move, ms / 1000.0);
    return 0;
}
