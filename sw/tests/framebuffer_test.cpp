#include "../drv/framebuffer.h"
#include "framebuffer_pattern.h"

#include <stdint.h>

#include <algorithm>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

namespace {

const unsigned kWidth = framebuffer::kWidth;
const unsigned kHeight = framebuffer::kHeight;
const unsigned kWords = framebuffer::kWords;
const uint32_t kGuardBefore = 0x13579bdfu;
const uint32_t kGuardAfter = 0x2468ace0u;

/* Independent 5x7 font evidence, expanded to an 8x16 cell below. */
const uint8_t kFont5x7[10][7] = {
    {0x0e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e},
    {0x04, 0x0c, 0x04, 0x04, 0x04, 0x04, 0x0e},
    {0x0e, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1f},
    {0x1e, 0x01, 0x01, 0x0e, 0x01, 0x01, 0x1e},
    {0x02, 0x06, 0x0a, 0x12, 0x1f, 0x02, 0x02},
    {0x1f, 0x10, 0x10, 0x1e, 0x01, 0x01, 0x1e},
    {0x0e, 0x10, 0x10, 0x1e, 0x11, 0x11, 0x0e},
    {0x1f, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08},
    {0x0e, 0x11, 0x11, 0x0e, 0x11, 0x11, 0x0e},
    {0x0e, 0x11, 0x11, 0x0f, 0x01, 0x01, 0x0e},
};

class Reference {
public:
    explicit Reference(uint8_t initial)
        : pixels_(static_cast<size_t>(kWidth) * kHeight, initial) {}

    uint8_t get(unsigned x, unsigned y) const
    {
        return pixels_[static_cast<size_t>(y) * kWidth + x];
    }

    void clear(uint8_t color)
    {
        for (size_t i = 0; i < pixels_.size(); ++i) {
            pixels_[i] = color;
        }
    }

    void pixel(int x, int y, uint8_t color)
    {
        if (x >= 0 && y >= 0 && x < static_cast<int>(kWidth) &&
            y < static_cast<int>(kHeight)) {
            pixels_[static_cast<size_t>(y) * kWidth +
                    static_cast<unsigned>(x)] = color;
        }
    }

    void fill_rect(int x, int y, int width, int height, uint8_t color)
    {
        if (width <= 0 || height <= 0) {
            return;
        }
        const int64_t x0 = x;
        const int64_t y0 = y;
        const int64_t x1 = x0 + static_cast<int64_t>(width);
        const int64_t y1 = y0 + static_cast<int64_t>(height);
        const int64_t left = x0 < 0 ? 0 : x0;
        const int64_t top = y0 < 0 ? 0 : y0;
        const int64_t right = x1 > kWidth ? kWidth : x1;
        const int64_t bottom = y1 > kHeight ? kHeight : y1;
        for (int64_t py = top; py < bottom; ++py) {
            for (int64_t px = left; px < right; ++px) {
                pixels_[static_cast<size_t>(py) * kWidth +
                        static_cast<size_t>(px)] = color;
            }
        }
    }

    void digit(int x, int y, unsigned digit_value, unsigned scale,
               uint8_t color)
    {
        if (digit_value > 9u || scale == 0u || scale > 16u) {
            return;
        }
        for (unsigned row = 0; row < 7u; ++row) {
            for (unsigned col = 0; col < 5u; ++col) {
                if ((kFont5x7[digit_value][row] & (1u << (4u - col))) == 0u) {
                    continue;
                }
                const int64_t px = static_cast<int64_t>(x) +
                                   static_cast<int64_t>(col + 1u) * scale;
                const int64_t py = static_cast<int64_t>(y) +
                                   static_cast<int64_t>(row * 2u + 1u) * scale;
                for (unsigned sy = 0; sy < 2u * scale; ++sy) {
                    for (unsigned sx = 0; sx < scale; ++sx) {
                        const int64_t dx = px + sx;
                        const int64_t dy = py + sy;
                        if (dx >= 0 && dy >= 0 && dx < kWidth && dy < kHeight) {
                            pixels_[static_cast<size_t>(dy) * kWidth +
                                    static_cast<size_t>(dx)] = color;
                        }
                    }
                }
            }
        }
    }

    void number(int x, int y, uint32_t value, unsigned scale, uint8_t color)
    {
        if (scale == 0u || scale > 16u) {
            return;
        }
        char digits[10];
        unsigned count = 0;
        do {
            digits[count++] = static_cast<char>('0' + value % 10u);
            value /= 10u;
        } while (value != 0u);
        for (unsigned i = 0; i < count; ++i) {
            const int64_t dx = static_cast<int64_t>(x) +
                               static_cast<int64_t>(count - i - 1u) * 8u * scale;
            if (dx >= std::numeric_limits<int>::min() &&
                dx <= std::numeric_limits<int>::max()) {
                digit(static_cast<int>(dx), y,
                      static_cast<unsigned>(digits[i] - '0'), scale, color);
            }
        }
    }

