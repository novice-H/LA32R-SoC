#include <cstdint>

#include "../drv/confreg.h"
#include "../drv/input.h"

extern "C" {
volatile std::uint32_t input_test_result;
volatile std::uint32_t input_test_checks;
}

namespace {

input::State state{};
std::uint32_t check_count = 0;

[[noreturn]] void fail(std::uint32_t code) {
    input_test_result = 0xbad00000u | code;
    confreg::write(confreg::Register::Step, code);
    confreg::write(confreg::Register::Status, confreg::kStatusLose);
    for (;;) {
    }
}

void expect_button(input::Button actual, input::Button expected) {
    ++check_count;
    input_test_checks = check_count;
    if (actual != expected) {
        fail(check_count);
    }
}

void expect_raw_buttons(std::uint32_t expected) {
    ++check_count;
    input_test_checks = check_count;
    if ((confreg::read(confreg::Register::Buttons) & confreg::kButtonMask) !=
        expected) {
        fail(check_count);
    }
}

void expect_keys(std::uint32_t expected) {
    ++check_count;
    input_test_checks = check_count;
    if (input::keys() != expected) {
        fail(check_count);
    }
}

void begin(std::uint32_t phase, std::uint32_t key = 3) {
    confreg::write(confreg::Register::Step, phase);
    for (std::uint32_t reads = 0; reads < 10000; ++reads) {
        if (input::keys() == key) {
            return;
        }
    }
    fail(0x1000u | phase);
}

void finish(std::uint32_t phase) {
    confreg::write(confreg::Register::Step, 100u + phase);
    for (std::uint32_t reads = 0; reads < 10000; ++reads) {
        if (input::keys() == 0) {
            return;
        }
    }
    fail(0x2000u | phase);
}

void expect_clean_state(std::uint32_t phase) {
    expect_button(input::poll(state), input::Button::None);
    if (state.pending != 0) {
        fail(0x3000u | phase);
    }
}

}  // namespace

int main() {
    input_test_result = 0;
    input_test_checks = 0;
    input::clear(state);

    // 1: Up edge, then a held level must not generate software repeats.
    begin(1);
    expect_button(input::poll(state), input::Button::Up);
    expect_raw_buttons(0);
    for (std::uint32_t i = 0; i < 8; ++i) {
        expect_button(input::poll(state), input::Button::None);
    }
    expect_clean_state(1);
    finish(1);

    // 2: Left edge.
    begin(2);
    expect_button(input::poll(state), input::Button::Left);
    expect_button(input::poll(state), input::Button::None);
    expect_clean_state(2);
    finish(2);

    // 3: Down edge.
    begin(3);
    expect_button(input::poll(state), input::Button::Down);
    expect_button(input::poll(state), input::Button::None);
    expect_clean_state(3);
    finish(3);

    // 4: Right edge.
    begin(4);
    expect_button(input::poll(state), input::Button::Right);
    expect_button(input::poll(state), input::Button::None);
    expect_clean_state(4);
    finish(4);

    // 5: Simultaneous buttons follow priority order; software pending survives a
    // separate read that clears the hardware register.
    begin(5);
    expect_button(input::poll(state), input::Button::Up);
    expect_raw_buttons(0);
    expect_button(input::poll(state), input::Button::Left);
    expect_button(input::poll(state), input::Button::Down);
    expect_button(input::poll(state), input::Button::Right);
    expect_button(input::poll(state), input::Button::None);
    expect_clean_state(5);
    finish(5);

    // 6: Up and Down are accumulated before polling.
    begin(6);
    expect_button(input::poll(state), input::Button::Up);
    expect_raw_buttons(0);
    expect_button(input::poll(state), input::Button::Down);
    expect_button(input::poll(state), input::Button::None);
    expect_clean_state(6);
    finish(6);

    // 7: Two unobserved Up pulses merge into the hardware's one direction bit.
    begin(7);
    expect_button(input::poll(state), input::Button::Up);
    expect_button(input::poll(state), input::Button::None);
    expect_clean_state(7);
    finish(7);

    // 8: A new Up edge after release is reported normally.
    begin(8);
    expect_button(input::poll(state), input::Button::Up);
    expect_button(input::poll(state), input::Button::None);
    expect_clean_state(8);
    finish(8);

    // 9: clear discards the remaining software-pending simultaneous events.
    begin(9);
    expect_button(input::poll(state), input::Button::Up);
    input::clear(state);
    expect_button(input::poll(state), input::Button::None);
    expect_clean_state(9);
    finish(9);

    // 10: clear discards unread hardware events.
    begin(10);
    input::clear(state);
    expect_button(input::poll(state), input::Button::None);
    expect_clean_state(10);
    finish(10);

    // 11: KEY exposes only its low two live bits despite high DIP bits.
    begin(11, 1);
    expect_keys(1);
    expect_button(input::poll(state), input::Button::None);
    expect_clean_state(11);
    finish(11);

    // 12: KEY bit 1 is independently observable.
    begin(12, 2);
    expect_keys(2);
    expect_button(input::poll(state), input::Button::None);
    expect_clean_state(12);
    finish(12);

    input_test_result = 0x600d1a00u;
    input_test_checks = check_count;
    confreg::write(confreg::Register::Step, 1234);
    confreg::write(confreg::Register::Status, confreg::kStatusWin);
    return 0;
}
