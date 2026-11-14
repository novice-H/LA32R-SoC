#ifndef LA32R_2048_BOARD_RENDER_H
#define LA32R_2048_BOARD_RENDER_H

#include "../app/game.h"
#include "../drv/framebuffer.h"

namespace platform {
void draw_board(framebuffer::Surface surface, const game2048::Game& game);
}

namespace board_render {
bool render(const game2048::Game& game, bool active);
bool clear();
}

#endif
