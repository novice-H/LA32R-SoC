#include "../app/game.h"

#include <stdio.h>

namespace {

int failures = 0;

void check(bool condition, const char* name) {
    if (condition) {
        printf("PASS %s\n", name);
    } else {
        printf("FAIL %s\n", name);
        ++failures;
    }
}

struct Sequence { uint32_t values[32]; uint32_t next; };

struct CounterRandom { uint32_t calls; uint32_t values[4]; };

struct SeedRandom { uint32_t state; };

uint32_t sequence_random(void* context) {
    Sequence* sequence = static_cast<Sequence*>(context);
    return sequence->values[sequence->next++ % 32U];
}

uint32_t counter_random(void* context) {
    CounterRandom* random = static_cast<CounterRandom*>(context);
    const uint32_t value = random->values[random->calls % 4U];
    ++random->calls;
    return value;
}

uint32_t seeded_random(void* context) {
    SeedRandom* random = static_cast<SeedRandom*>(context);
    random->state = random->state * 1664525U + 1013904223U;
    return random->state;
}

void clear(game2048::Game& game) {
    for (uint32_t r = 0; r < 4U; ++r)
        for (uint32_t c = 0; c < 4U; ++c)
            game.tiles[r][c] = 0U;
    game.score = game.moves = 0U;
    game.won = game.over = false;
}

bool equal_board(const game2048::Game& a, const game2048::Game& b) {
    for (uint32_t r = 0; r < 4U; ++r)
        for (uint32_t c = 0; c < 4U; ++c)
            if (a.tiles[r][c] != b.tiles[r][c]) return false;
    return true;
}

}  // namespace

int main() {
    using namespace game2048;
    Game game = {};
    check(move(game, Direction::Left) == false, "empty board move unchanged");

    clear(game);
    game.tiles[0][0] = 2U; game.tiles[0][1] = 2U;
    game.tiles[1][0] = 4U; game.tiles[1][1] = 4U;
    check(move(game, Direction::Left), "left move changes board");
    check(game.tiles[0][0] == 4U && game.tiles[1][0] == 8U &&
          game.score == 12U && game.moves == 1U, "left merge and score");

    clear(game);
    game.tiles[0][0] = 2U; game.tiles[0][1] = 2U;
    game.tiles[0][2] = 2U; game.tiles[0][3] = 2U;
    move(game, Direction::Left);
    check(game.tiles[0][0] == 4U && game.tiles[0][1] == 4U &&
          game.tiles[0][2] == 0U && game.score == 8U,
          "four equal tiles merge in pairs once");

    clear(game);
    game.tiles[0][0] = 2U; game.tiles[0][1] = 2U; game.tiles[0][2] = 4U;
    move(game, Direction::Left);
    check(game.tiles[0][0] == 4U && game.tiles[0][1] == 4U &&
          game.tiles[0][2] == 0U, "new merge does not merge again");

    clear(game);
    game.tiles[0][0] = 2U; game.tiles[1][0] = 2U;
    check(move(game, Direction::Up) && game.tiles[0][0] == 4U,
          "up direction");
    clear(game);
    game.tiles[0][0] = 2U; game.tiles[0][1] = 2U;
    check(move(game, Direction::Right) && game.tiles[0][3] == 4U,
          "right direction");
    clear(game);
    game.tiles[0][0] = 2U; game.tiles[1][0] = 2U;
    check(move(game, Direction::Down) && game.tiles[3][0] == 4U,
          "down direction");

    clear(game);
    game.tiles[0][0] = 2U;
    check(!move(game, Direction::Left) && game.moves == 0U && game.score == 0U,
          "invalid move leaves counters unchanged");

    clear(game);
    for (uint32_t r = 0; r < 4U; ++r)
        for (uint32_t c = 0; c < 4U; ++c)
            game.tiles[r][c] = ((r + c) % 2U == 0U) ? 2U : 4U;
    refresh_status(game);
    check(game.over && !can_move(game), "full dead board is over");
    game.tiles[0][0] = 0U;
    refresh_status(game);
    check(!game.over && can_move(game), "empty slot allows a move");
    game.tiles[0][0] = 2U; game.tiles[0][1] = 2U;
    refresh_status(game);
    check(!game.over && can_move(game), "matching neighbors allow a move");

    clear(game);
    game.tiles[0][0] = 1024U; game.tiles[0][1] = 1024U;
    move(game, Direction::Left);
    check(game.won && game.tiles[0][0] == 2048U, "2048 sets won");

    Sequence a = {{0U, 9U, 1U, 0U}, 0U};
    Sequence b = {{0U, 9U, 1U, 0U}, 0U};
    Game first = {}, second = {};
    init(first, sequence_random, &a);
    init(second, sequence_random, &b);
    check(equal_board(first, second) && first.tiles[0][0] == 2U &&
          first.tiles[0][2] == 4U, "fixed random sequence reproduces init");
    uint32_t occupied = 0U;
    for (uint32_t r = 0; r < 4U; ++r)
        for (uint32_t c = 0; c < 4U; ++c)
            if (first.tiles[r][c] != 0U) ++occupied;
    check(occupied == 2U, "init spawns two tiles");

    Game full = {};
    for (uint32_t r = 0; r < 4U; ++r)
        for (uint32_t c = 0; c < 4U; ++c)
            full.tiles[r][c] = 2U;
    CounterRandom counter = {0U, {7U, 7U, 7U, 7U}};
    check(!spawn(full, counter_random, &counter) && counter.calls == 0U,
          "full board spawn does not consume random values");

    Game branch = {};
    CounterRandom two_rng = {0U, {0U, 9U, 0U, 0U}};
    CounterRandom four_rng = {0U, {0U, 0U, 0U, 0U}};
    check(spawn(branch, counter_random, &two_rng) && branch.tiles[0][0] == 2U,
          "spawn 2 branch");
    clear(branch);
    check(spawn(branch, counter_random, &four_rng) && branch.tiles[0][0] == 4U,
          "spawn 4 branch");

    clear(branch);
    for (uint32_t r = 0; r < 4U; ++r)
        for (uint32_t c = 0; c < 4U; ++c)
            branch.tiles[r][c] = ((r + c) % 2U == 0U) ? 2U : 4U;
    branch.tiles[3][3] = 0U;
    refresh_status(branch);
    CounterRandom last_rng = {0U, {0U, 9U, 0U, 0U}};
    check(spawn(branch, counter_random, &last_rng) && branch.over &&
          branch.tiles[3][3] == 2U, "last empty spawn marks dead board over");

    SeedRandom seed_a = {123456U};
    SeedRandom seed_b = {123456U};
    Game replay_a = {}, replay_b = {};
    init(replay_a, seeded_random, &seed_a);
    init(replay_b, seeded_random, &seed_b);
    for (uint32_t step = 0; step < 32U && !replay_a.won && !replay_a.over; ++step) {
        const Direction direction = static_cast<Direction>(step % 4U);
        if (move(replay_a, direction)) spawn(replay_a, seeded_random, &seed_a);
        if (move(replay_b, direction)) spawn(replay_b, seeded_random, &seed_b);
    }
    check(equal_board(replay_a, replay_b) && replay_a.score == replay_b.score &&
          replay_a.moves == replay_b.moves && replay_a.won == replay_b.won &&
          replay_a.over == replay_b.over, "fixed seed reproduces multiple moves");

    printf("%d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