    const std::vector<uint8_t>& pixels() const { return pixels_; }

private:
    std::vector<uint8_t> pixels_;
};

struct Fixture {
    explicit Fixture(uint8_t initial)
        : words_(kWords + 2u), reference(initial)
    {
        words_[0] = kGuardBefore;
        words_[kWords + 1u] = kGuardAfter;
        for (unsigned i = 0; i < kWords; ++i) {
            uint32_t word = 0;
            for (unsigned lane = 0; lane < 4u; ++lane) {
                const unsigned x = (i * 4u + lane) % kWidth;
                const unsigned y = (i * 4u + lane) / kWidth;
                const uint8_t color = static_cast<uint8_t>(
                    initial + (x * 17u + y * 29u + lane * 43u));
                word |= static_cast<uint32_t>(color) << (lane * 8u);
                reference.pixel(static_cast<int>(x), static_cast<int>(y), color);
            }
            words_[i + 1u] = word;
        }
        surface.words = &words_[1];
    }

    void reset(uint8_t color)
    {
        reference.clear(color);
        for (unsigned i = 0; i < kWords; ++i) {
            words_[i + 1u] = static_cast<uint32_t>(color) * 0x01010101u;
        }
    }

    uint8_t actual(unsigned x, unsigned y) const
    {
        const unsigned word_index = y * (kWidth / 4u) + x / 4u;
        const unsigned lane = x & 3u;
        return static_cast<uint8_t>(words_[word_index + 1u] >> (lane * 8u));
    }

    bool matches(const std::string& label)
    {
        if (words_[0] != kGuardBefore || words_[kWords + 1u] != kGuardAfter) {
            report(label + ": guard word changed");
            return false;
        }
        for (unsigned y = 0; y < kHeight; ++y) {
            for (unsigned x = 0; x < kWidth; ++x) {
                const unsigned lane = x & 3u;
                const unsigned word_index = y * (kWidth / 4u) + x / 4u;
                const uint8_t actual = static_cast<uint8_t>(
                    words_[word_index + 1u] >> (lane * 8u));
                const uint8_t expected = reference.get(x, y);
                if (actual != expected) {
                    std::ostringstream message;
                    message << label << ": pixel (" << x << ',' << y
                            << ") expected 0x" << std::hex
                            << static_cast<unsigned>(expected) << " got 0x"
                            << static_cast<unsigned>(actual);
                    report(message.str());
                    return false;
                }
            }
        }
        return true;
    }

    static void report(const std::string& text)
    {
        ++failures();
        std::cerr << "FAIL: " << text << '\n';
    }

    static unsigned& failures()
    {
        static unsigned count = 0;
        return count;
    }

