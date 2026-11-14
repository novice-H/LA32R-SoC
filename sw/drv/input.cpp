#include "input.h"

#include "confreg.h"

namespace input {
namespace {

constexpr std::uint32_t kButtonBits[] = {
    static_cast<std::uint32_t>(Button::Up),
    static_cast<std::uint32_t>(Button::Left),
    static_cast<std::uint32_t>(Button::Down),
    static_cast<std::uint32_t>(Button::Right),
};

}  // namespace

void clear(State& state) {
    state.pending = 0;
    (void)confreg::read(confreg::Register::Buttons);
}

Button poll(State& state) {
    if (state.pending == 0) {
        state.pending = confreg::read(confreg::Register::Buttons) &
                        confreg::kButtonMask;
    }

    for (const std::uint32_t bit : kButtonBits) {
        if ((state.pending & bit) != 0) {
            state.pending &= ~bit;
            return static_cast<Button>(bit);
        }
    }

    return Button::None;
}

std::uint32_t keys() {
    return confreg::read(confreg::Register::Keys) & 0x3;
}

}  // namespace input
