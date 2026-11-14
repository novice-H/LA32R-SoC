#ifndef GAME2048_GAME_H
#define GAME2048_GAME_H

#include <stdint.h>

namespace game2048 {

enum class Direction { Up, Left, Down, Right };

struct Game {
    uint32_t tiles[4][4];
    uint32_t score;
    uint32_t moves;
    bool won;
    bool over;
};

typedef uint32_t (*RandomFn)(void*);

void init(Game& game, RandomFn random, void* context);
bool move(Game& game, Direction direction);
bool spawn(Game& game, RandomFn random, void* context);
bool can_move(const Game& game);
void refresh_status(Game& game);

}  // namespace game2048

#endif  // GAME2048_GAME_H
