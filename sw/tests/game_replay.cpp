#include "../app/game.h"
#include "../hal/board_render.h"

#include <stdio.h>
#include <stdlib.h>
#include <vector>

namespace {
uint32_t random_state = 123U;

uint32_t xorshift32(void*) {
    uint32_t value = random_state;
    value ^= value << 13U;
    value ^= value >> 17U;
    value ^= value << 5U;
    random_state = value;
    return value;
}

bool emit(FILE* output, const game2048::Game& game) {
    for (uint32_t row = 0; row < 4U; ++row)
        for (uint32_t col = 0; col < 4U; ++col)
            if (fprintf(output, "%08x\n", game.tiles[row][col]) < 0) return false;
    return fprintf(output, "%08x\n%08x\n%08x\n%08x\n",
                   game.score, game.moves, game.won ? 1U : 0U,
                   game.over ? 1U : 0U) >= 0;
}

bool emit_frame(FILE* output, const uint32_t* pixels, size_t count) {
    if (count != 120000U) return false;
    for (size_t index = 0; index < count; ++index) {
        if (fprintf(output, "%08x\n", pixels[index]) < 0) return false;
    }
    return true;
}
}  // namespace

int main(int argc, char** argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: game_replay OUTPUT_DIR\n");
        return 2;
    }
    char expected_path[1024];
    char frame_path[1024];
    if (snprintf(expected_path, sizeof(expected_path), "%s/game-expected.hex", argv[1]) >=
            static_cast<int>(sizeof(expected_path)) ||
        snprintf(frame_path, sizeof(frame_path), "%s/game-frame.hex", argv[1]) >=
            static_cast<int>(sizeof(frame_path))) {
        fprintf(stderr, "output directory path too long\n");
        return 2;
    }
    FILE* expected = fopen(expected_path, "w");
    FILE* frame = fopen(frame_path, "w");
    if (expected == NULL || frame == NULL) {
        perror("game replay output");
        if (expected != NULL) fclose(expected);
        if (frame != NULL) fclose(frame);
        return 2;
    }
    game2048::Game game = {};
    game2048::init(game, xorshift32, NULL);
    bool ok = emit(expected, game);
    const game2048::Direction directions[] = {
        game2048::Direction::Up, game2048::Direction::Left,
        game2048::Direction::Down, game2048::Direction::Right
    };
    for (uint32_t index = 0; index < 4U && ok; ++index) {
        if (!game.won && !game.over && game2048::move(game, directions[index]))
            game2048::spawn(game, xorshift32, NULL);
        ok = emit(expected, game);
    }
    std::vector<uint32_t> pixels(120000U, 0U);
    framebuffer::Surface surface = {pixels.data()};
    random_state = 123U;
    game2048::init(game, xorshift32, NULL);
    platform::draw_board(surface, game);
    ok = emit_frame(frame, pixels.data(), pixels.size()) && ok;
    if (fclose(expected) != 0) ok = false;
    if (fclose(frame) != 0) ok = false;
    if (!ok) {
        fprintf(stderr, "failed to write game replay output\n");
        return 1;
    }
    return 0;
}