    std::vector<uint32_t> words_;
    Reference reference;
    framebuffer::Surface surface;
};

unsigned& failure_count() { return Fixture::failures(); }

bool same(Fixture& fixture, const std::string& what)
{
    return fixture.matches(what);
}

void reference_pattern(Reference& ref, unsigned variant)
{
    ref.clear(variant == 0u ? 0x03u : 0x1cu);
    ref.fill_rect(0, 0, static_cast<int>(kWidth), 1, 0xefu);
    ref.fill_rect(0, static_cast<int>(kHeight) - 1,
                  static_cast<int>(kWidth), 1, 0xffu);
    ref.fill_rect(0, 1, 4, static_cast<int>(kHeight) - 2, 0xffu);
    ref.fill_rect(static_cast<int>(kWidth) - 4, 1, 4,
                  static_cast<int>(kHeight) - 2, 0xffu);
    for (unsigned d = 0; d <= 9u; ++d) {
        ref.digit(16 + static_cast<int>(d) * 12, 16, d, 1u, 0xffu);
    }
    ref.number(20, 70, 2048u, 2u, 0xffu);
    ref.number(20, 120, 0u, 3u, 0xffu);
    ref.fill_rect(-2, 200, 7, 3, 0xe0u);
    ref.fill_rect(797, 599, 7, 3, 0x1cu);
    ref.pixel(1, 300, 0xe0u);
    ref.pixel(2, 300, 0x1cu);
    ref.pixel(3, 300, 0x03u);
    if (variant != 0u) {
        ref.fill_rect(100, 250, 17, 9, 0xe0u);
        ref.number(200, 200, 0xffffffffu, 1u, 0xffu);
    }
}

void run_unit_checks()
{
    Fixture f(0x5au);

    if (framebuffer::rgb(0u, 0u, 0u) != 0x00u ||
        framebuffer::rgb(255u, 255u, 255u) != 0xffu ||
        framebuffer::rgb(255u, 0u, 0u) != 0xe0u ||
        framebuffer::rgb(0u, 255u, 0u) != 0x1cu ||
        framebuffer::rgb(0u, 0u, 255u) != 0x03u) {
        Fixture::report("RGB888 to RGB332 conversion");
    }

    framebuffer::pixel(f.surface, 0, 0, 0xe0u);
    f.reference.pixel(0, 0, 0xe0u);
    same(f, "pixel lane 0");
    framebuffer::pixel(f.surface, 1, 0, 0x1cu);
    f.reference.pixel(1, 0, 0x1cu);
    same(f, "pixel lane 1");
    framebuffer::pixel(f.surface, 2, 0, 0x03u);
    f.reference.pixel(2, 0, 0x03u);
    same(f, "pixel lane 2");
    framebuffer::pixel(f.surface, 3, 0, 0xffu);
    f.reference.pixel(3, 0, 0xffu);
    same(f, "pixel lane 3");

    framebuffer::fill_rect(f.surface, 3, 2, 5, 3, 0xa5u);
    f.reference.fill_rect(3, 2, 5, 3, 0xa5u);
    same(f, "rectangle crosses word lanes");
    framebuffer::pixel(f.surface, -1, 0, 0x99u);
    f.reference.pixel(-1, 0, 0x99u);
    framebuffer::pixel(f.surface, static_cast<int>(kWidth), 0, 0x99u);
    f.reference.pixel(static_cast<int>(kWidth), 0, 0x99u);
    framebuffer::pixel(f.surface, 0, static_cast<int>(kHeight), 0x99u);
    f.reference.pixel(0, static_cast<int>(kHeight), 0x99u);
    same(f, "pixel clipping");

    framebuffer::fill_rect(f.surface, -2, -1, 5, 4, 0xc3u);
    f.reference.fill_rect(-2, -1, 5, 4, 0xc3u);
    framebuffer::fill_rect(f.surface, 798, 598, 9, 8, 0x36u);
    f.reference.fill_rect(798, 598, 9, 8, 0x36u);
    same(f, "rectangle clips top-left and bottom-right");

    const int extremes[] = {std::numeric_limits<int>::min(),
                            std::numeric_limits<int>::max()};
    for (unsigned i = 0; i < 2u; ++i) {
        framebuffer::fill_rect(f.surface, extremes[i], extremes[1u - i],
                               std::numeric_limits<int>::max(),
                               std::numeric_limits<int>::max(), 0x73u);
        f.reference.fill_rect(extremes[i], extremes[1u - i],
                              std::numeric_limits<int>::max(),
                              std::numeric_limits<int>::max(), 0x73u);
    }
    framebuffer::fill_rect(f.surface, -1, -1,
                           std::numeric_limits<int>::max(),
                           std::numeric_limits<int>::max(), 0x47u);
    f.reference.fill_rect(-1, -1, std::numeric_limits<int>::max(),
                          std::numeric_limits<int>::max(), 0x47u);
    framebuffer::fill_rect(f.surface, 0, 0,
                           std::numeric_limits<int>::min(), 1, 0x92u);
    f.reference.fill_rect(0, 0, std::numeric_limits<int>::min(), 1, 0x92u);
    framebuffer::fill_rect(f.surface, 0, 0, 1,
                           std::numeric_limits<int>::min(), 0x92u);
    f.reference.fill_rect(0, 0, 1, std::numeric_limits<int>::min(), 0x92u);
    same(f, "extreme rectangle coordinates and sizes");

    std::vector<uint32_t> before(&f.surface.words[0],
                                 &f.surface.words[kWords]);
    framebuffer::fill_rect(f.surface, 10, 10, 0, 4, 0u);
    framebuffer::fill_rect(f.surface, 10, 10, -4, 4, 0u);
    framebuffer::fill_rect(f.surface, 10, 10, 4, 0, 0u);
    framebuffer::fill_rect(f.surface, 10, 10, 4, -4, 0u);
    if (!std::equal(before.begin(), before.end(), &f.surface.words[0])) {
        Fixture::report("zero or negative rectangle dimensions changed memory");
    }

    framebuffer::clear(f.surface, 0x6du);
    f.reference.clear(0x6du);
    same(f, "full-screen clear");

    for (unsigned scale = 1; scale <= 16u; ++scale) {
        const unsigned d = (scale - 1u) % 10u;
        const int x = static_cast<int>(scale * 7u) - 20;
        const int y = static_cast<int>(scale * 13u) - 30;
        framebuffer::digit(f.surface, x, y, d, scale,
                           static_cast<uint8_t>(0x80u + scale));
        f.reference.digit(x, y, d, scale,
                          static_cast<uint8_t>(0x80u + scale));
    }
    same(f, "transparent glyphs at scales 1 through 16");

    framebuffer::digit(f.surface, 0, 0, 10u, 1u, 0xffu);
    framebuffer::digit(f.surface, 0, 0, 1u, 0u, 0xffu);
    framebuffer::digit(f.surface, 0, 0, 1u, 17u, 0xffu);
    framebuffer::number(f.surface, 0, 0, 123u, 0u, 0xffu);
    framebuffer::number(f.surface, 0, 0, 123u, 17u, 0xffu);
    same(f, "invalid digit and scale are no-ops");

    const uint32_t values[] = {0u, 2048u, 0xffffffffu};
    for (unsigned i = 0; i < sizeof(values) / sizeof(values[0]); ++i) {
        for (unsigned scale = 1; scale <= 16u; scale *= 2u) {
            const int x = i == 2u ? -7 : static_cast<int>(i * 19u);
            const int y = i == 2u ? 590 : static_cast<int>(40u + scale);
            framebuffer::number(f.surface, x, y, values[i], scale,
                                static_cast<uint8_t>(0x31u + i * 29u + scale));
            f.reference.number(x, y, values[i], scale,
                               static_cast<uint8_t>(0x31u + i * 29u + scale));
        }
    }
    framebuffer::digit(f.surface, 796, 590, 8u, 4u, 0xceu);
    f.reference.digit(796, 590, 8u, 4u, 0xceu);
    same(f, "numbers, scales, and clipped glyphs");

    for (unsigned variant = 0; variant <= 1u; ++variant) {
        Fixture pattern(0u);
        framebuffer_test_pattern(pattern.surface, variant);
        reference_pattern(pattern.reference, variant);
        same(pattern, variant == 0u ? "pattern variant 0" : "pattern variant 1");
    }
}

uint8_t rgb332_to_r(uint8_t c)
{
    const uint8_t v = static_cast<uint8_t>((c >> 5u) & 7u);
    return static_cast<uint8_t>((v << 5u) | (v << 2u) | (v >> 1u));
}

uint8_t rgb332_to_g(uint8_t c)
{
    const uint8_t v = static_cast<uint8_t>((c >> 2u) & 7u);
    return static_cast<uint8_t>((v << 5u) | (v << 2u) | (v >> 1u));
}

uint8_t rgb332_to_b(uint8_t c)
{
    const uint8_t v = static_cast<uint8_t>(c & 3u);
    return static_cast<uint8_t>((v << 6u) | (v << 4u) | (v << 2u) | v);
}

bool export_variant(const std::string& directory, unsigned variant)
{
    Fixture fixture(0u);
    framebuffer_test_pattern(fixture.surface, variant);
    std::ostringstream suffix;
    suffix << variant;
    const std::string base = directory + "/expected" + suffix.str();
    std::ofstream hex((base + ".hex").c_str(), std::ios::out | std::ios::binary);
    std::ofstream ppm((base + ".ppm").c_str(), std::ios::out | std::ios::binary);
    if (!hex || !ppm) {
        std::cerr << "cannot open export files under " << directory << '\n';
        return false;
    }
    for (unsigned y = 0; y < kHeight; ++y) {
        for (unsigned word_x = 0; word_x < kWidth / 4u; ++word_x) {
            uint32_t word = 0;
            for (unsigned lane = 0; lane < 4u; ++lane) {
                word |= static_cast<uint32_t>(
                    fixture.actual(word_x * 4u + lane, y)) << (lane * 8u);
            }
            hex << std::hex << std::setw(8) << std::setfill('0') << word << '\n';
        }
    }
    ppm << "P6\n" << kWidth << ' ' << kHeight << "\n255\n";
    for (unsigned y = 0; y < kHeight; ++y) {
        for (unsigned x = 0; x < kWidth; ++x) {
            const uint8_t c = fixture.actual(x, y);
            const char rgb[3] = {static_cast<char>(rgb332_to_r(c)),
                                 static_cast<char>(rgb332_to_g(c)),
                                 static_cast<char>(rgb332_to_b(c))};
            ppm.write(rgb, sizeof(rgb));
        }
    }
    if (!hex || !ppm) {
        std::cerr << "failed while writing export files under " << directory << '\n';
        return false;
    }
    return true;
}

}  // namespace

int main(int argc, char** argv)
{
    run_unit_checks();
    if (failure_count() != 0u) {
        std::cerr << failure_count() << " framebuffer test failure(s)\n";
        return 1;
    }
    if (argc > 1) {
        if (!export_variant(argv[1], 0u) || !export_variant(argv[1], 1u)) {
            return 2;
        }
    }
    std::cout << "framebuffer tests passed\n";
    return 0;
}
