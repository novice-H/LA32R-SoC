// ---------------------------------------------------------------------------
// vga_pattern.c —— 生成 VGA 测试图案（双帧，用于翻页测试）
//
// 产物（在当前目录）：
//   fb0.bin       480000 字节，FB0 的字节内容（1 字节/像素，RGB332）
//   fb1.bin       480000 字节，FB1 的字节内容（另一幅画面）
//   expected.ppm  由 fb0 展开的 RGB888 预期图（P6）
//   expected1.ppm 由 fb1 展开的 RGB888 预期图（P6）
//
// 两帧布局相同、内容不同，用来验证 fb_sel 翻页：新帧必须整帧来自 FB1。
// 配色取自 docs/design.md 2.2.7.4：背景 0x6D、色块 0xEF、文字 0x00
// ---------------------------------------------------------------------------
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define W 800
#define H 600

#define COL_BG   0x6D
#define COL_TILE 0xEF
#define COL_TEXT 0x00
#define COL_RED  0xE0

static uint8_t fb[W * H];

// 5x7 字模（仅数字 0-9）：每字符 5 字节，一字节一列，bit0 为最上一行
static const uint8_t FONT5x7[10][5] = {
    {0x3E, 0x51, 0x49, 0x45, 0x3E}, // 0
    {0x00, 0x42, 0x7F, 0x40, 0x00}, // 1
    {0x42, 0x61, 0x51, 0x49, 0x46}, // 2
    {0x21, 0x41, 0x45, 0x4B, 0x31}, // 3
    {0x18, 0x14, 0x12, 0x7F, 0x10}, // 4
    {0x27, 0x45, 0x45, 0x45, 0x39}, // 5
    {0x3C, 0x4A, 0x49, 0x49, 0x30}, // 6
    {0x01, 0x71, 0x09, 0x05, 0x03}, // 7
    {0x36, 0x49, 0x49, 0x49, 0x36}, // 8
    {0x06, 0x49, 0x49, 0x29, 0x1E}, // 9
};

static void put_px(int x, int y, uint8_t c) {
    if (x >= 0 && x < W && y >= 0 && y < H) fb[y * W + x] = c;
}

static void fill_rect(int x, int y, int w, int h, uint8_t c) {
    for (int j = 0; j < h; j++)
        for (int i = 0; i < w; i++) put_px(x + i, y + j, c);
}

static int number_width(int val, int scale) {
    int n = 1, v = val;
    while (v >= 10) { v /= 10; n++; }
    return n * 5 * scale + (n - 1) * scale;
}

static void draw_number(int x, int y, int val, int scale, uint8_t color) {
    char buf[16];
    snprintf(buf, sizeof buf, "%d", val);
    int cx = x;
    for (const char *p = buf; *p; p++) {
        int d = *p - '0';
        if (d < 0 || d > 9) continue;
        for (int col = 0; col < 5; col++)
            for (int row = 0; row < 7; row++)
                if ((FONT5x7[d][col] >> row) & 1)
                    fill_rect(cx + col * scale, y + row * scale, scale, scale, color);
        cx += 6 * scale;
    }
}

