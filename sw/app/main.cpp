#include "ai_mode.h"
#include "game.h"
#include "../hal/platform.h"

#ifdef GAME2048_USE_CACHE
extern "C" void boot_enable_caches(void);
#endif

int main() {
#ifdef GAME2048_USE_CACHE
    boot_enable_caches();
    ai_mode::set_node_budget(10000);
#else
    ai_mode::set_node_budget(3000);
#endif
    ai_mode::set_max_depth(8);

    game2048::Game game;
    for (;;) {
        platform::wait_for_start();
        game2048::init(game, platform::random_u32, nullptr);
        platform::render(game);
        for (;;) {
            const platform::Event event = platform::read_event();
            if (event == platform::Event::Quit) return 0;
            if (event == platform::Event::Pause) break;
            if (event == platform::Event::Restart) {
                game2048::init(game, platform::random_u32, nullptr);
                platform::render(game);
                continue;
            }
            if (game.won || game.over) continue;

            if (platform::ai_mode_requested()) {
                if (ai_mode::step(game, platform::random_u32, nullptr))
                    platform::render(game);
                continue;
            }

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
}
