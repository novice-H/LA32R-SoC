`default_nettype none
// ---------------------------------------------------------------------------
// dut_placeholder.v —— 【占位实现，不是最终设计】
//
// 本文件只为了让验证环境今天就能端到端跑通：用最简单的逻辑实现 DUT 契约，
// 即"时序计数 + 帧缓冲地址生成 + 4 像素取 1 字节 + RGB332 输出"。
//
// 正式的 VGA / DVI 模块请写在 soc/ 下（按 docs/design.md 2.2.7 的规格），
// 然后在本目录新增 dut_xxx.v 把它的端口接到契约上，运行时：
//     make DUT=vga/dut_xxx.v
// 不是直接改本文件——本文件是参照用的占位件。契约见 sim/vga/README.md。
// ---------------------------------------------------------------------------
// 时序：VGA 800x600 @ 72.19 Hz（50 MHz 像素时钟）
// 时序（与 thinpad_top.v 中的 vga #(12,800,856,976,1040,600,637,643,666,1,1) 一致）：
//   行：H_ACTIVE=800  H_SYNC_START=856  H_SYNC_END=976  H_TOTAL=1040
//   场：V_ACTIVE=600  V_SYNC_START=637  V_SYNC_END=643  V_TOTAL=666
//   像素时钟 = 系统时钟 = 50 MHz -> 刷新率 50e6/(1040*666) = 72.19 Hz
//
// 像素格式：1 字节/像素，{R[2:0], G[2:0], B[1:0]}，PITCH = 800 字节
// 帧缓冲：4 像素打包进 1 个 32 位字，小端（像素 x 在字节道 x[1:0]）
//         FB0 基址 0xA000_0000 -> 字偏移 0
//         FB1 基址 0xA008_0000 -> 字偏移 131072
//
// 读时序：RAM 读延迟 1 拍。在每组第 4 个像素那一拍（hcnt[1:0]==3）发出下一组的
//         字地址，数据正好在下一组第 1 个像素那一拍到，组合选择字节输出像素。
//         行尾（hcnt==799）发出的地址是下一行第 0 字，数据在消隐期到达并被 RAM
//         输出保持，于是下一行开头可直接使用；帧尾同样回卷到第 0 字。
// ---------------------------------------------------------------------------
module vga_dut #(
    parameter integer H_ACTIVE      = 800,
    parameter integer H_SYNC_START  = 856,
    parameter integer H_SYNC_END    = 976,
    parameter integer H_TOTAL       = 1040,
    parameter integer V_ACTIVE      = 600,
    parameter integer V_SYNC_START  = 637,
    parameter integer V_SYNC_END    = 643,
    parameter integer V_TOTAL       = 666,
    parameter integer FB_WORDS      = 120000,   // 480000 B / 4
    parameter integer FB1_WORD_BASE = 131072    // (0xA008_0000 - 0xA000_0000) / 4
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        fb_sel,        // 0 = FB0, 1 = FB1
    output wire [19:0] ram_addr,      // ExtRAM 字地址
    output wire        ram_req,       // 读请求
    input  wire [31:0] ram_rdata,     // 1 拍延迟读数据
    output wire [2:0]  vga_red,
    output wire [2:0]  vga_green,
    output wire [1:0]  vga_blue,
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire        vga_de,
    output wire        vsync_start,
    output wire        dvi_next
);

    // 定宽常量，避免与 11/10 位计数器比较时的位宽扩展告警
    localparam [10:0] H_ACT  = H_ACTIVE[10:0];
    localparam [10:0] H_SYN0 = H_SYNC_START[10:0];
    localparam [10:0] H_SYN1 = H_SYNC_END[10:0];
    localparam [10:0] H_TOT  = H_TOTAL[10:0] - 11'd1;
    localparam [9:0]  V_ACT  = V_ACTIVE[9:0];
    localparam [9:0]  V_SYN0 = V_SYNC_START[9:0];
    localparam [9:0]  V_SYN1 = V_SYNC_END[9:0];
    localparam [9:0]  V_TOT  = V_TOTAL[9:0] - 10'd1;
    localparam [19:0] FBW    = FB_WORDS[19:0];
    localparam [19:0] FB1    = FB1_WORD_BASE[19:0];
    localparam [10:0] H_ONE  = 11'd1;
    localparam [10:0] H_LAST = H_ACT - 11'd1;

    reg [10:0] hcnt;   // 0 .. H_TOTAL-1
    reg [9:0]  vcnt;   // 0 .. V_TOTAL-1

    // ---------------------------------------------------------------- 时序计数
    always @(posedge clk) begin
        if (rst) begin
            hcnt <= 11'd0;
            vcnt <= 10'd0;
        end else if (hcnt == H_TOT) begin
            hcnt <= 11'd0;
            vcnt <= (vcnt == V_TOT) ? 10'd0 : vcnt + 10'd1;
        end else begin
            hcnt <= hcnt + H_ONE;
        end
    end

    // ------------------------------------------------------------ 地址生成
    // 下一像素组的字偏移（FB 内线性字节偏移 / 4）
    wire [19:0] line_base = vcnt * H_ACT;
    wire [19:0] h_ext     = {9'd0, hcnt};
    wire [19:0] word_idx  = (line_base + h_ext + 20'd2) >> 2;
    // 越界（帧尾回卷）时预取第 0 字，保证下一帧第一组像素正确
    wire [19:0] word_off  = (word_idx >= FBW) ? 20'd0 : word_idx;
    wire [19:0] word_abs  = word_off + (fb_sel ? FB1 : 20'd0);

    // fb_sel 变化时按新基址重新预取 word0（翻页后首字不能来自旧缓冲）
    reg fb_sel_q;
    always @(posedge clk) begin
        if (rst) fb_sel_q <= fb_sel;
        else     fb_sel_q <= fb_sel;
    end
    wire fb_sel_changed = (fb_sel != fb_sel_q);
    wire [19:0] sel_base = fb_sel ? FB1 : 20'd0;

    assign ram_addr = (rst || fb_sel_changed) ? sel_base : word_abs;
    assign ram_req  = rst || fb_sel_changed || ((hcnt <= H_LAST) && (hcnt[1:0] == 2'd2));

    assign dvi_next    = !rst && (hcnt <= H_LAST) && (hcnt[1:0] == 2'd1);
    assign vsync_start = !rst && (hcnt == 11'd0) && (vcnt == V_ACT);

    // ------------------------------------------------------------ 像素选择
    reg [7:0] pix;
    always @(*) begin
        case (hcnt[1:0])
            2'd0:    pix = ram_rdata[7:0];
            2'd1:    pix = ram_rdata[15:8];
            2'd2:    pix = ram_rdata[23:16];
            default: pix = ram_rdata[31:24];
        endcase
    end

    assign vga_red   = pix[7:5];
    assign vga_green = pix[4:2];
    assign vga_blue  = pix[1:0];

    // ------------------------------------------------------------ 同步信号
    assign vga_hsync = (hcnt >= H_SYN0) && (hcnt < H_SYN1);
    assign vga_vsync = (vcnt >= V_SYN0) && (vcnt < V_SYN1);
    assign vga_de    = (hcnt <= H_LAST) && (vcnt < V_ACT);

endmodule

`default_nettype wire
