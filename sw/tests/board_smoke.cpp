#include <stdint.h>

extern "C" {
volatile uint32_t smoke_data = 0x12345678u;
volatile uint32_t smoke_bss[4];
volatile uint32_t smoke_result;
volatile uint32_t smoke_stack_checksum;
}

static volatile uint32_t& confreg(uint32_t word_offset)
{
    return reinterpret_cast<volatile uint32_t*>(0xbfd00000u)[word_offset];
}

static void fail(uint32_t step)
{
    confreg(0) = step;
    confreg(1) = 0x4000u;
    for (;;) {
        __asm__ volatile("" ::: "memory");
    }
}

__attribute__((noinline)) static uint32_t stack_check(void)
{
    volatile uint32_t words[4];
    words[0] = 0x11u;
    words[1] = 0x22u;
    words[2] = 0x33u;
    words[3] = 0x44u;
    return words[0] + words[1] + words[2] + words[3];
}

extern "C" int main(void)
{
    if (smoke_data != 0x12345678u) {
        fail(1u);
    }
    for (uint32_t i = 0; i < 4u; ++i) {
        if (smoke_bss[i] != 0u) {
            fail(2u);
        }
    }
    const uint32_t checksum = stack_check();
    if (checksum != 0xaau) {
        fail(3u);
    }

    /* FB0 marker pattern consumed by the board smoke-test pixel check. */
    volatile uint32_t *const fb0 =
        reinterpret_cast<volatile uint32_t *>(0x1c400000u);
    for (uint32_t i = 0; i < 200u; ++i) {
        fb0[i] = 0xefefefefu;
    }
    fb0[200] = 0xe0e0e0e0u;

    smoke_stack_checksum = checksum;
    smoke_result = 0x600d2048u;
    confreg(0) = 1234u;
    confreg(1) = 0x2000u;
    return 0;
}
