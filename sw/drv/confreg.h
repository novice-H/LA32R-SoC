#ifndef LA32R_DRV_CONFREG_H
#define LA32R_DRV_CONFREG_H

#include <cstdint>

namespace confreg {

enum class Register : std::uint32_t {
    Step = 0x00,
    Status = 0x04,
    Buttons = 0x08,
    Keys = 0x0c,
    Time = 0x10,
    Random = 0x14,
    Framebuffer = 0x18,
};

constexpr std::uintptr_t kBase = 0xbfd00000;
constexpr std::uint32_t kButtonMask = 0xf;
constexpr std::uint32_t kGameEnable = 1;
constexpr std::uint32_t kAiEnable = 2;
constexpr std::uint32_t kStatusWin = 1u << 13;
constexpr std::uint32_t kStatusLose = 1u << 14;
constexpr std::uint32_t kStatusAi = 1u << 15;
constexpr std::uint32_t kFlipRequest = 1;
constexpr std::uint32_t kDisplayedBuffer = 1u << 16;

// Aligned 32-bit MMIO for the current reset-time uncached CPU configuration.
inline std::uint32_t read(Register reg) {
    const auto address = kBase + static_cast<std::uintptr_t>(reg);
    return *reinterpret_cast<volatile const std::uint32_t*>(address);
}

inline void write(Register reg, std::uint32_t value) {
    const auto address = kBase + static_cast<std::uintptr_t>(reg);
    *reinterpret_cast<volatile std::uint32_t*>(address) = value;
}

}  // namespace confreg

#endif  // LA32R_DRV_CONFREG_H
