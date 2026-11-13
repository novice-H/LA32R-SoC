`default_nettype none
// ---------------------------------------------------------------------------
// confreg.v —— CPU 唯一的板载外设（基址 0xBFD0_0000）
//
// 寄存器（偏移为字节地址，见 docs/design.md 2.2.6 / 4.1）：
//   +0x00 STEP      W   [11:0] 步数（显示饱和到 3199）
//   +0x04 STATUS    W   [15]AI [14]LOSE [13]WIN [12:5]调试
//   +0x08 BTN       R   [3:0] 按键单拍事件（0=上 1=左 2=下 3=右），读后清零
//   +0x0C KEY       R   [1:0] 拨码电平：key[0]=游戏开关 key[1]=AI
//   +0x10 TIME      R   [31:0] 毫秒计时（1 kHz 自由运行）
//   +0x14 RAND      R   [31:0] 50 MHz 自由计数（随机种子）
//   +0x18 FB_CTRL   W/R [0] 翻页请求（写 1 置位，vsync_start 清 0）
//                       [16] 当前显示缓冲号（硬件独占，CPU 只读）
//
// 输出：
//   leds[15:13] = STATUS[15:13]，leds[12:5] = STATUS[12:5]，
//   leds[4:0]   = step/100（饱和 31）
//   dpy1 / dpy0 = step%100 的十位 / 个位，段码位序见 seg7()
//
// 总线接口：单拍请求，下一拍返回（rsp_valid）。固定 2 拍应答由上层总线桥补齐。
// ---------------------------------------------------------------------------
module confreg (
    input  wire        clk,
    input  wire        rst,

    // ---- 简单总线（req_addr 为字节偏移）----
    input  wire        req_valid,
    output wire        req_ready,
    input  wire [7:0]  req_addr,
    input  wire        req_we,
    input  wire [3:0]  req_be_n,     // 低有效字节使能
    input  wire [31:0] req_wdata,
    output reg         rsp_valid,
    output reg  [31:0] rsp_rdata,

    // ---- 板载输入 ----
    input  wire [3:0]  touch_btn,    // 按下为 1（板上有硬件消抖）
    input  wire [31:0] dip_sw,

    // ---- 视频翻页握手 ----
    input  wire        vsync_start,  // vga_fb 单拍脉冲
    output reg         fb_sel,

    // ---- 板载输出 ----
    output wire [15:0] leds,
    output wire [7:0]  dpy1,
    output wire [7:0]  dpy0
);

    localparam [2:0] A_STEP    = 3'd0,
                     A_STATUS  = 3'd1,
                     A_BTN     = 3'd2,
                     A_KEY     = 3'd3,
                     A_TIME    = 3'd4,
                     A_RAND    = 3'd5,
                     A_FBCTRL  = 3'd6;

    // ---------------------------------------------------------------- 寄存器
    reg [11:0] step;
    reg [10:0] status;       // [15:5]
    reg [3:0]  btn_evt;
    reg [31:0] ms_cnt;
    reg [15:0] ms_div;
    reg [31:0] raw_cnt;
    reg        flip_req;

    // ---------------------------------------------------------------- 按键
    // 两级同步 + 边沿检测 + 事件累积（读后清零）
    reg [3:0] btn_meta, btn_sync, btn_prev;
    wire [3:0] btn_pulse = btn_sync & ~btn_prev;

    always @(posedge clk) begin
        if (rst) begin
            btn_meta <= 4'd0;
            btn_sync <= 4'd0;
            btn_prev <= 4'd0;
        end else begin
            btn_meta <= touch_btn;
            btn_sync <= btn_meta;
            btn_prev <= btn_sync;
        end
    end

    // ---------------------------------------------------------------- 计时与随机
    always @(posedge clk) begin
        if (rst) begin
            ms_div  <= 16'd0;
            ms_cnt  <= 32'd0;
            raw_cnt <= 32'd0;
        end else begin
            if (ms_div == 16'd49_999) begin
                ms_div <= 16'd0;
                ms_cnt <= ms_cnt + 32'd1;
            end else begin
                ms_div <= ms_div + 16'd1;
            end
            raw_cnt <= raw_cnt + 32'd1;
        end
    end

    // ---------------------------------------------------------------- 总线
    assign req_ready = 1'b1;

    wire [2:0] alu_sel = req_addr[4:2];   // 只译码 0x00..0x18 所在的 8 字节窗口

    // 字节级合并：be_n 为 1 的字节保持原值
    function [31:0] merge;
        input [31:0] cur;
        input [31:0] wdat;
        input [3:0]  be_n;
        begin
            merge[7:0]   = be_n[0] ? cur[7:0]   : wdat[7:0];
            merge[15:8]  = be_n[1] ? cur[15:8]  : wdat[15:8];
            merge[23:16] = be_n[2] ? cur[23:16] : wdat[23:16];
            merge[31:24] = be_n[3] ? cur[31:24] : wdat[31:24];
        end
    endfunction

    // 写合并（组合）
    wire [31:0] merged_step   = merge({20'd0, step},   req_wdata, req_be_n);
    wire [31:0] merged_status = merge({21'd0, status}, req_wdata, req_be_n);

    // 读多路选择（组合，供与读清同拍使用）
    reg [31:0] rd_mux;
    always @(*) begin
        case (alu_sel)
            A_STEP:   rd_mux = {20'd0, step};
            A_STATUS: rd_mux = {16'd0, status[10:0], 5'd0};
            A_BTN:    rd_mux = {28'd0, btn_evt};
            A_KEY:    rd_mux = {30'd0, dip_sw[1:0]};
            A_TIME:   rd_mux = ms_cnt;
            A_RAND:   rd_mux = raw_cnt;
            A_FBCTRL: rd_mux = {15'd0, fb_sel, 15'd0, flip_req};
            default:  rd_mux = 32'd0;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            step      <= 12'd0;
            status    <= 11'd0;
            btn_evt   <= 4'd0;
            flip_req  <= 1'b0;
            fb_sel    <= 1'b0;
            rsp_valid <= 1'b0;
            rsp_rdata <= 32'd0;
        end else begin
            rsp_valid <= 1'b0;

            // 按键事件累积（脉冲单拍）
            btn_evt <= btn_evt | btn_pulse;

            // 翻页握手：vsync 到来时若挂起请求则原子翻转并清请求
            if (vsync_start && flip_req) begin
                fb_sel   <= ~fb_sel;
                flip_req <= 1'b0;
            end

            if (req_valid && req_ready) begin
                if (req_we) begin
                    case (alu_sel)
                        A_STEP: begin
                            step <= merged_step[11:0];
                        end
                        A_STATUS: begin
                            status <= merged_status[15:5];
                        end
                        A_FBCTRL: begin
                            // bit[0] 写 1 置位（写 0 无效果）；bit[16] 硬件独占不可写
                            if (!req_be_n[0] && req_wdata[0])
                                flip_req <= 1'b1;
                        end
                        default: ;   // 只读寄存器忽略写
                    endcase
                end else begin
                    rsp_rdata <= rd_mux;
                    rsp_valid <= 1'b1;
                    // BTN 读后清零
                    if (alu_sel == A_BTN)
                        btn_evt <= 4'd0;
                end
            end
        end
    end

    // ---------------------------------------------------------------- 显示解码
    wire [11:0] step_sat = (step > 12'd3199) ? 12'd3199 : step;
    wire [11:0] hundreds = step_sat / 12'd100;        // 0..31
    wire [11:0] tens     = (step_sat % 12'd100) / 12'd10;
    wire [11:0] ones     = step_sat % 12'd10;

    assign leds[15:13] = status[10:8];    // STATUS[15:13]
    assign leds[12:5]  = status[7:0];     // STATUS[12:5]
    assign leds[4:0]   = hundreds[4:0];

    // 段码位序（顶层注释）：dpy = {g, f, a, b, e, d, c, p}，1 点亮
    function [7:0] seg7;
        input [3:0] d;
        begin
            case (d)
                4'd0: seg7 = 8'h7E;
                4'd1: seg7 = 8'h12;
                4'd2: seg7 = 8'hBC;
                4'd3: seg7 = 8'hB6;
                4'd4: seg7 = 8'hD2;
                4'd5: seg7 = 8'hE6;
                4'd6: seg7 = 8'hEE;
                4'd7: seg7 = 8'h32;
                4'd8: seg7 = 8'hFE;
                4'd9: seg7 = 8'hF6;
                default: seg7 = 8'h00;
            endcase
        end
    endfunction

    assign dpy1 = seg7(tens[3:0]);
    assign dpy0 = seg7(ones[3:0]);

endmodule

`default_nettype wire
