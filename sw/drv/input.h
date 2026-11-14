#ifndef LA32R_DRV_INPUT_H
#define LA32R_DRV_INPUT_H

#include <cstdint>

namespace input {

enum class Button : std::uint32_t {
    None = 0,
    Up = 1,
    Down = 2,
    Left = 4,
    Right = 8,
};

struct State {
    std::uint32_t pending;
};

// Initialize the caller-owned state with State{}. Polling is single-threaded.
// BTN1 = bit 0 Up, BTN2 = bit 1 Down, BTN3 = bit 2 Left, BTN4 = bit 3 Right.
// Simultaneous button bits are consumed in Up/Left/Down/Right priority order.
// Hardware stores one bit per direction, so repeated presses can merge.
// BTN is a read-to-clear bitmask with one accumulated bit per direction.
// In the current RTL, a BTN read on the same clock edge as a new button edge
// clears btn_evt after accumulation, so that edge is lost.
// Clear software-pending events and discard the current hardware event bits.
void clear(State& state);

// Return one pending button event, in Up/Left/Down/Right priority order.
Button poll(State& state);

// Return live KEY levels: bit 0 game enable, bit 1 AI enable.
std::uint32_t keys();

}  // namespace input

#endif  // LA32R_DRV_INPUT_H
