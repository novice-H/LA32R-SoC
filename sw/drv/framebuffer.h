#ifndef LA32R_DRV_FRAMEBUFFER_H
#define LA32R_DRV_FRAMEBUFFER_H

#include <cstdint>

namespace framebuffer {

constexpr int kWidth = 800;
constexpr int kHeight = 600;
constexpr std::uint32_t kWords = 120000;
// 用 ExtRAM 的 0xA000_0000 别名：DMW1 下 MAT=0（不可缓存），
// 开 I/D-Cache 时 VGA 也能立即读到 CPU 写入的像素。
constexpr std::uintptr_t kBuffer0 = 0xa0000000;
constexpr std::uintptr_t kBuffer1 = 0xa0080000;

using Color = std::uint8_t;

constexpr Color rgb(std::uint8_t r, std::uint8_t g, std::uint8_t b) {
    return static_cast<Color>((r & 0xe0u) | ((g >> 3) & 0x1cu) | (b >> 6));
}

struct Surface {
    volatile std::uint32_t* words;
};

struct Frame {
    Surface surface;
    std::uint32_t index;
    bool acquired;
};

// Raster functions use aligned word accesses on a fixed 800x600 surface.
// digit/number draw only foreground pixels; scale is an integer in [1,16].
void clear(Surface surface, Color color);
void pixel(Surface surface, int x, int y, Color color);
void fill_rect(Surface surface, int x, int y, int width, int height,
               Color color);
void digit(Surface surface, int x, int y, unsigned value, unsigned scale,
           Color color);
void number(Surface surface, int x, int y, std::uint32_t value,
            unsigned scale, Color color);

// One submitting thread owns the hardware flip protocol. Draw only on the
// acquired back surface. Current CPU data mappings must remain uncached.
bool begin(Frame& frame, std::uint32_t timeout_ms = 100);
// After a submitted request, acquired is cleared even on timeout. Hardware
// may finish it later; begin waits for idle and acquires the next back buffer.
bool present(Frame& frame, std::uint32_t timeout_ms = 100);

}  // namespace framebuffer

#endif  // LA32R_DRV_FRAMEBUFFER_H