// 两幅画面共用布局，只换内容/颜色，方便逐像素对比时定位差异
static void draw_frame(int variant) {
    static const int board0[4][4] = {
        {2,    4,    8,    16},
        {32,   64,   128,  256},
        {512,  1024, 2048, 0},
        {2,    4,    8,    16},
    };
    static const int board1[4][4] = {
        {16,   8,    4,    2},
        {256,  128,  64,   32},
        {0,    2048, 1024, 512},
        {16,   8,    4,    2},
    };

    memset(fb, COL_BG, sizeof fb);

    // 外边框
    fill_rect(0, 0, W, 2, COL_TILE);
    fill_rect(0, H - 2, W, 2, COL_TILE);
    fill_rect(0, 0, 2, H, COL_TILE);
    fill_rect(W - 2, 0, 2, H, COL_TILE);

    // 标题：第 1 帧米白，第 2 帧红色（肉眼一眼能区分翻页是否生效）
    const int title_scale = 8;
    int tw = number_width(2048, title_scale);
    draw_number((W - tw) / 2, 24, 2048, title_scale,
                variant == 0 ? COL_TILE : COL_RED);

    // 4x4 棋盘
    const int tile = 100, gap = 12, cell = tile + gap;
    const int bw = 4 * tile + 5 * gap;
    const int bh = bw;
    const int x0 = (W - bw) / 2;
    const int y0 = 118;
    const int num_scale = 4;

    if (x0 < 4 || y0 + bh > H - 4) {
        fprintf(stderr, "布局越界: x0=%d y0=%d bh=%d H=%d\n", x0, y0, bh, H);
        exit(1);
    }

    for (int r = 0; r < 4; r++) {
        for (int c = 0; c < 4; c++) {
            int v = (variant == 0) ? board0[r][c] : board1[r][c];
            int tx = x0 + gap + c * cell;
            int ty = y0 + gap + r * cell;
            if (v == 0) continue;
            fill_rect(tx, ty, tile, tile, COL_TILE);
            int nw = number_width(v, num_scale);
            int nh = 7 * num_scale;
            draw_number(tx + (tile - nw) / 2, ty + (tile - nh) / 2, v, num_scale, COL_TEXT);
        }
    }

    // FB1 独有标记：覆盖最左上 4x2 像素（正好是第 0 个 32 位字），
    // 让翻页测试能发现"首字仍来自旧缓冲"的预取问题。
    if (variant == 1) {
        fill_rect(0, 0, 4, 2, COL_RED);
    }

    // 四角标记：用来快速定位首行/末行/边沿
    fill_rect(2, H - 10, 8, 8, 0xFF);
    fill_rect(W - 10, H - 10, 8, 8, 0x00);
    fill_rect(2, 32, 8, 8, COL_RED);
    if (variant == 1) fill_rect(W - 10, 32, 8, 8, 0x1C);   // 第 2 帧独有的角标
}

static int write_files(const char *fb_path, const char *ppm_path) {
    FILE *f = fopen(fb_path, "wb");
    if (!f) { perror(fb_path); return -1; }
    if (fwrite(fb, 1, sizeof fb, f) != sizeof fb) { perror("fwrite"); fclose(f); return -1; }
    fclose(f);

    f = fopen(ppm_path, "wb");
    if (!f) { perror(ppm_path); return -1; }
    fprintf(f, "P6\n%d %d\n255\n", W, H);
    for (int i = 0; i < W * H; i++) {
        uint8_t p = fb[i];
        unsigned r = ((p >> 5) & 0x7) * 255u / 7u;
        unsigned g = ((p >> 2) & 0x7) * 255u / 7u;
        unsigned b = (p & 0x3) * 255u / 3u;
        fputc((int)r, f); fputc((int)g, f); fputc((int)b, f);
    }
    fclose(f);
    return 0;
}

static void report(const char *name) {
    int n_bg = 0, n_tile = 0, n_text = 0, n_other = 0;
    for (int i = 0; i < W * H; i++) {
        switch (fb[i]) {
            case COL_BG:   n_bg++;   break;
            case COL_TILE: n_tile++; break;
            case COL_TEXT: n_text++; break;
            default:       n_other++; break;
        }
    }
    printf("%s: 背景 %d, 色块 %d, 文字 %d, 其它 %d\n", name, n_bg, n_tile, n_text, n_other);
}

int main(void) {
    draw_frame(0);
    if (write_files("fb0.bin", "expected.ppm") != 0) return 1;
    report("FB0");

    draw_frame(1);
    if (write_files("fb1.bin", "expected1.ppm") != 0) return 1;
    report("FB1");

    printf("尺寸: %d x %d, 每帧 %d 字节\n", W, H, W * H);
    return 0;
}
