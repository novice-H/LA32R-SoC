// ---------------------------------------------------------------------------
// tb_main.cpp —— VGA 扫描通道的 Verilator testbench
//
// 只把 DUT 当成一台"显示器"：采样 video_de / hsync / vsync / RGB332，
// 不看内部计数器。画面与预期一致即说明时序、地址、字节序都对。
//
// 模式：
//   默认      采集 FB0 一帧 → actual.ppm
//   +flip     先采 FB0 一帧，再在 vsync 处把 fb_sel 翻到 FB1，采第二帧
//             → actual0.ppm / actual1.ppm（用于验证双缓冲翻页）
//
// 用法：
//   ./obj_vga/Vtb_vga_top             # 单帧
//   ./obj_vga/Vtb_vga_top +flip       # 翻页：两帧
//   ./obj_vga/Vtb_vga_top +trace-cycles=6000   # 只跑若干拍并导出 vga.vcd
// ---------------------------------------------------------------------------
#include "Vtb_vga_top.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <vector>

#if VM_TRACE
# include "verilated_vcd_c.h"
#endif

static const int H_ACTIVE = 800;
static const int V_ACTIVE = 600;
static const long H_TOTAL = 1040;
static const long V_TOTAL = 666;
static const long FRAME_PIXELS = (long)H_ACTIVE * V_ACTIVE;

static int write_ppm(const char* path, const std::vector<uint8_t>& frame) {
    FILE* f = std::fopen(path, "wb");
    if (!f) { std::perror(path); return -1; }
    std::fprintf(f, "P6\n%d %d\n255\n", H_ACTIVE, V_ACTIVE);
    for (size_t i = 0; i < frame.size(); i++) {
        unsigned p = frame[i];
        unsigned r = ((p >> 5) & 0x7) * 255u / 7u;
        unsigned g = ((p >> 2) & 0x7) * 255u / 7u;
        unsigned b = (p & 0x3) * 255u / 3u;
        std::fputc((int)r, f); std::fputc((int)g, f); std::fputc((int)b, f);
    }
    std::fclose(f);
    std::printf("%-14s: %d x %d 已写出\n", path, H_ACTIVE, V_ACTIVE);
    return 0;
}

static int check_lines(const char* tag, const std::vector<int>& lines) {
    int good = 0, bad = 0;
    for (int n : lines) {
        if (n == H_ACTIVE) good++;
        else if (n != 0) bad++;
    }
    std::printf("%s 行有效像素 : %d 行完整, %d 行异常\n", tag, good, bad);
    return bad;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtb_vga_top* dut = new Vtb_vga_top;

    long trace_cycles = 0;
    bool flip = false;
    for (int i = 1; i < argc; i++) {
        if (std::strncmp(argv[i], "+trace-cycles=", 14) == 0) trace_cycles = std::atol(argv[i] + 14);
        if (std::strcmp(argv[i], "+flip") == 0) flip = true;
    }

#if VM_TRACE
    VerilatedVcdC* tfp = nullptr;
    if (trace_cycles > 0) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        dut->trace(tfp, 99);
        tfp->open("vga.vcd");
    }
