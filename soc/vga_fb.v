`default_nettype none

// ---------------------------------------------------------------------------
// vga_fb.v
//
// 800x600 视频扫描与帧缓冲读取模块。
//
// 设计约定：
//   1. clk 同时作为系统时钟和像素时钟，频率 50 MHz；
//   2. hcnt/vcnt 产生 1040x666 的完整扫描时序；
//   3. 有效区中的 4 个连续 RGB332 像素打包在一个 32 位字中；
//   4. RAM 为同步读，ram_rdata 在 ram_req 后一拍有效；
//   5. ram_addr 是 32 位字地址，不是字节地址。
//
// CPU 不直接连接本模块。CPU 和本模块分别通过 ExtRAM 控制器访问帧缓冲，
// 具体的双主机仲裁放在上层 SoC 中。
// ---------------------------------------------------------------------------
module vga_fb #(
    parameter integer H_ACTIVE       = 800,
    parameter integer H_SYNC_START   = 856,
    parameter integer H_SYNC_END     = 976,
    parameter integer H_TOTAL        = 1040,
    parameter integer V_ACTIVE       = 600,
    parameter integer V_SYNC_START   = 637,
    parameter integer V_SYNC_END     = 643,
    parameter integer V_TOTAL        = 666,
    parameter integer FB_WORDS       = 120000,
    parameter integer FB1_WORD_BASE  = 131072
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        fb_sel,

    output wire [19:0] ram_addr,
    output wire        ram_req,
    input  wire [31:0] ram_rdata,

    output wire [2:0]  vga_red,
    output wire [2:0]  vga_green,
    output wire [1:0]  vga_blue,
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire        vga_de
);

    localparam [10:0] H_TOTAL_LAST = H_TOTAL[10:0] - 11'd1;
    localparam [9:0]  V_TOTAL_LAST = V_TOTAL[9:0] - 10'd1;
    localparam [10:0] H_ACTIVE_LAST = H_ACTIVE[10:0] - 11'd1;
    localparam [19:0] WORDS_PER_LINE = H_ACTIVE[19:0] / 20'd4;
    localparam [19:0] FB_WORDS_CONST = FB_WORDS[19:0];
    localparam [19:0] FB1_BASE_CONST = FB1_WORD_BASE[19:0];

    reg [10:0] hcnt;
    reg [9:0]  vcnt;

    // 当前扫描行在帧缓冲中的字地址起点。
    // 800 像素 / 4 像素每字 = 200 字，因此每进入下一有效行加 200。
    reg [19:0] line_word_base;

    // fb_sel 打一拍，用于检测翻页时刻：显存基址在消隐区变化后，
    // 必须立刻为新缓冲补一次 word0 预取，否则下一帧前 4 个像素仍来自旧缓冲。
    reg fb_sel_q;

    wire in_active_x = (hcnt <= H_ACTIVE_LAST);
    wire in_active_y = (vcnt < V_ACTIVE[9:0]);
    wire in_active   = in_active_x && in_active_y;
    wire video_active = !rst && in_active;

    // 当前 hcnt 所在的 4 像素组之后的下一个字地址。
    // 例如 hcnt=3 时，下一组是字 1；hcnt=799 时，下一行是字 200。
    wire [19:0] next_word_in_line = ({9'd0, hcnt} + 20'd1) >> 2;
    wire [19:0] next_word_offset  = line_word_base + next_word_in_line;
    wire [19:0] wrapped_word_offset =
        (next_word_offset >= FB_WORDS_CONST) ? 20'd0 : next_word_offset;
    wire [19:0] selected_word_base = fb_sel ? FB1_BASE_CONST : 20'd0;

    // ------------------------------------------------------------ 扫描计数器
    always @(posedge clk) begin
        if (rst) begin
            hcnt          <= 11'd0;
            vcnt          <= 10'd0;
            line_word_base <= 20'd0;
            fb_sel_q      <= fb_sel;
        end else if (hcnt == H_TOTAL_LAST) begin
            hcnt <= 11'd0;

            fb_sel_q <= fb_sel;
            if (vcnt == V_TOTAL_LAST) begin
                vcnt           <= 10'd0;
                line_word_base <= 20'd0;
            end else begin
                vcnt <= vcnt + 10'd1;

                // 只有下一行仍属于有效画面时才推进显存行地址。
                // 垂直消隐期间不发 RAM 请求，因此保持 0 即可。
                if (vcnt < V_ACTIVE[9:0] - 10'd1)
                    line_word_base <= line_word_base + WORDS_PER_LINE;
                else
                    line_word_base <= 20'd0;
            end
        end else begin
            hcnt     <= hcnt + 11'd1;
            fb_sel_q <= fb_sel;
        end
    end

    wire fb_sel_changed = (fb_sel != fb_sel_q);

    // RAM 一拍延迟，所以在每组第 4 个像素时预取下一组。
    // 复位期间预取当前帧的第一个字，保证解除复位后第一组像素也有数据。
    assign ram_addr = (rst || fb_sel_changed) ? selected_word_base
                                              : selected_word_base + wrapped_word_offset;
    assign ram_req  = rst || fb_sel_changed || (in_active && (hcnt[1:0] == 2'b11));

    // ------------------------------------------------------------ 像素拆包
    reg [7:0] pixel_rgb332;
    always @(*) begin
        case (hcnt[1:0])
            2'd0:    pixel_rgb332 = ram_rdata[7:0];
            2'd1:    pixel_rgb332 = ram_rdata[15:8];
            2'd2:    pixel_rgb332 = ram_rdata[23:16];
            default: pixel_rgb332 = ram_rdata[31:24];
        endcase
    end

    // 消隐区输出黑色；显示器只在 vga_de=1 时采样颜色。
    assign vga_red   = video_active ? pixel_rgb332[7:5] : 3'b000;
    assign vga_green = video_active ? pixel_rgb332[4:2] : 3'b000;
    assign vga_blue  = video_active ? pixel_rgb332[1:0] : 2'b00;

    // 本项目使用正脉冲同步信号。
    assign vga_hsync = (hcnt >= H_SYNC_START[10:0]) &&
                       (hcnt <  H_SYNC_END[10:0]);
    assign vga_vsync = (vcnt >= V_SYNC_START[9:0]) &&
                       (vcnt <  V_SYNC_END[9:0]);
    assign vga_de    = video_active;

endmodule

`default_nettype wire
