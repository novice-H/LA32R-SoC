`default_nettype none
// ---------------------------------------------------------------------------
// tb_soc_top.sv —— 全系统仿真
//
//   CPU（openLA500）── AXI3 ── 参考桥 ── 总线译码 ── BaseRAM / ExtRAM / confreg
//   VGA 扫描器与 CPU 争用 ExtRAM（仲裁器）
//
// 流程：
//   1. BaseRAM 预装 prog/start.S 编译出的镜像（链接在 0x1C00_0000）
//   2. 释放复位，等程序写 STATUS[13]=1（WIN 标志）
//   3. 检查 STEP -> LED/数码管
//   4. 采一整帧 VGA，检查程序写入的像素
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_soc_top;

    reg clk = 0;
    always #5 clk = ~clk;          // 100 MHz 仿真时钟（按拍计时，不影响功能）

    reg reset_btn = 1;

    wire [31:0] base_ram_data, ext_ram_data;
    wire [19:0] base_ram_addr, ext_ram_addr;
    wire [3:0]  base_ram_be_n, ext_ram_be_n;
    wire        base_ram_ce_n, base_ram_oe_n, base_ram_we_n;
    wire        ext_ram_ce_n, ext_ram_oe_n, ext_ram_we_n;
    wire [2:0]  video_red, video_green;
    wire [1:0]  video_blue;
    wire        video_hsync, video_vsync, video_clk, video_de;
    wire [15:0] leds;
    wire [7:0]  dpy0, dpy1;
    wire [31:0] dbg_wb_pc;

    soc_top dut (
        .clk_50M(clk), .reset_btn(reset_btn),
        .base_ram_data(base_ram_data), .base_ram_addr(base_ram_addr),
        .base_ram_be_n(base_ram_be_n), .base_ram_ce_n(base_ram_ce_n),
        .base_ram_oe_n(base_ram_oe_n), .base_ram_we_n(base_ram_we_n),
        .ext_ram_data(ext_ram_data), .ext_ram_addr(ext_ram_addr),
        .ext_ram_be_n(ext_ram_be_n), .ext_ram_ce_n(ext_ram_ce_n),
        .ext_ram_oe_n(ext_ram_oe_n), .ext_ram_we_n(ext_ram_we_n),
        .video_red(video_red), .video_green(video_green), .video_blue(video_blue),
        .video_hsync(video_hsync), .video_vsync(video_vsync),
        .video_clk(video_clk), .video_de(video_de),
        .touch_btn(4'd0), .dip_sw(32'd0),
        .leds(leds), .dpy0(dpy0), .dpy1(dpy1),
        .dbg_wb_pc(dbg_wb_pc)
    );

    async_sram_model #(
        .WORDS(1 << 20), .LOAD_INIT(1'b1), .INIT_FILE("prog.hex"), .FILL_WORD(32'd0)
    ) u_base_ram (
        .clk(clk), .addr(base_ram_addr), .be_n(base_ram_be_n),
        .ce_n(base_ram_ce_n), .oe_n(base_ram_oe_n), .we_n(base_ram_we_n),
        .data(base_ram_data)
    );

    async_sram_model #(
        .WORDS(1 << 20), .LOAD_INIT(1'b0), .FILL_WORD(32'd0)
    ) u_ext_ram (
        .clk(clk), .addr(ext_ram_addr), .be_n(ext_ram_be_n),
        .ce_n(ext_ram_ce_n), .oe_n(ext_ram_oe_n), .we_n(ext_ram_we_n),
        .data(ext_ram_data)
    );

    integer errors = 0;
    reg [7:0] frame [0:479999];

    task automatic check32(input [31:0] got, input [31:0] exp, input string name);
        if (got !== exp) begin
            $display("FAIL: %0s got=%h exp=%h", name, got, exp);
            errors = errors + 1;
        end else begin
            $display("PASS: %0s = %h", name, got);
        end
    endtask

    integer timeout, n;

    initial begin
        $display("=== soc_top full-system testbench ===");
        if ($test$plusargs("wave")) begin
            $dumpfile("soc.vcd");
            $dumpvars(1, tb_soc_top.dut);
            $dumpvars(1, tb_soc_top);
        end
        repeat (20) @(posedge clk);
        reset_btn = 0;

        // 等程序写完 STATUS[13]
        timeout = 0;
        while (leds[13] !== 1'b1 && timeout < 8_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (leds[13] !== 1'b1) begin
            $display("FAIL: 等 STATUS[13] 超时（%0d 拍），最后 WB PC=%h",
                     timeout, dbg_wb_pc);
            $display("      leds=%h dpy1=%h dpy0=%h", leds, dpy1, dpy0);
            errors = errors + 1;
        end else begin
            $display("PASS: 程序完成（%0d 拍），leds=%h", timeout, leds);
        end

        check32({27'd0, leds[4:0]}, 32'd12, "STEP=1234 -> LED[4:0]");
        check32({24'd0, dpy1}, 32'hB6, "数码管十位 seg7(3)");
        check32({24'd0, dpy0}, 32'hD2, "数码管个位 seg7(4)");

        // 波形模式：跑完程序就停，不采整帧
        if ($test$plusargs("short")) begin
            repeat (100) @(posedge clk);
            $display("RESULT: PASS (wave run)");
            $finish;
        end

        // 采一整帧
        while (video_vsync === 1'b1) @(posedge clk);
        while (video_vsync === 1'b0) @(posedge clk);

        n = 0;
        timeout = 0;
        while (n < 480000 && timeout < 1_500_000) begin
            @(posedge clk);
            timeout = timeout + 1;
            if (video_de) begin
                frame[n] = {video_red, video_green, video_blue};
                n = n + 1;
            end
        end

        if (n != 480000) begin
            $display("FAIL: 帧采集不完整 %0d/480000", n);
            errors = errors + 1;
        end else begin
            $display("PASS: 采到完整一帧");
            check32({24'd0, frame[0]},   32'h0000EF, "pixel(0,0)  FB0 line0");
            check32({24'd0, frame[3]},   32'h0000EF, "pixel(3,0)  FB0 line0");
            check32({24'd0, frame[800]}, 32'h0000E0, "pixel(0,1)  FB0 line1 word0");
            check32({24'd0, frame[803]}, 32'h0000E0, "pixel(3,1)  FB0 line1 word0");
            check32({24'd0, frame[804]}, 32'h000000, "pixel(4,1)  未写区域为 0");
        end

        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

`default_nettype wire
