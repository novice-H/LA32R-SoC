#include "board_render.h"

#include <cstdint>

#include "../drv/confreg.h"
#include "../drv/framebuffer.h"

extern "C" {
extern volatile std::uint32_t game_snapshot[22];
}

namespace {
using framebuffer::Color;
const Color kBackground = framebuffer::rgb(18, 24, 34);
const Color kBoard = framebuffer::rgb(44, 54, 68);
const Color kEmpty = framebuffer::rgb(72, 82, 96);
const Color kText = framebuffer::rgb(238, 242, 248);
const Color kAccent = framebuffer::rgb(247, 190, 70);
const std::uint32_t kStatusDisplayError = 1u << 5;

void show_display_error() {
    confreg::write(confreg::Register::Status, kStatusDisplayError);
}

void glyph(framebuffer::Surface surface, int x, int y, char value,
           Color color) {
    static const std::uint8_t font[][5] = {
        {0x3e,0x51,0x49,0x45,0x3e}, {0x00,0x42,0x7f,0x40,0x00},
        {0x42,0x61,0x51,0x49,0x46}, {0x21,0x41,0x45,0x4b,0x31},
        {0x18,0x14,0x12,0x7f,0x10}, {0x27,0x45,0x45,0x45,0x39},
        {0x3c,0x4a,0x49,0x49,0x30}, {0x01,0x71,0x09,0x05,0x03},
        {0x36,0x49,0x49,0x49,0x36}, {0x06,0x49,0x49,0x29,0x1e},
        {0x7e,0x11,0x11,0x11,0x7e}, {0x7f,0x49,0x49,0x49,0x36},
        {0x3e,0x41,0x41,0x41,0x22}, {0x7f,0x41,0x41,0x22,0x1c},
        {0x7f,0x49,0x49,0x49,0x41}, {0x7f,0x09,0x09,0x09,0x01},
        {0x3e,0x41,0x49,0x49,0x7a}, {0x7f,0x08,0x08,0x08,0x7f},
        {0x00,0x41,0x7f,0x41,0x00}, {0x06,0x41,0x41,0x3f,0x01},
        {0x7f,0x08,0x14,0x22,0x41}, {0x7f,0x40,0x40,0x40,0x40},
        {0x7f,0x02,0x0c,0x02,0x7f}, {0x7f,0x04,0x08,0x10,0x7f},
        {0x3e,0x41,0x41,0x41,0x3e}, {0x7f,0x09,0x09,0x09,0x06},
        {0x3e,0x41,0x51,0x21,0x5e}, {0x7f,0x09,0x19,0x29,0x46},
        {0x46,0x49,0x49,0x49,0x31}, {0x01,0x01,0x7f,0x01,0x01},
        {0x3f,0x40,0x40,0x40,0x3f}, {0x1f,0x20,0x40,0x20,0x1f},
        {0x3f,0x40,0x38,0x40,0x3f}, {0x63,0x14,0x08,0x14,0x63},
        {0x07,0x08,0x70,0x08,0x07}, {0x61,0x51,0x49,0x45,0x43},
    };
    unsigned index = 36;
    if (value >= '0' && value <= '9') index = static_cast<unsigned>(value-'0');
    else if (value >= 'A' && value <= 'Z') index = 10u + value - 'A';
    else if (value >= 'a' && value <= 'z') index = 10u + value - 'a';
    if (index >= 36) return;
    for (unsigned col = 0; col < 5; ++col)
        for (unsigned row = 0; row < 7; ++row)
            if ((font[index][col] & (1u << row)) != 0)
                framebuffer::fill_rect(surface, x + col * 3, y + row * 3,
                                       2, 2, color);
}

void label(framebuffer::Surface surface, int x, int y, const char* value,
           Color color) {
    while (*value) {
        glyph(surface, x, y, *value++, color);
        x += 18;
    }
}

unsigned decimal_digits(std::uint32_t value) {
    unsigned count = 1;
    while (value >= 10) {
        value /= 10;
        ++count;
    }
    return count;
}

void draw_stat(framebuffer::Surface surface, int x, int y, int width,
               std::uint32_t value, Color color) {
    const unsigned digits = decimal_digits(value);
    unsigned scale = 3;
    while (scale > 1 && digits * 8 * scale > static_cast<unsigned>(width))
        --scale;
    const int text_width = static_cast<int>(digits * 8 * scale);
    framebuffer::number(surface, x + (width - text_width) / 2, y,
                        value, scale, color);
}

void draw_number(framebuffer::Surface surface, int x, int y,
                 std::uint32_t value, unsigned scale, Color color) {
    framebuffer::number(surface, x, y, value, scale, color);
}

void publish(const game2048::Game* game, bool active) {
    static std::uint32_t serial = 0;
    if (game == nullptr) {
        game_snapshot[21] = 0;
        return;
    }
    unsigned i = 0;
    for (unsigned row = 0; row < 4; ++row)
        for (unsigned col = 0; col < 4; ++col)
            game_snapshot[i++] = game->tiles[row][col];
    game_snapshot[16] = game->score;
    game_snapshot[17] = game->moves;
    game_snapshot[18] = game->won ? 1u : 0u;
    game_snapshot[19] = game->over ? 1u : 0u;
    game_snapshot[21] = active ? 1u : 0u;
    game_snapshot[20] = ++serial;
}

}  // namespace

