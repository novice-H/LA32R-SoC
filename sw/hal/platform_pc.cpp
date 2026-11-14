#include "platform.h"

#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <poll.h>
#include <termios.h>
#include <unistd.h>

namespace {
class Terminal {
public:
    Terminal() : active(false) {
        if (isatty(STDIN_FILENO) && tcgetattr(STDIN_FILENO, &saved) == 0) {
            termios raw = saved;
            raw.c_lflag &= ~(ICANON | ECHO | ISIG);
            raw.c_cc[VMIN] = 1;
            raw.c_cc[VTIME] = 0;
            active = tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0;
        }
    }
    ~Terminal() {
        if (active) tcsetattr(STDIN_FILENO, TCSANOW, &saved);
    }
private:
    termios saved;
    bool active;
};

int sequence_byte() {
    pollfd input = {STDIN_FILENO, POLLIN, 0};
    return poll(&input, 1, 100) > 0 ? std::getchar() : EOF;
}
} // namespace

namespace platform {
bool ai_mode_requested() { return false; }

Event read_event() {
    static Terminal terminal;
    // Unbuffered input keeps poll() and stdio on the same byte stream.
    static const bool configured = []() {
        std::setvbuf(stdin, nullptr, _IONBF, 0);
        return true;
    }();
    (void)configured;
    int key = std::getchar();
    if (key == 27) {
        const int prefix = sequence_byte();
        if (prefix != '[' && prefix != 'O') return Event::None;
        switch (sequence_byte()) {
        case 'A': return Event::Up;
        case 'B': return Event::Down;
        case 'C': return Event::Right;
        case 'D': return Event::Left;
        default: return Event::None;
        }
    }
    switch (key) {
    case 'w': case 'W': return Event::Up;
    case 'a': case 'A': return Event::Left;
    case 's': case 'S': return Event::Down;
    case 'd': case 'D': return Event::Right;
    case 'r': case 'R': return Event::Restart;
    case 'q': case 'Q': case 3: case EOF: return Event::Quit;
    default: return Event::None;
    }
}

void render(const game2048::Game& game) {
    if (isatty(STDOUT_FILENO)) std::printf("\033[2J\033[H");
    std::printf("2048 | WASD / arrows: move | R: restart | Q: quit\n");
    std::printf("Score: %lu  Moves: %lu\n",
                static_cast<unsigned long>(game.score),
                static_cast<unsigned long>(game.moves));
    for (unsigned row = 0; row < 4; ++row) {
        std::puts("+------+------+------+------+");
        for (unsigned col = 0; col < 4; ++col) {
            if (game.tiles[row][col])
                std::printf("|%6lu", static_cast<unsigned long>(game.tiles[row][col]));
            else std::printf("|      ");
        }
        std::puts("|");
    }
    std::puts("+------+------+------+------+");
    if (game.won) std::puts("You reached 2048! R: restart, Q: quit.");
    else if (game.over) std::puts("Game over. R: restart, Q: quit.");
    std::fflush(stdout);
}

uint32_t random_u32(void*) {
    // A supplied seed makes PC tests and later board replay reproducible.
    static uint32_t state = []() {
#if defined(GAME2048_SEED) && GAME2048_SEED != 0
        uint32_t value = static_cast<uint32_t>(GAME2048_SEED);
#else
        const char* seed = std::getenv("GAME2048_SEED");
        uint32_t value = seed ? static_cast<uint32_t>(std::strtoul(seed, nullptr, 0))
                              : static_cast<uint32_t>(std::time(nullptr));
#endif
        return value ? value : 1u;
    }();
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

void wait_for_start() {}
} // namespace platform
