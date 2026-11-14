#include <cstdint>
#include "../drv/confreg.h"
#include "../drv/framebuffer.h"
#include "framebuffer_pattern.h"

extern "C" {
volatile std::uint32_t framebuffer_test_result;
volatile std::uint32_t framebuffer_test_checks;
}

static void expect(bool condition) {
    ++framebuffer_test_checks;
    if (!condition) {
        framebuffer_test_result = 0xbadf0000u | framebuffer_test_checks;
        confreg::write(confreg::Register::Step, framebuffer_test_checks);
        confreg::write(confreg::Register::Status, confreg::kStatusLose);
        for (;;) {}
    }
}

static void wait_for_capture(std::uint32_t key) {
    // The testbench captures a stable complete frame before acknowledging.
    while ((confreg::read(confreg::Register::Keys) & 3u) != key) {}
}

int main() {
    framebuffer::Frame frame{};
    expect(!framebuffer::present(frame));
    expect(framebuffer::begin(frame));
    expect(frame.index == 1);
    framebuffer::Frame invalid = frame;
    invalid.index = 2;
    expect(!framebuffer::present(invalid));

    confreg::write(confreg::Register::Step, 1);
    framebuffer_test_pattern(frame.surface, 0);
    expect(framebuffer::present(frame));
    expect(confreg::read(confreg::Register::Framebuffer) == confreg::kDisplayedBuffer);
    expect(!framebuffer::present(frame));
    confreg::write(confreg::Register::Step, 101);
    wait_for_capture(1);

    expect(framebuffer::begin(frame));
    expect(frame.index == 0);
    confreg::write(confreg::Register::Step, 2);
    framebuffer_test_pattern(frame.surface, 1);
    expect(framebuffer::present(frame));
    expect(confreg::read(confreg::Register::Framebuffer) == 0);
    expect(!framebuffer::present(frame));
    confreg::write(confreg::Register::Step, 102);
    wait_for_capture(2);

    // The testbench releases KEY=3 well inside active scanout, so timeout=0
    // expires before VSYNC. The pending hardware request is then recovered.
    expect(framebuffer::begin(frame));
    expect(frame.index == 1);
    confreg::write(confreg::Register::Step, 3);
    wait_for_capture(3);
    expect(!framebuffer::present(frame, 0));
    expect(!frame.acquired);
    framebuffer::Frame waiting{};
    expect(!framebuffer::begin(waiting, 0));
    expect(!waiting.acquired && waiting.surface.words == nullptr);
    expect(framebuffer::begin(waiting));
    expect(waiting.index == 0);
    expect(framebuffer::present(waiting));
    expect(confreg::read(confreg::Register::Framebuffer) == 0);
    confreg::write(confreg::Register::Step, 103);

    framebuffer_test_result = 0x600dfb00u;
    confreg::write(confreg::Register::Step, 1234);
    confreg::write(confreg::Register::Status, confreg::kStatusWin);
    return 0;
}
