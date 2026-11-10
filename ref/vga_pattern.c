// ---------------------------------------------------------------------------
// vga_pattern.c —— 生成 VGA 测试图案
//
// 产物（在当前目录）：
//   fb0.bin       480000 字节，就是 FB0 的字节内容（1 字节/像素，RGB332）
//   expected.ppm  由同一份字节展开成 RGB888 的"预期图片"（P6）
//
// 这个程序扮演"在 PC 上编译运行的游戏绘制代码"：它把画面写进帧缓冲，
// 仿真侧则把同一份 fb0.bin 灌进 RAM，由 RTL 扫描出来。两者应逐像素一致。
//
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

static int write_ppm(const char *path) {
    FILE *f = fopen(path, "wb");
    if (!f) { perror(path); return -1; }
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

int main(void) {
    // 1) 背景
    memset(fb, COL_BG, sizeof fb);

    // 2) 外边框（2 像素），便于检查边沿与地址映射是否错位
    fill_rect(0, 0, W, 2, COL_TILE);
    fill_rect(0, H - 2, W, 2, COL_TILE);
    fill_rect(0, 0, 2, H, COL_TILE);
    fill_rect(W - 2, 0, 2, H, COL_TILE);

    // 3) 标题 "2048"（scale 8）
    const int title_scale = 8;
    const int title = 2048;
    int tw = number_width(title, title_scale);
    draw_number((W - tw) / 2, 24, title, title_scale, COL_TILE);

    // 4) 4x4 棋盘（600 格 / 空隙 12 / 色块 100）
    static const int board[4][4] = {
        {2,    4,    8,    16},
        {32,   64,   128,  256},
        {512,  1024, 2048, 0},
        {2,    4,    8,    16},
    };
    const int tile = 100, gap = 12, cell = tile + gap;
    const int bw = 4 * tile + 5 * gap;          // 460
    const int bh = bw;
    const int x0 = (W - bw) / 2;                // 170
    const int y0 = 118;
    const int num_scale = 4;

    if (x0 < 4 || y0 + bh > H - 4) {
        fprintf(stderr, "布局越界: x0=%d y0=%d bh=%d H=%d\n", x0, y0, bh, H);
        return 1;
    }

    for (int r = 0; r < 4; r++) {
        for (int c = 0; c < 4; c++) {
            int v = board[r][c];
            int tx = x0 + gap + c * cell;
            int ty = y0 + gap + r * cell;
            if (v == 0) continue;               // 空格：保留背景色
            fill_rect(tx, ty, tile, tile, COL_TILE);
            int nw = number_width(v, num_scale);
            int nh = 7 * num_scale;
            draw_number(tx + (tile - nw) / 2, ty + (tile - nh) / 2, v, num_scale, COL_TEXT);
        }
    }

    // 5) 底部标记：左下角 8x8 纯色小块 = 0xFF（白），右下角 = 0x00，用于快速定位首行/末行
    fill_rect(2, H - 10, 8, 8, 0xFF);
    fill_rect(W - 10, H - 10, 8, 8, 0x00);
    fill_rect(2, 2 + 30, 8, 8, 0xE0);           // 纯红（左上，检查行首）

    // 6) 输出
    FILE *f = fopen("fb0.bin", "wb");
    if (!f) { perror("fb0.bin"); return 1; }
    if (fwrite(fb, 1, sizeof fb, f) != sizeof fb) { perror("fwrite"); fclose(f); return 1; }
    fclose(f);

    if (write_ppm("expected.ppm") != 0) return 1;

    // 7) 统计
    int n_bg = 0, n_tile = 0, n_text = 0, n_other = 0;
    for (int i = 0; i < W * H; i++) {
        switch (fb[i]) {
            case COL_BG:   n_bg++;   break;
            case COL_TILE: n_tile++; break;
            case COL_TEXT: n_text++; break;
            default:       n_other++; break;
        }
    }
    printf("fb0.bin       : %d x %d = %d 字节\n", W, H, W * H);
    printf("expected.ppm  : RGB888 展开\n");
    printf("配色统计      : 背景 %d, 色块 %d, 文字 %d, 其它 %d\n", n_bg, n_tile, n_text, n_other);

    return 0;
}
