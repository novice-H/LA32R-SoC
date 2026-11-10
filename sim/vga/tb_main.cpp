// ---------------------------------------------------------------------------
// tb_main.cpp —— VGA 扫描通道的 Verilator testbench
//
// 只把 DUT 当成一台"显示器"来观测：采样 video_de / hsync / vsync / RGB332，
// 完全不看内部计数器。这样一旦重建出的画面与预期一致，时序也必然是对的。
//
// 产物（当前目录）：
//   actual.ppm   从 VGA 信号重建出的整帧（RGB888）
//   vga.vcd      仅在带 +trace-cycles=N 运行时生成
//
// 用法：
//   ./obj_vga/Vtb_vga_top                     # 正常仿真，输出 actual.ppm + 时序报告
//   ./obj_vga/Vtb_vga_top +trace-cycles=6000  # 只跑 6000 拍并导出波形
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

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtb_vga_top* dut = new Vtb_vga_top;

    long trace_cycles = 0;
    for (int i = 1; i < argc; i++) {
        if (std::strncmp(argv[i], "+trace-cycles=", 14) == 0)
            trace_cycles = std::atol(argv[i] + 14);
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

    // 复位：rst 有效 4 拍
    dut->clk = 0; dut->rst = 1; dut->fb_sel = 0;
    for (int i = 0; i < 4; i++) {
        dut->clk = 1; dut->eval();
        dut->clk = 0; dut->eval();
    }
    dut->rst = 0;

    bool prev_hs = false, prev_vs = false;
    int hs_hi = 0, vs_hi = 0;
    long hs_width = -1, vs_width = -1;
    long hs_period = -1, vs_period = -1;
    long last_h_rise = -1, last_v_rise = -1;
    int vs_rises = 0;

    bool capturing = false;
    long cyc = 0;
    std::vector<uint8_t> frame;
    frame.reserve(FRAME_PIXELS);
    std::vector<int> line_pixels;
    int cur_line = 0;

    for (;;) {
        // 一个时钟周期
        dut->clk = 1; dut->eval();
        cyc++;

#if VM_TRACE
        if (tfp) tfp->dump((vluint64_t)(cyc * 20000));   // 20 ns/拍 -> 20000 ps
#endif

        bool hs = dut->vga_hsync;
        bool vs = dut->vga_vsync;
        bool de = dut->vga_de;
        uint8_t pix = (uint8_t)((dut->vga_red << 5) | (dut->vga_green << 2) | dut->vga_blue);

        // --- 同步信号测量 ---
        if (hs) hs_hi++; else { if (hs_hi) { hs_width = hs_hi; hs_hi = 0; } }
        if (vs) vs_hi++; else { if (vs_hi) { vs_width = vs_hi; vs_hi = 0; } }
        if (hs && !prev_hs) { if (last_h_rise >= 0) hs_period = cyc - last_h_rise; last_h_rise = cyc; }
        if (vs && !prev_vs) { if (last_v_rise >= 0) vs_period = cyc - last_v_rise; last_v_rise = cyc; }

        // --- 帧边界：第 2 个 vsync 上升沿开始采集（跳过复位后的第一帧） ---
        if (vs && !prev_vs) {
            vs_rises++;
            if (vs_rises == 2) {
                capturing = true;
                frame.clear();
                line_pixels.clear();
                cur_line = 0;
            }
        }

        // --- 行边界：记录本行有效像素数 ---
        if (hs && !prev_hs && capturing) {
            line_pixels.push_back(cur_line);
            cur_line = 0;
        }

        // --- 采集有效像素 ---
        if (capturing && de) {
            frame.push_back(pix);
            cur_line++;
            if ((long)frame.size() == FRAME_PIXELS) break;
        }

        if (trace_cycles > 0 && cyc >= trace_cycles) break;

        dut->clk = 0; dut->eval();
        prev_hs = hs;
        prev_vs = vs;
    }

    // ---- 波形模式：只导出波形，不做图像检查 ----
    if (trace_cycles > 0 && cyc >= trace_cycles) {
#if VM_TRACE
        if (tfp) { tfp->close(); delete tfp; tfp = nullptr; }
        printf("trace: %ld 拍已导出 vga.vcd\n", cyc);
#endif
        dut->final();
        delete dut;
        return 0;
    }

#if VM_TRACE
    if (tfp) { tfp->close(); delete tfp; }
#endif

    // ---------------- 结果检查 ----------------
    bool ok = true;
    bool frame_done = ((long)frame.size() == FRAME_PIXELS);
    if (!frame_done) {
        printf("FAIL: 帧采集不完整，只收到 %zu / %ld 像素\n", frame.size(), FRAME_PIXELS);
        ok = false;
    }

    if (frame_done) {
        FILE* f = std::fopen("actual.ppm", "wb");
        if (!f) {
            std::perror("actual.ppm");
            ok = false;
        } else {
            std::fprintf(f, "P6\n%d %d\n255\n", H_ACTIVE, V_ACTIVE);
            for (size_t i = 0; i < frame.size(); i++) {
                unsigned p = frame[i];
                unsigned r = ((p >> 5) & 0x7) * 255u / 7u;
                unsigned g = ((p >> 2) & 0x7) * 255u / 7u;
                unsigned b = (p & 0x3) * 255u / 3u;
                std::fputc((int)r, f); std::fputc((int)g, f); std::fputc((int)b, f);
            }
            std::fclose(f);
            printf("actual.ppm    : %d x %d 已写出\n", H_ACTIVE, V_ACTIVE);
        }
    }

    int good_lines = 0, bad_lines = 0;
    for (int n : line_pixels) {
        if (n == H_ACTIVE) good_lines++;
        else if (n != 0) bad_lines++;
    }

    printf("\n=== VGA 时序报告（只依据 de/hsync/vsync 测量）===\n");
    printf("仿真拍数      : %ld  (%.3f ms @50MHz)\n", cyc, cyc * 20.0 / 1000.0);
    printf("hsync 宽度    : %ld  (期望 %d)  %s\n", hs_width, 120,
           hs_width == 120 ? "PASS" : "FAIL");
    printf("hsync 周期    : %ld  (期望 %ld) %s\n", hs_period, H_TOTAL,
           hs_period == H_TOTAL ? "PASS" : "FAIL");
    printf("vsync 宽度    : %ld  (期望 %ld) %s\n", vs_width, 6 * H_TOTAL,
           vs_width == 6 * H_TOTAL ? "PASS" : "FAIL");
    printf("vsync 周期    : %ld  (期望 %ld) %s\n", vs_period, V_TOTAL * H_TOTAL,
           vs_period == V_TOTAL * H_TOTAL ? "PASS" : "FAIL");
    printf("行有效像素    : %d 行完整 (800 像素/行), %d 行异常\n", good_lines, bad_lines);
    printf("像素总数      : %zu / %ld\n", frame.size(), FRAME_PIXELS);
    printf("刷新率        : %.2f Hz\n", 50e6 / ((double)H_TOTAL * V_TOTAL));

    if (hs_width != 120 || hs_period != H_TOTAL ||
        vs_width != 6 * H_TOTAL || vs_period != V_TOTAL * H_TOTAL || bad_lines != 0) {
        ok = false;
    }

    printf("\n结果: %s\n", ok ? "PASS（时序正确，图像已导出）" : "FAIL");
    dut->final();
    delete dut;
    return ok ? 0 : 1;
}
