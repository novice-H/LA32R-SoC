#include "platform.h"

#include <cstdint>

#include "../drv/confreg.h"
#include "../drv/input.h"
#include "board_render.h"

namespace {
input::State input_state = {};
std::uint32_t random_state = 1;

void seed_random() {
#if defined(GAME2048_SEED) && GAME2048_SEED != 0
    random_state = static_cast<std::uint32_t>(GAME2048_SEED);
#else
    random_state = confreg::read(confreg::Register::Random);
#endif
    if (random_state == 0) random_state = 1;
}
}  // namespace

namespace platform {
Event read_event() {
    if ((input::keys() & confreg::kGameEnable) == 0) {
        input::clear(input_state);
        confreg::write(confreg::Register::Status, 0);
        return Event::Pause;
    }
    switch (input::poll(input_state)) {
    case input::Button::Up: return Event::Up;
    case input::Button::Left: return Event::Left;
    case input::Button::Down: return Event::Down;
    case input::Button::Right: return Event::Right;
    default: return Event::None;
    }
}

void render(const game2048::Game& game) {
    while ((input::keys() & confreg::kGameEnable) != 0 &&
           !board_render::render(game, true)) {
    }
}

bool ai_mode_requested() {
    return (input::keys() & confreg::kAiEnable) != 0;
}

uint32_t random_u32(void*) {
    random_state ^= random_state << 13;
    random_state ^= random_state >> 17;
    random_state ^= random_state << 5;
    return random_state;
}

void wait_for_start() {
    bool cleared = false;
    for (;;) {
        input::clear(input_state);
        if ((input::keys() & confreg::kGameEnable) != 0) {
            confreg::write(confreg::Register::Status, 0);
            input::clear(input_state);
            seed_random();
            return;
        }
        if (!cleared) {
            cleared = board_render::clear();
        }
    }
}
}  // namespace platform
