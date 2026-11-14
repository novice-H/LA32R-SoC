#ifndef LA32R_2048_PLATFORM_H
#define LA32R_2048_PLATFORM_H

#include "../app/game.h"

namespace platform {
enum class Event { Up, Left, Down, Right, Restart, Quit, None };

// Each backend implements these functions. Events represent single presses.
Event read_event();
void render(const game2048::Game& game);
// Return pseudorandom bits; the core owns the tile placement rules.
uint32_t random_u32(void* context);
} // namespace platform

#endif
