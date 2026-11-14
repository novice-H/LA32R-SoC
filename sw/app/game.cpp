#include "game.h"

namespace game2048 {
namespace {

uint32_t tile_at(const Game& game, Direction direction, uint32_t line,
                 uint32_t offset) {
    switch (direction) {
        case Direction::Left:  return game.tiles[line][offset];
        case Direction::Right: return game.tiles[line][3U - offset];
        case Direction::Up:    return game.tiles[offset][line];
        case Direction::Down:  return game.tiles[3U - offset][line];
    }
    return 0U;
}

void set_tile(Game& game, Direction direction, uint32_t line,
              uint32_t offset, uint32_t value) {
    switch (direction) {
        case Direction::Left:  game.tiles[line][offset] = value; break;
        case Direction::Right: game.tiles[line][3U - offset] = value; break;
        case Direction::Up:    game.tiles[offset][line] = value; break;
        case Direction::Down:  game.tiles[3U - offset][line] = value; break;
    }
}

}  // namespace

bool can_move(const Game& game) {
    for (uint32_t row = 0; row < 4U; ++row) {
        for (uint32_t col = 0; col < 4U; ++col) {
            const uint32_t value = game.tiles[row][col];
            if (value == 0U) return true;
            if (row < 3U && value == game.tiles[row + 1U][col]) return true;
            if (col < 3U && value == game.tiles[row][col + 1U]) return true;
        }
    }
    return false;
}

void refresh_status(Game& game) {
    game.over = !can_move(game);
}

bool spawn(Game& game, RandomFn random, void* context) {
    uint32_t empty_count = 0U;
    for (uint32_t row = 0; row < 4U; ++row)
        for (uint32_t col = 0; col < 4U; ++col)
            if (game.tiles[row][col] == 0U) ++empty_count;
    if (empty_count == 0U || random == 0) return false;

    const uint32_t selected = random(context) % empty_count;
    uint32_t index = 0U;
    for (uint32_t row = 0; row < 4U; ++row) {
        for (uint32_t col = 0; col < 4U; ++col) {
            if (game.tiles[row][col] != 0U) continue;
            if (index == selected) {
                game.tiles[row][col] = (random(context) % 10U == 0U) ? 4U : 2U;
                refresh_status(game);
                return true;
            }
            ++index;
        }
    }
    return false;
}

void init(Game& game, RandomFn random, void* context) {
    for (uint32_t row = 0; row < 4U; ++row)
        for (uint32_t col = 0; col < 4U; ++col)
            game.tiles[row][col] = 0U;
    game.score = 0U;
    game.moves = 0U;
    game.won = false;
    game.over = false;
    spawn(game, random, context);
    spawn(game, random, context);
    refresh_status(game);
}

bool move(Game& game, Direction direction) {
    bool changed = false;
    for (uint32_t line = 0; line < 4U; ++line) {
        uint32_t compact[4] = {0U, 0U, 0U, 0U};
        uint32_t count = 0U;
        for (uint32_t offset = 0; offset < 4U; ++offset) {
            const uint32_t value = tile_at(game, direction, line, offset);
            if (value != 0U) compact[count++] = value;
        }

        // Scan toward the destination once: each source tile can merge once.
        uint32_t output[4] = {0U, 0U, 0U, 0U};
        uint32_t out_count = 0U;
        for (uint32_t i = 0; i < count; ++i) {
            if (i + 1U < count && compact[i] == compact[i + 1U]) {
                const uint32_t merged = compact[i] * 2U;
                output[out_count++] = merged;
                game.score += merged;
                if (merged == 2048U) game.won = true;
                ++i;
            } else {
                output[out_count++] = compact[i];
            }
        }

        for (uint32_t offset = 0; offset < 4U; ++offset) {
            const uint32_t value = offset < out_count ? output[offset] : 0U;
            if (tile_at(game, direction, line, offset) != value) changed = true;
            set_tile(game, direction, line, offset, value);
        }
    }
    if (changed) ++game.moves;
    refresh_status(game);
    return changed;
}

}  // namespace game2048