extern "C" {
volatile std::uint32_t game_snapshot[22] = {};
}

namespace platform {
void draw_board(framebuffer::Surface surface, const game2048::Game& game) {
    framebuffer::clear(surface, kBackground);
    label(surface, 74, 34, "2048", kAccent);
    label(surface, 300, 38, "SCORE", kText);
    draw_stat(surface, 400, 32, 130, game.score, kAccent);
    label(surface, 550, 38, "MOVES", kText);
    draw_stat(surface, 650, 32, 130, game.moves, kAccent);

    const int origin_x = 170, origin_y = 100, cell = 100, gap = 12;
    framebuffer::fill_rect(surface, origin_x - 12, origin_y - 12,
                           4 * cell + 5 * gap, 4 * cell + 5 * gap, kBoard);
    for (unsigned row = 0; row < 4; ++row) {
        for (unsigned col = 0; col < 4; ++col) {
            const int x = origin_x + static_cast<int>(col) * (cell + gap);
            const int y = origin_y + static_cast<int>(row) * (cell + gap);
            const std::uint32_t value = game.tiles[row][col];
            framebuffer::fill_rect(surface, x, y, cell, cell,
                                  value ? framebuffer::rgb(220, 166, 95) : kEmpty);
            if (value) {
                unsigned digits = 1;
                for (std::uint32_t n = value; n >= 10; n /= 10) ++digits;
                unsigned scale = 5;
                while (scale > 1 && digits * 8 * scale > 88) --scale;
                const int width = static_cast<int>(digits * 8 * scale);
                draw_number(surface, x + (cell - width) / 2,
                            y + (cell - static_cast<int>(16 * scale)) / 2,
                            value, scale, kText);
            }
        }
    }
    if (game.won) label(surface, 260, 560, "YOU WIN", kAccent);
    else if (game.over) label(surface, 260, 560, "GAME OVER", kAccent);
    else label(surface, 230, 560, "KEY0 ENABLE  KEY1 IGNORED", kText);
}
} // namespace platform

namespace board_render {
bool render(const game2048::Game& game, bool active) {
    framebuffer::Frame frame;
    if (!framebuffer::begin(frame)) {
        show_display_error();
        return false;
    }
    platform::draw_board(frame.surface, game);

    if (!framebuffer::present(frame)) {
        show_display_error();
        return false;
    }
    confreg::write(confreg::Register::Step,
                   game.moves > 3199u ? 3199u : game.moves);
    confreg::write(confreg::Register::Status,
                   game.won ? confreg::kStatusWin :
                   game.over ? confreg::kStatusLose : 0u);
    publish(&game, active);
    return true;
}

bool clear() {
    framebuffer::Frame frame;
    if (!framebuffer::begin(frame)) {
        show_display_error();
        return false;
    }
    framebuffer::clear(frame.surface, kBackground);
    if (!framebuffer::present(frame)) {
        show_display_error();
        return false;
    }
    confreg::write(confreg::Register::Step, 0);
    confreg::write(confreg::Register::Status, 0);
    publish(nullptr, false);
    return true;
}
}  // namespace board_render
