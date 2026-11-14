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
    reg [3:0] touch_btn = 0;
    reg [31:0] dip_sw = 0;

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

    thinpad_top dut (
        .clk_50M(clk),
        .clk_11M0592(1'b0),
        .clock_btn(1'b0),
        .reset_btn(reset_btn),

        .touch_btn(touch_btn),
        .dip_sw(dip_sw),
        .leds(leds), .dpy0(dpy0), .dpy1(dpy1),

        .base_ram_data(base_ram_data), .base_ram_addr(base_ram_addr),
        .base_ram_be_n(base_ram_be_n), .base_ram_ce_n(base_ram_ce_n),
        .base_ram_oe_n(base_ram_oe_n), .base_ram_we_n(base_ram_we_n),

        .ext_ram_data(ext_ram_data), .ext_ram_addr(ext_ram_addr),
        .ext_ram_be_n(ext_ram_be_n), .ext_ram_ce_n(ext_ram_ce_n),
        .ext_ram_oe_n(ext_ram_oe_n), .ext_ram_we_n(ext_ram_we_n),

        .txd(), .rxd(1'b0),

        .flash_a(), .flash_d(), .flash_rp_n(), .flash_vpen(),
        .flash_ce_n(), .flash_oe_n(), .flash_we_n(), .flash_byte_n(),

        .video_red(video_red), .video_green(video_green), .video_blue(video_blue),
        .video_hsync(video_hsync), .video_vsync(video_vsync),
        .video_clk(video_clk), .video_de(video_de)
    );

    // 仿真观测：CPU 写回级 PC（thinpad_top 不引出，只能层次引用）
    assign dbg_wb_pc = dut.u_soc.dbg_wb_pc;

`ifdef TB_AI
    localparam BASE_INIT = "ai.hex";
`elsif TB_V2
    localparam BASE_INIT = "prog_v2.hex";
`else
    localparam BASE_INIT = "prog.hex";
`endif

    async_sram_model #(
        .WORDS(1 << 20), .LOAD_INIT(1'b1), .INIT_FILE(BASE_INIT), .FILL_WORD(32'd0)
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

    `include "input_scenarios.svh"
    `include "framebuffer_scenarios.svh"
    `include "game_scenarios.svh"

    integer timeout, n;
    integer cyc = 0;
    integer cyc0, cyc1;
    reg [31:0] ai_nodes, ai_move;
    always @(posedge clk) cyc = cyc + 1;
    reg cpp_smoke;
    reg [31:0] boot_symbols [0:6];
    integer poison_addr;

    initial begin
        $display("=== soc_top full-system testbench ===");
        cpp_smoke = $test$plusargs("cpp-smoke");
        if (cpp_smoke) begin
            $readmemh("boot-symbols.hex", boot_symbols);
            // SRAM models finish image loading at time 0. Dirty the runtime
            // data/BSS destination so successful startup must copy and clear.
            #1;
            for (poison_addr = int'(boot_symbols[0]); poison_addr < int'(boot_symbols[1]); poison_addr += 4)
                u_base_ram.mem[(poison_addr - 'h1c000000) >> 2] = 32'hdeadbeef;
            for (poison_addr = int'(boot_symbols[2]); poison_addr < int'(boot_symbols[3]); poison_addr += 4)
                u_base_ram.mem[(poison_addr - 'h1c000000) >> 2] = 32'hdeadbeef;
            $display("CPP_BOOT: runtime data/BSS poisoned before reset release");
        end
        if ($test$plusargs("wave")) begin
            $dumpfile("soc.vcd");
            $dumpvars(1, tb_soc_top.dut);
            $dumpvars(1, tb_soc_top);
        end
        repeat (20) @(posedge clk);
        reset_btn = 0;

        if ($test$plusargs("game-image-test")) begin
            run_game_image_scenarios();
            if (errors == 0) $display("RESULT: PASS (CPU game image test)");
            else             $display("RESULT: FAIL (%0d errors)", errors);
            $finish;
        end else if ($test$plusargs("game-live-test")) begin
            run_game_live_scenarios();
            if (errors == 0) $display("RESULT: PASS (CPU live game test)");
            else             $display("RESULT: FAIL (%0d errors)", errors);
            $finish;
        end else if ($test$plusargs("game-test")) begin
            run_game_scenarios();
            if (errors == 0) $display("RESULT: PASS (CPU game test)");
            else             $display("RESULT: FAIL (%0d errors)", errors);
            $finish;
        end else if ($test$plusargs("input-test")) begin
            run_input_scenarios();
            if (errors == 0) $display("RESULT: PASS (CPU input test)");
            else             $display("RESULT: FAIL (%0d errors)", errors);
            $finish;
        end else if ($test$plusargs("framebuffer-test")) begin
            run_framebuffer_scenarios();
            if (errors == 0) $display("RESULT: PASS (CPU framebuffer test)");
            else             $display("RESULT: FAIL (%0d errors)", errors);
            $finish;
        end else begin

`ifdef TB_AI
        // ---- AI 单步基准：STATUS[5] 开始，STATUS[13] 结束 ----
        timeout = 0;
        while (leds[5] !== 1'b1 && timeout < 2_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (leds[5] !== 1'b1) begin
            $display("FAIL: 等开始标记超时，leds=%h", leds);
            $finish;
        end
        $display("AI start @%0d cycles", cyc);
        cyc0 = cyc;

        timeout = 0;
        while (leds[13] !== 1'b1 && timeout < 30_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (leds[13] !== 1'b1) begin
            $display("FAIL: 搜索超时（%0d 拍），leds=%h", timeout, leds);
            $finish;
        end
        cyc1 = cyc;

        ai_nodes = u_ext_ram.mem[20'hFC000];
        ai_move  = u_ext_ram.mem[20'hFC001];

        $display("AI one-move: cycles=%0d nodes=%0d cycles/node=%0.1f move=%0d",
                 cyc1 - cyc0, ai_nodes,
                 ai_nodes ? (cyc1 - cyc0) * 1.0 / ai_nodes : 0.0,
                 ai_move - 1);

        if (ai_nodes == 0 || ai_nodes > 32'd10000) begin
            $display("FAIL: 节点数异常 %0d", ai_nodes);
            errors = errors + 1;
        end
        if (ai_move < 1 || ai_move > 4) begin
            $display("FAIL: 走法异常 %0d", ai_move - 1);
            errors = errors + 1;
        end
        if ((cyc1 - cyc0) < ai_nodes * 10 || (cyc1 - cyc0) > 50_000_000) begin
            $display("FAIL: 周期数异常 %0d", cyc1 - cyc0);
            errors = errors + 1;
        end

        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
`else

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

        if (cpp_smoke) begin
            timeout = 0;
            while (dbg_wb_pc != boot_symbols[6] && timeout < 10000) begin
                @(posedge clk);
                timeout += 1;
            end
            check32(dbg_wb_pc, boot_symbols[6], "C++ main returned to boot halt");
            check32(u_base_ram.mem[(boot_symbols[4] - 'h1c000000) >> 2],
                    32'h600d2048, "C++ data/BSS/stack self-check");
            check32(u_base_ram.mem[(boot_symbols[5] - 'h1c000000) >> 2],
                    32'haa, "C++ stack function checksum");
        end

        // 波形模式：跑完程序就停，不采整帧
        if ($test$plusargs("short")) begin
            repeat (100) @(posedge clk);
            if (errors == 0) $display("RESULT: PASS (wave run)");
            else             $display("RESULT: FAIL (%0d errors)", errors);
            $finish;
        end

        // 采一整帧
        while (video_vsync === 1'b1) @(posedge clk);
        while (video_vsync === 1'b0) @(posedge clk);
`ifdef TB_V2
        while (video_vsync === 1'b1) @(posedge clk);
        while (video_vsync === 1'b0) @(posedge clk);
`endif

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
`ifdef TB_V2
            check32({24'd0, frame[0]},          32'h0000FF, "pixel(0,0)    左上角白");
            check32({24'd0, frame[800]},        32'h0000FF, "pixel(0,1)    左边白");
            check32({24'd0, frame[400]},        32'h0000EF, "pixel(400,0)  顶边中粉");
            check32({24'd0, frame[599*800]},    32'h0000FF, "pixel(0,599)  底边白");
            check32({24'd0, frame[599*800+796]},32'h0000FF, "pixel(796,599)右边白");
            check32({24'd0, frame[300*800]},    32'h0000FF, "pixel(0,300)  左边白");
            check32({24'd0, frame[300*800+4]},  32'h000003, "pixel(4,300)  背景蓝");
            check32({24'd0, frame[796]},        32'h0000FF, "pixel(796,0)  右边白");
            check32({24'd0, frame[4]},          32'h0000EF, "pixel(4,0)    顶边粉");
`else
            check32({24'd0, frame[0]},   32'h0000EF, "pixel(0,0)  FB0 line0");
            check32({24'd0, frame[3]},   32'h0000EF, "pixel(3,0)  FB0 line0");
            check32({24'd0, frame[800]}, 32'h0000E0, "pixel(0,1)  FB0 line1 word0");
            check32({24'd0, frame[803]}, 32'h0000E0, "pixel(3,1)  FB0 line1 word0");
            check32({24'd0, frame[804]}, 32'h000000, "pixel(4,1)  未写区域为 0");
`endif
        end

        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
`endif
        end // Default assembly/C++ startup suite.
    end

endmodule

`default_nettype wire
