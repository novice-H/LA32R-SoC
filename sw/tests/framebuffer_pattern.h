#ifndef LA32R_SW_TESTS_FRAMEBUFFER_PATTERN_H
#define LA32R_SW_TESTS_FRAMEBUFFER_PATTERN_H

#include "../drv/framebuffer.h"

inline void framebuffer_test_pattern(framebuffer::Surface surface,
                                     unsigned variant)
{
    const framebuffer::Color background = variant == 0u ? 0x03u : 0x1cu;
    framebuffer::clear(surface, background);

    framebuffer::fill_rect(surface, 0, 0, framebuffer::kWidth, 1, 0xefu);
    framebuffer::fill_rect(surface, 0,
                           static_cast<int>(framebuffer::kHeight) - 1,
                           framebuffer::kWidth, 1, 0xffu);
    framebuffer::fill_rect(surface, 0, 1, 4,
                           static_cast<int>(framebuffer::kHeight) - 2, 0xffu);
    framebuffer::fill_rect(surface,
                           static_cast<int>(framebuffer::kWidth) - 4, 1, 4,
                           static_cast<int>(framebuffer::kHeight) - 2, 0xffu);

    for (unsigned digit = 0; digit <= 9u; ++digit) {
        framebuffer::digit(surface, 16 + static_cast<int>(digit) * 12, 16,
                           digit, 1u, 0xffu);
    }
    framebuffer::number(surface, 20, 70, 2048u, 2u, 0xffu);
    framebuffer::number(surface, 20, 120, 0u, 3u, 0xffu);

    framebuffer::fill_rect(surface, -2, 200, 7, 3, 0xe0u);
    framebuffer::fill_rect(surface, 797, 599, 7, 3, 0x1cu);
    framebuffer::pixel(surface, 1, 300, 0xe0u);
    framebuffer::pixel(surface, 2, 300, 0x1cu);
    framebuffer::pixel(surface, 3, 300, 0x03u);

    if (variant != 0u) {
        framebuffer::fill_rect(surface, 100, 250, 17, 9, 0xe0u);
        framebuffer::number(surface, 200, 200, 0xffffffffu, 1u, 0xffu);
    }
}

#endif  // LA32R_SW_TESTS_FRAMEBUFFER_PATTERN_H
