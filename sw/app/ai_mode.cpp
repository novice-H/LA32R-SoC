#include "ai_mode.h"

#include "ai.h"

namespace ai_mode {
namespace {

Mode g_mode = Mode::Manual;
int g_budget = 10000;
int g_depth = 8;
uint64_t g_last_nodes = 0;

// ai 的方向顺序：0=上 1=右 2=下 3=左
const game2048::Direction kDirs[4] = {
    game2048::Direction::Up,
    game2048::Direction::Right,
    game2048::Direction::Down,
    game2048::Direction::Left,
};

}  // namespace

void set_mode(Mode mode) { g_mode = mode; }
Mode mode() { return g_mode; }
void toggle() { g_mode = (g_mode == Mode::AI) ? Mode::Manual : Mode::AI; }

void set_node_budget(int nodes) {
    if (nodes > 0) g_budget = nodes;
}
int node_budget() { return g_budget; }

void set_max_depth(int depth) {
    if (depth > 0) g_depth = depth;
}
int max_depth() { return g_depth; }

uint64_t last_nodes() { return g_last_nodes; }

void board_from_game(const game2048::Game& game, uint8_t out[16]) {
    for (int r = 0; r < 4; r++) {
        for (int c = 0; c < 4; c++) {
            uint32_t v = game.tiles[r][c];
            uint8_t e = 0;
            while (v > 1u) {
                v >>= 1;
                e++;
            }
            out[r * 4 + c] = (v == 0u) ? 0 : e;
        }
    }
}

int choose_direction(const game2048::Game& game, uint64_t* nodes_used) {
    uint8_t board[16];
    board_from_game(game, board);
    uint64_t used = 0;
    int dir = ai::best_move(board, g_budget, g_depth, &used);
    g_last_nodes = used;
    if (nodes_used) *nodes_used = used;
    return dir;  // -1 或 0..3
}

bool step(game2048::Game& game, game2048::RandomFn random, void* context,
          uint64_t* nodes_used) {
    int dir = choose_direction(game, nodes_used);
    if (dir < 0 || dir > 3) return false;
    if (!game2048::move(game, kDirs[dir])) return false;
    game2048::spawn(game, random, context);
    game2048::refresh_status(game);
    return true;
}

}  // namespace ai_mode
