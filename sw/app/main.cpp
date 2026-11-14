#include "game.h"
#include "../hal/platform.h"

int main() {
    game2048::Game game;
    game2048::init(game, platform::random_u32, nullptr);
    platform::render(game);
    for (;;) {
        const platform::Event event = platform::read_event();
        if (event == platform::Event::Quit) return 0;
        if (event == platform::Event::Restart) {
            game2048::init(game, platform::random_u32, nullptr);
            platform::render(game);
            continue;
        }
        if (game.won || game.over) continue;
        game2048::Direction direction;
        switch (event) {
        case platform::Event::Up: direction = game2048::Direction::Up; break;
        case platform::Event::Left: direction = game2048::Direction::Left; break;
        case platform::Event::Down: direction = game2048::Direction::Down; break;
        case platform::Event::Right: direction = game2048::Direction::Right; break;
        default: continue;
        }
        if (game2048::move(game, direction)) {
            game2048::spawn(game, platform::random_u32, nullptr);
        }
        platform::render(game);
    }
}
