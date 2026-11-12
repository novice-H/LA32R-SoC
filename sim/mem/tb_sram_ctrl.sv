`default_nettype none
// ---------------------------------------------------------------------------
// tb_sram_ctrl.sv —— sram_ctrl / base_ram_ctrl / ext_ram_ctrl 自检 testbench
//
// 覆盖：
//   1. 50MHz/67MHz → RAM_CYC=1：读写、CE 低电平 1 拍
//   2. 193MHz/67MHz → RAM_CYC=3：读写、CE 低电平 3 拍
//   3. 字节使能 be_n 的部分写
//   4. BaseRAM / ExtRAM 两个实例互不干扰
//
// 运行：见 sim/mem/Makefile；结束打印 RESULT: PASS
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_sram_ctrl;

    reg clk = 0;
    always #5 clk = ~clk;      // 仿真时钟，与 DUT 的频率参数无关

    reg rst = 1;
    integer errors = 0;

    // ==================================================================
    // 实例 1：BaseRAM，RAM_CYC = 1
    // ==================================================================
    reg         req_valid = 0;
    reg  [19:0] req_addr  = 0;
    reg         req_we    = 0;
    reg  [3:0]  req_be_n  = 4'h0;
    reg  [31:0] req_wdata = 0;
    wire        req_ready, rsp_valid;
    wire [31:0] rsp_rdata;

    wire [31:0] bram_data;
    wire [19:0] bram_addr;
    wire [3:0]  bram_be_n;
    wire        bram_ce_n, bram_oe_n, bram_we_n;

    base_ram_ctrl #(
        .CLK_FREQ(50_000_000),
        .RAM_FREQ(67_000_000)
    ) u_base (
        .clk(clk), .rst(rst),
        .req_valid(req_valid), .req_ready(req_ready),
        .req_addr(req_addr), .req_we(req_we),
        .req_be_n(req_be_n), .req_wdata(req_wdata),
        .rsp_valid(rsp_valid), .rsp_rdata(rsp_rdata),
        .base_ram_data(bram_data), .base_ram_addr(bram_addr),
        .base_ram_be_n(bram_be_n), .base_ram_ce_n(bram_ce_n),
        .base_ram_oe_n(bram_oe_n), .base_ram_we_n(bram_we_n)
    );

    async_sram_model #(.WORDS(256)) u_base_ram (
        .clk(clk), .addr(bram_addr), .be_n(bram_be_n),
        .ce_n(bram_ce_n), .oe_n(bram_oe_n), .we_n(bram_we_n),
        .data(bram_data)
    );

    // ==================================================================
    // 实例 2：ExtRAM，RAM_CYC = 3
    // ==================================================================
    reg         req2_valid = 0;
    reg  [19:0] req2_addr  = 0;
    reg         req2_we    = 0;
    reg  [3:0]  req2_be_n  = 4'h0;
    reg  [31:0] req2_wdata = 0;
    wire        req2_ready, rsp2_valid;
    wire [31:0] rsp2_rdata;

    wire [31:0] eram_data;
    wire [19:0] eram_addr;
    wire [3:0]  eram_be_n;
    wire        eram_ce_n, eram_oe_n, eram_we_n;

    ext_ram_ctrl #(
        .CLK_FREQ(193_000_000),
        .RAM_FREQ(67_000_000)
    ) u_ext (
        .clk(clk), .rst(rst),
        .req_valid(req2_valid), .req_ready(req2_ready),
        .req_addr(req2_addr), .req_we(req2_we),
        .req_be_n(req2_be_n), .req_wdata(req2_wdata),
        .rsp_valid(rsp2_valid), .rsp_rdata(rsp2_rdata),
        .ext_ram_data(eram_data), .ext_ram_addr(eram_addr),
        .ext_ram_be_n(eram_be_n), .ext_ram_ce_n(eram_ce_n),
        .ext_ram_oe_n(eram_oe_n), .ext_ram_we_n(eram_we_n)
    );

    async_sram_model #(.WORDS(256)) u_ext_ram (
        .clk(clk), .addr(eram_addr), .be_n(eram_be_n),
        .ce_n(eram_ce_n), .oe_n(eram_oe_n), .we_n(eram_we_n),
        .data(eram_data)
    );

    // CE_n 低电平拍数统计（在 posedge 观察上一拍的电平）
    integer ce1_cnt = 0, ce2_cnt = 0;
    always @(posedge clk) begin
        if (!bram_ce_n) ce1_cnt = ce1_cnt + 1;
        if (!eram_ce_n) ce2_cnt = ce2_cnt + 1;
    end

    // ==================================================================
    // 事务任务
    // ==================================================================
    task automatic wr1(input [19:0] a, input [31:0] d, input [3:0] be);
        @(negedge clk);
        req_valid = 1; req_addr = a; req_we = 1; req_wdata = d; req_be_n = be;
        @(posedge clk);
        while (!req_ready) @(posedge clk);
        @(negedge clk);
        req_valid = 0;
        @(posedge clk);
        while (!rsp_valid) @(posedge clk);
    endtask

    task automatic rd1(input [19:0] a, output [31:0] d);
        integer ce_before;
        ce_before = ce1_cnt;
        @(negedge clk);
        req_valid = 1; req_addr = a; req_we = 0; req_be_n = 4'h0;
        @(posedge clk);
        while (!req_ready) @(posedge clk);
        @(negedge clk);
        req_valid = 0;
        @(posedge clk);
        while (!rsp_valid) @(posedge clk);
        d = rsp_rdata;
        if (ce1_cnt - ce_before != 1) begin
            $display("FAIL: 实例1 CE 低电平 %0d 拍（期望 1）", ce1_cnt - ce_before);
            errors = errors + 1;
        end
    endtask

    task automatic wr2(input [19:0] a, input [31:0] d, input [3:0] be);
        integer ce_before;
        ce_before = ce2_cnt;
        @(negedge clk);
        req2_valid = 1; req2_addr = a; req2_we = 1; req2_wdata = d; req2_be_n = be;
        @(posedge clk);
        while (!req2_ready) @(posedge clk);
        @(negedge clk);
        req2_valid = 0;
        @(posedge clk);
        while (!rsp2_valid) @(posedge clk);
        if (ce2_cnt - ce_before != 3) begin
            $display("FAIL: 实例2 写 CE 低电平 %0d 拍（期望 3）", ce2_cnt - ce_before);
            errors = errors + 1;
        end
    endtask

    task automatic rd2(input [19:0] a, output [31:0] d);
        integer ce_before;
        ce_before = ce2_cnt;
        @(negedge clk);
        req2_valid = 1; req2_addr = a; req2_we = 0; req2_be_n = 4'h0;
        @(posedge clk);
        while (!req2_ready) @(posedge clk);
        @(negedge clk);
        req2_valid = 0;
        @(posedge clk);
        while (!rsp2_valid) @(posedge clk);
        d = rsp2_rdata;
        if (ce2_cnt - ce_before != 3) begin
            $display("FAIL: 实例2 读 CE 低电平 %0d 拍（期望 3）", ce2_cnt - ce_before);
            errors = errors + 1;
        end
    endtask

    task automatic check(input [31:0] got, input [31:0] exp, input string name);
        if (got !== exp) begin
            $display("FAIL: %0s  got=%h exp=%h", name, got, exp);
            errors = errors + 1;
        end else begin
            $display("PASS: %0s  %h", name, got);
        end
    endtask

    reg [31:0] d;

    // ==================================================================
    // 主流程
    // ==================================================================
    initial begin
        $display("=== sram_ctrl testbench ===");
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // ---- 实例 1（RAM_CYC=1） ----
        rd1(20'd0, d);
        check(d, 32'hdead_beef, "base: initial read addr0");

        wr1(20'd1, 32'h11223344, 4'b0000);
        rd1(20'd1, d);
        check(d, 32'h11223344, "base: word write/read addr1");

        rd1(20'd2, d);
        check(d, 32'hdead_beef, "base: initial read addr2");
        wr1(20'd2, 32'haabbccaa, 4'b1110);       // 只写 byte0
        rd1(20'd2, d);
        check(d, 32'hdead_beaa, "base: byte0-only write addr2");

        wr1(20'd3, 32'h55_000000, 4'b0111);      // 只写 byte3
        rd1(20'd3, d);
        check(d, 32'h55ad_beef, "base: byte3-only write addr3");

        // ---- 实例 2（RAM_CYC=3） ----
        rd2(20'd0, d);
        check(d, 32'hdead_beef, "ext: initial read addr0");

        wr2(20'd1, 32'hcafebabe, 4'b0000);
        rd2(20'd1, d);
        check(d, 32'hcafebabe, "ext: word write/read addr1");

        wr2(20'd2, 32'h00_0000_7f, 4'b1110);
        rd2(20'd2, d);
        check(d, 32'hdead_be7f, "ext: byte0-only write addr2");

        // ---- 两实例互不干扰 ----
        rd1(20'd1, d);
        check(d, 32'h11223344, "cross: base addr1 unaffected by ext");

        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

`default_nettype wire
