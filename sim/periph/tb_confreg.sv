`default_nettype none
// ---------------------------------------------------------------------------
// tb_confreg.sv —— confreg 自检
//
// 覆盖：
//   * STEP 写入 → LED[4:0]/数码管 BCD 解码，及 3199 饱和
//   * STATUS → LED 直连映射
//   * BTN：两级同步 + 边沿检测 + 读后清零
//   * KEY：拨码开关电平
//   * TIME：1 kHz 计时（50 MHz / 50000）
//   * RAND：自由计数
//   * FB_CTRL：写 1 置位、vsync_start 原子翻转、bit[16] 硬件独占不可写
//   * 字节使能部分写
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_confreg;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;

    // 总线
    reg        req_valid = 0;
    reg  [7:0] req_addr  = 0;
    reg        req_we    = 0;
    reg  [3:0] req_be_n  = 4'h0;
    reg  [31:0] req_wdata = 0;
    wire       req_ready, rsp_valid;
    wire [31:0] rsp_rdata;

    // 板载
    reg  [3:0]  touch_btn = 0;
    reg  [31:0] dip_sw = 0;
    reg         vsync_start = 0;
    wire        fb_sel;
    wire [15:0] leds;
    wire [7:0]  dpy1, dpy0;

    confreg dut (
        .clk(clk), .rst(rst),
        .req_valid(req_valid), .req_ready(req_ready),
        .req_addr(req_addr), .req_we(req_we),
        .req_be_n(req_be_n), .req_wdata(req_wdata),
        .rsp_valid(rsp_valid), .rsp_rdata(rsp_rdata),
        .touch_btn(touch_btn), .dip_sw(dip_sw),
        .vsync_start(vsync_start), .fb_sel(fb_sel),
        .leds(leds), .dpy1(dpy1), .dpy0(dpy0)
    );

    integer errors = 0;

    task automatic check32(input [31:0] got, input [31:0] exp, input string name);
        if (got !== exp) begin
            $display("FAIL: %0s got=%h exp=%h", name, got, exp);
            errors = errors + 1;
        end else begin
            $display("PASS: %0s = %h", name, got);
        end
    endtask

    task automatic bus_write(input [7:0] a, input [31:0] d, input [3:0] be);
        @(negedge clk);
        req_valid = 1; req_addr = a; req_we = 1; req_wdata = d; req_be_n = be;
        @(posedge clk);
        if (!req_ready) begin
            $display("FAIL: 写 %h 时 req_ready=0", a);
            errors = errors + 1;
        end
        @(negedge clk);
        req_valid = 0; req_be_n = 4'h0;
        @(posedge clk);
    endtask

    task automatic bus_read(input [7:0] a, output [31:0] d);
        @(negedge clk);
        req_valid = 1; req_addr = a; req_we = 0; req_be_n = 4'h0;
        @(posedge clk);
        if (!req_ready) begin
            $display("FAIL: 读 %h 时 req_ready=0", a);
            errors = errors + 1;
        end
        @(negedge clk);
        req_valid = 0;
        if (!rsp_valid) begin
            $display("FAIL: 读 %h 没有 rsp_valid", a);
            errors = errors + 1;
        end
        d = rsp_rdata;
    endtask

    reg [31:0] d, d2, t0, t1;

    initial begin
        $display("=== confreg testbench ===");
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // ---- STEP / 数码管 ----
        bus_write(8'h00, 32'd1234, 4'h0);
        check32({27'd0, leds[4:0]}, 32'd12, "STEP=1234 -> LED 百位以上");
        check32({24'd0, dpy1}, 32'hB6, "STEP=1234 -> 十位 seg7(3)");
        check32({24'd0, dpy0}, 32'hD2, "STEP=1234 -> 个位 seg7(4)");

        bus_write(8'h00, 32'd4000, 4'h0);       // 饱和
        check32({27'd0, leds[4:0]}, 32'd31, "STEP=4000 饱和 LED=31");
        check32({24'd0, dpy1}, 32'hF6, "STEP=4000 饱和 十位=9");
        check32({24'd0, dpy0}, 32'hF6, "STEP=4000 饱和 个位=9");

        // ---- STATUS -> LED ----
        bus_write(8'h04, (32'd5 << 13) | (32'hA5 << 5), 4'h0);
        check32({29'd0, leds[15:13]}, 32'd5, "STATUS[15:13] -> LED[15:13]");
        check32({24'd0, leds[12:5]}, 32'hA5, "STATUS[12:5] -> LED[12:5]");

        // ---- 字节使能部分写 ----
        bus_write(8'h00, 32'h123, 4'h0);
        bus_write(8'h00, 32'h45, 4'b1110);    // 只写 byte0
        bus_read(8'h00, d);                     // STEP 只写，读回 0
        check32({27'd0, leds[4:0]}, 32'd3, "部分写后 STEP=0x145 -> LED=3");
        check32({24'd0, dpy1}, 32'hBC, "部分写后 十位 seg7(2)");
        check32({24'd0, dpy0}, 32'hE6, "部分写后 个位 seg7(5)");

        // ---- BTN：按下 -> 事件 -> 读清 ----
        touch_btn = 4'b0010;
        repeat (4) @(posedge clk);
        touch_btn = 4'b0000;
        repeat (2) @(posedge clk);
        bus_read(8'h08, d);
        check32(d, 32'h2, "BTN 读到 bit1 事件");
        bus_read(8'h08, d);
        check32(d, 32'h0, "BTN 读后清零");

        // ---- KEY ----
        dip_sw = 32'h0000_0002;
        bus_read(8'h0C, d);
        check32(d, 32'h2, "KEY 读拨码");
        dip_sw = 32'h0;

        // ---- TIME ----
        bus_read(8'h10, t0);
        repeat (100000) @(posedge clk);
        bus_read(8'h10, t1);
        if (t1 <= t0) begin
            $display("FAIL: TIME 未递增 t0=%0d t1=%0d", t0, t1);
            errors = errors + 1;
        end else begin
            $display("PASS: TIME 递增 %0d -> %0d", t0, t1);
        end

        // ---- RAND ----
        bus_read(8'h14, d);
        bus_read(8'h14, d2);
        if (d == d2) begin
            $display("FAIL: RAND 未变化");
            errors = errors + 1;
        end else begin
            $display("PASS: RAND 变化 %h -> %h", d, d2);
        end

        // ---- FB_CTRL ----
        bus_read(8'h18, d);
        check32(d, 32'h0, "FB_CTRL 初值");
        bus_write(8'h18, 32'h1, 4'h0);           // 请求翻页
        bus_read(8'h18, d);
        check32(d, 32'h1, "FB_CTRL flip_req=1");
        check32({31'd0, fb_sel}, 32'd0, "翻页前 fb_sel=0");

        @(negedge clk); vsync_start = 1;
        @(posedge clk);
        @(negedge clk); vsync_start = 0;
        repeat (2) @(posedge clk);

        bus_read(8'h18, d);
        check32(d, 32'h1_0000, "vsync 后 fb_sel=1 且请求清除");
        check32({31'd0, fb_sel}, 32'd1, "fb_sel 已翻转");

        // CPU 整字写不能覆盖 bit[16]
        bus_write(8'h18, 32'h1_0001, 4'h0);
        bus_read(8'h18, d);
        check32(d, 32'h1_0001, "整字写不破坏 fb_sel 位");

        @(negedge clk); vsync_start = 1;
        @(posedge clk);
        @(negedge clk); vsync_start = 0;
        repeat (2) @(posedge clk);
        bus_read(8'h18, d);
        check32(d, 32'h0, "再次翻页回到 fb_sel=0");

        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

`default_nettype wire
