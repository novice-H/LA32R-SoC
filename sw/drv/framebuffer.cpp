#include "framebuffer.h"

#include <climits>
#include <cstdint>

#include "confreg.h"
#include "font_digits.h"

namespace framebuffer {
namespace {

std::uint32_t color_word(Color color) {
    const std::uint32_t c = color;
    return c | (c << 8) | (c << 16) | (c << 24);
}

volatile std::uint32_t* buffer_words(std::uint32_t index) {
    const std::uintptr_t address = index == 0 ? kBuffer0 : kBuffer1;
    return reinterpret_cast<volatile std::uint32_t*>(address);
}

std::uint32_t displayed_index(std::uint32_t control) {
    return (control & confreg::kDisplayedBuffer) != 0 ? 1u : 0u;
}

bool timed_out(std::uint32_t start, std::uint32_t timeout_ms) {
    return static_cast<std::uint32_t>(
               confreg::read(confreg::Register::Time) - start) >= timeout_ms;
}

void write_pixel_run(volatile std::uint32_t* words, int y, int x0, int x1,
                     std::uint32_t value) {
    const std::uint32_t row_start =
        static_cast<std::uint32_t>(y) * (kWidth / 4);
    const int first_word = x0 / 4;
    const int last_word = (x1 - 1) / 4;

    for (int word_index = first_word; word_index <= last_word; ++word_index) {
        const int first_lane = word_index == first_word ? x0 & 3 : 0;
        const int last_lane = word_index == last_word ? ((x1 - 1) & 3) : 3;
        std::uint32_t mask = 0;
        for (int lane = first_lane; lane <= last_lane; ++lane) {
            mask |= 0xffu << (lane * 8);
        }

        volatile std::uint32_t& target = words[row_start + word_index];
        if (mask == 0xffffffffu) {
            target = value;
        } else {
            const std::uint32_t old_value = target;
            target = (old_value & ~mask) | (value & mask);
        }
    }
}

void memory_barrier() {
#if defined(__loongarch__)
    __asm__ volatile("dbar 0" ::: "memory");
#elif defined(__GNUC__) || defined(__clang__)
    __asm__ volatile("" ::: "memory");
#endif
}

}  // namespace

void clear(Surface surface, Color color) {
    if (surface.words == nullptr) {
        return;
    }

    const std::uint32_t value = color_word(color);
    for (std::uint32_t i = 0; i < kWords; ++i) {
        surface.words[i] = value;
    }
}

void pixel(Surface surface, int x, int y, Color color) {
    fill_rect(surface, x, y, 1, 1, color);
}

void fill_rect(Surface surface, int x, int y, int width, int height,
               Color color) {
    if (surface.words == nullptr || width <= 0 || height <= 0) {
        return;
    }

    const std::int64_t left = x;
    const std::int64_t top = y;
    const std::int64_t right = left + static_cast<std::int64_t>(width);
    const std::int64_t bottom = top + static_cast<std::int64_t>(height);
    const std::int64_t clipped_left = left < 0 ? 0 : left;
    const std::int64_t clipped_top = top < 0 ? 0 : top;
    const std::int64_t clipped_right = right > kWidth ? kWidth : right;
    const std::int64_t clipped_bottom = bottom > kHeight ? kHeight : bottom;

    if (clipped_left >= clipped_right || clipped_top >= clipped_bottom) {
        return;
    }

    const int x0 = static_cast<int>(clipped_left);
    const int x1 = static_cast<int>(clipped_right);
    const std::uint32_t value = color_word(color);
    for (int row = static_cast<int>(clipped_top);
         row < static_cast<int>(clipped_bottom); ++row) {
        write_pixel_run(surface.words, row, x0, x1, value);
    }
}

void digit(Surface surface, int x, int y, unsigned value, unsigned scale,
           Color color) {
    if (value >= 10 || scale == 0 || scale > 16 || surface.words == nullptr) {
        return;
    }

    for (unsigned row = 0; row < kGlyphHeight; ++row) {
        const std::uint8_t bits = kDigitFont[value][row];
        unsigned column = 0;
        while (column < kGlyphWidth) {
            while (column < kGlyphWidth &&
                   (bits & (0x80u >> column)) == 0) {
                ++column;
            }
            const unsigned run_start = column;
            while (column < kGlyphWidth &&
                   (bits & (0x80u >> column)) != 0) {
                ++column;
            }
            if (run_start < column) {
                const std::int64_t draw_x =
                    static_cast<std::int64_t>(x) + run_start * scale;
                const std::int64_t draw_y =
                    static_cast<std::int64_t>(y) + row * scale;
                if (draw_x <= INT_MAX && draw_x >= INT_MIN &&
                    draw_y <= INT_MAX && draw_y >= INT_MIN) {
                    fill_rect(surface, static_cast<int>(draw_x),
                              static_cast<int>(draw_y),
                              (column - run_start) * scale, scale, color);
                }
            }
        }
    }
}

void number(Surface surface, int x, int y, std::uint32_t value,
            unsigned scale, Color color) {
    if (scale == 0 || scale > 16) {
        return;
    }

    unsigned digits[10];
    unsigned count = 0;
    do {
        digits[count++] = value % 10;
        value /= 10;
    } while (value != 0 && count < 10);

    for (unsigned position = 0; position < count; ++position) {
        const std::int64_t draw_x =
            static_cast<std::int64_t>(x) +
            static_cast<std::int64_t>(count - position - 1) *
                kGlyphWidth * scale;
        if (draw_x <= INT_MAX && draw_x >= INT_MIN) {
            digit(surface, static_cast<int>(draw_x), y,
                  digits[position], scale, color);
        }
    }
}

bool begin(Frame& frame, std::uint32_t timeout_ms) {
    frame.surface.words = nullptr;
    frame.index = 0;
    frame.acquired = false;

    const std::uint32_t start = confreg::read(confreg::Register::Time);
    for (;;) {
        const std::uint32_t control =
            confreg::read(confreg::Register::Framebuffer);
        if ((control & confreg::kFlipRequest) == 0) {
            const std::uint32_t front = displayed_index(control);
            frame.index = front ^ 1u;
            frame.surface.words = buffer_words(frame.index);
            frame.acquired = true;
            return true;
        }
        if (timed_out(start, timeout_ms)) {
            return false;
        }
    }
}

bool present(Frame& frame, std::uint32_t timeout_ms) {
    if (!frame.acquired || frame.index > 1 ||
        frame.surface.words != buffer_words(frame.index)) {
        frame.acquired = false;
        return false;
    }

    const std::uint32_t before =
        confreg::read(confreg::Register::Framebuffer);
    if ((before & confreg::kFlipRequest) != 0 ||
        displayed_index(before) == frame.index) {
        frame.acquired = false;
        return false;
    }

    const std::uint32_t start = confreg::read(confreg::Register::Time);
    memory_barrier();
    confreg::write(confreg::Register::Framebuffer, confreg::kFlipRequest);
    frame.acquired = false;

    for (;;) {
        const std::uint32_t control =
            confreg::read(confreg::Register::Framebuffer);
        if ((control & confreg::kFlipRequest) == 0 &&
            displayed_index(control) == frame.index) {
            return true;
        }
        if (timed_out(start, timeout_ms)) {
            return false;
        }
    }
}

}  // namespace framebuffer