#endif

    dut->clk = 0; dut->rst = 1; dut->fb_sel = 0;
    for (int i = 0; i < 4; i++) { dut->clk = 1; dut->eval(); dut->clk = 0; dut->eval(); }
    dut->rst = 0;

    // phase: 0=等第 2 个 vsync，1=采第 1 帧，2=等翻页，3=采第 2 帧，4=完成
    int phase = 0;
    int vs_rises = 0;
    bool prev_hs = false, prev_vs = false;
    int hs_hi = 0, vs_hi = 0;
    long hs_width = -1, vs_width = -1, hs_period = -1, vs_period = -1;
    long last_h_rise = -1, last_v_rise = -1;
    long cyc = 0;
    int cur_line = 0;

    std::vector<uint8_t> f0, f1;
    std::vector<int> lines0, lines1;
    f0.reserve(FRAME_PIXELS);
    f1.reserve(FRAME_PIXELS);

    for (;;) {
        dut->clk = 1; dut->eval();
        cyc++;
#if VM_TRACE
        if (tfp) tfp->dump((vluint64_t)(cyc * 20000));
#endif

        bool hs = dut->vga_hsync;
        bool vs = dut->vga_vsync;
        bool de = dut->vga_de;
        uint8_t pix = (uint8_t)((dut->vga_red << 5) | (dut->vga_green << 2) | dut->vga_blue);

        if (hs) hs_hi++; else { if (hs_hi) { hs_width = hs_hi; hs_hi = 0; } }
        if (vs) vs_hi++; else { if (vs_hi) { vs_width = vs_hi; vs_hi = 0; } }
        if (hs && !prev_hs) { if (last_h_rise >= 0) hs_period = cyc - last_h_rise; last_h_rise = cyc; }
        if (vs && !prev_vs) { if (last_v_rise >= 0) vs_period = cyc - last_v_rise; last_v_rise = cyc; }

        if (vs && !prev_vs) {
            vs_rises++;
            if (phase == 0 && vs_rises == 2) {
                phase = 1;
                f0.clear(); lines0.clear(); cur_line = 0;
            } else if (flip && phase == 2) {
                dut->fb_sel = 1;            // 模拟 confreg 在 vsync 处翻页
                phase = 3;
                f1.clear(); lines1.clear(); cur_line = 0;
            }
        }

        if (hs && !prev_hs && (phase == 1 || phase == 3)) {
            (phase == 1 ? lines0 : lines1).push_back(cur_line);
            cur_line = 0;
        }

        if (de) {
            if (phase == 1) {
                f0.push_back(pix); cur_line++;
                if ((long)f0.size() == FRAME_PIXELS) {
                    lines0.push_back(cur_line);
                    phase = flip ? 2 : 4;
                }
            } else if (phase == 3) {
                f1.push_back(pix); cur_line++;
                if ((long)f1.size() == FRAME_PIXELS) {
                    lines1.push_back(cur_line);
                    phase = 4;
                }
            }
        }

        if (phase == 4) break;
        if (trace_cycles > 0 && cyc >= trace_cycles) break;

        dut->clk = 0; dut->eval();
        prev_hs = hs;
        prev_vs = vs;
    }

    if (trace_cycles > 0 && cyc >= trace_cycles) {
#if VM_TRACE
        if (tfp) { tfp->close(); delete tfp; tfp = nullptr; }
        std::printf("trace: %ld 拍已导出 vga.vcd\n", cyc);
#endif
        dut->final(); delete dut;
        return 0;
    }

#if VM_TRACE
    if (tfp) { tfp->close(); delete tfp; }
#endif

    bool ok = true;
    if (!flip) {
        if ((long)f0.size() != FRAME_PIXELS) {
            std::printf("FAIL: 帧采集不完整 %zu / %ld\n", f0.size(), FRAME_PIXELS);
            ok = false;
        } else if (write_ppm("actual.ppm", f0) != 0) {
            ok = false;
        }
    } else {
        bool ok0 = ((long)f0.size() == FRAME_PIXELS);
        bool ok1 = ((long)f1.size() == FRAME_PIXELS);
        if (!ok0) { std::printf("FAIL: FB0 帧不完整 %zu / %ld\n", f0.size(), FRAME_PIXELS); ok = false; }
        if (!ok1) { std::printf("FAIL: FB1 帧不完整 %zu / %ld\n", f1.size(), FRAME_PIXELS); ok = false; }
        if (ok0 && write_ppm("actual0.ppm", f0) != 0) ok = false;
        if (ok1 && write_ppm("actual1.ppm", f1) != 0) ok = false;
    }

    int bad = 0;
    bad += check_lines("FB0", lines0);
    if (flip) bad += check_lines("FB1", lines1);

    std::printf("\n=== VGA 时序报告（只依据 de/hsync/vsync 测量）===\n");
    std::printf("仿真拍数      : %ld  (%.3f ms @50MHz)\n", cyc, cyc * 20.0 / 1000.0);
    std::printf("hsync 宽度    : %ld  (期望 120)  %s\n", hs_width, hs_width == 120 ? "PASS" : "FAIL");
    std::printf("hsync 周期    : %ld  (期望 %ld) %s\n", hs_period, H_TOTAL, hs_period == H_TOTAL ? "PASS" : "FAIL");
    std::printf("vsync 宽度    : %ld  (期望 %ld) %s\n", vs_width, 6 * H_TOTAL, vs_width == 6 * H_TOTAL ? "PASS" : "FAIL");
    std::printf("vsync 周期    : %ld  (期望 %ld) %s\n", vs_period, V_TOTAL * H_TOTAL, vs_period == V_TOTAL * H_TOTAL ? "PASS" : "FAIL");
    std::printf("刷新率        : %.2f Hz\n", 50e6 / ((double)H_TOTAL * V_TOTAL));

    if (hs_width != 120 || hs_period != H_TOTAL || vs_width != 6 * H_TOTAL ||
        vs_period != V_TOTAL * H_TOTAL || bad != 0) ok = false;

    std::printf("\n结果: %s\n", ok ? "PASS（时序正确，图像已导出）" : "FAIL");
    dut->final(); delete dut;
    return ok ? 0 : 1;
}
