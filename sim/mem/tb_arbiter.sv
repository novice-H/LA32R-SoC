`default_nettype none
// ---------------------------------------------------------------------------
// tb_arbiter.sv —— ExtRAM 仲裁器单元测试
//
// 被测：soc/mem/ext_ram_arbiter.v（+ ext_ram_ctrl + 异步 SRAM 模型）
//
// 覆盖（沿用队友 tb_extram_arbiter 的测试意图，按本仓库接口重写）：
//   1. CPU 整字写/读
//   2. CPU 字节使能部分写
//   3. DVI 每 4 拍发一次请求（带 dvi_next 预警）：请求零丢弃、响应恰好 2 拍
//   4. DVI 与 CPU 争用下，DVI 读到的数据正确
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_arbiter;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;

    // ---------------- DVI 侧 ----------------
    reg  [1:0]  dvi_phase = 0;
    reg         dvi_en = 0;
    reg  [19:0] vga_idx = 0;
    reg  [19:0] dvi_addr_q = 0;
    wire [19:0] dvi_addr = vga_idx;
    wire        dvi_req  = dvi_en && (dvi_phase == 2'd2);
    wire        dvi_next = dvi_en && (dvi_phase == 2'd1);
    wire        dvi_ready;
    wire [31:0] dvi_rdata;
    wire        dvi_rsp_valid;

    // ---------------- CPU 侧 ----------------
    reg         cpu_req = 0;
    reg  [19:0] cpu_addr = 0;
    reg         cpu_we = 0;
    reg  [3:0]  cpu_be_n = 4'h0;
    reg  [31:0] cpu_wdata = 0;
    wire        cpu_ready;
    wire [31:0] cpu_rsp_rdata;
    wire        cpu_rsp_valid;

    // ---------------- 控制器侧 ----------------
    wire        mem_req, mem_we, mem_ready, mem_rsp_valid;
    wire [19:0] mem_addr;
    wire [3:0]  mem_be_n;
    wire [31:0] mem_wdata, mem_rsp_rdata;

    // ---------------- SRAM 引脚 ----------------
    wire [31:0] sram_data;
    wire [19:0] sram_addr;
    wire [3:0]  sram_be_n;
    wire        sram_ce_n, sram_oe_n, sram_we_n;

    ext_ram_arbiter u_arb (
        .clk(clk), .rst(rst),
        .dvi_req(dvi_req), .dvi_next(dvi_next), .dvi_addr(dvi_addr),
        .dvi_ready(dvi_ready), .dvi_rdata(dvi_rdata), .dvi_rsp_valid(dvi_rsp_valid),
        .cpu_req(cpu_req), .cpu_addr(cpu_addr), .cpu_we(cpu_we),
        .cpu_be_n(cpu_be_n), .cpu_wdata(cpu_wdata),
        .cpu_ready(cpu_ready), .cpu_rsp_rdata(cpu_rsp_rdata), .cpu_rsp_valid(cpu_rsp_valid),
        .mem_req(mem_req), .mem_addr(mem_addr), .mem_we(mem_we),
        .mem_be_n(mem_be_n), .mem_wdata(mem_wdata),
        .mem_ready(mem_ready), .mem_rsp_valid(mem_rsp_valid), .mem_rsp_rdata(mem_rsp_rdata)
    );

    ext_ram_ctrl #(.CLK_FREQ(50_000_000), .RAM_FREQ(67_000_000)) u_ctrl (
        .clk(clk), .rst(rst),
        .req_valid(mem_req), .req_ready(mem_ready),
        .req_addr(mem_addr), .req_we(mem_we), .req_be_n(mem_be_n), .req_wdata(mem_wdata),
        .rsp_valid(mem_rsp_valid), .rsp_rdata(mem_rsp_rdata),
        .ext_ram_data(sram_data), .ext_ram_addr(sram_addr),
        .ext_ram_be_n(sram_be_n), .ext_ram_ce_n(sram_ce_n),
        .ext_ram_oe_n(sram_oe_n), .ext_ram_we_n(sram_we_n)
    );

    async_sram_model #(.WORDS(1024), .LOAD_INIT(1'b0), .FILL_WORD(32'hdead_beef)) u_sram (
        .clk(clk), .addr(sram_addr), .be_n(sram_be_n),
        .ce_n(sram_ce_n), .oe_n(sram_oe_n), .we_n(sram_we_n),
        .data(sram_data)
    );

    // ---------------- 监视 ----------------
    integer errors = 0;
    integer vga_reqs = 0, vga_rsps = 0, vga_drops = 0, vga_lat_err = 0, vga_data_err = 0;
    reg     req_d1 = 0, req_d2 = 0;

    always @(posedge clk) begin
        if (rst) begin
            req_d1 <= 0; req_d2 <= 0;
        end else begin
            req_d1 <= dvi_req;
            req_d2 <= req_d1;
            if (dvi_req) begin
                vga_reqs = vga_reqs + 1;
                if (!dvi_ready) vga_drops = vga_drops + 1;
                dvi_addr_q <= dvi_addr;
            end
            if (dvi_rsp_valid) begin
                vga_rsps = vga_rsps + 1;
                if (dvi_rdata !== (32'hC0DE_0000 | {12'd0, dvi_addr_q}))
                    vga_data_err = vga_data_err + 1;
            end
            if (dvi_rsp_valid != req_d2) vga_lat_err = vga_lat_err + 1;
        end
    end

    // DVI 每 4 拍一个周期
    always @(posedge clk) begin
        if (rst) dvi_phase <= 2'd0;
        else begin
            dvi_phase <= (dvi_phase == 2'd3) ? 2'd0 : dvi_phase + 2'd1;
            if (dvi_en && dvi_phase == 2'd3) vga_idx <= (vga_idx == 20'd15) ? 20'd0 : vga_idx + 20'd1;
        end
    end

    task automatic check32(input [31:0] got, input [31:0] exp, input string name);
        if (got !== exp) begin
            $display("FAIL: %0s got=%h exp=%h", name, got, exp);
            errors = errors + 1;
        end else begin
            $display("PASS: %0s = %h", name, got);
        end
    endtask

    task automatic cpu_write(input [19:0] a, input [31:0] d, input [3:0] be);
        @(negedge clk);
        cpu_req = 1; cpu_addr = a; cpu_we = 1; cpu_wdata = d; cpu_be_n = be;
        @(posedge clk);
        while (!cpu_ready) @(posedge clk);
        @(negedge clk);
        cpu_req = 0; cpu_be_n = 4'h0;
        @(posedge clk);
        while (!cpu_rsp_valid) @(posedge clk);
    endtask

    task automatic cpu_read(input [19:0] a, output [31:0] d);
        @(negedge clk);
        cpu_req = 1; cpu_addr = a; cpu_we = 0; cpu_be_n = 4'h0;
        @(posedge clk);
        while (!cpu_ready) @(posedge clk);
        @(negedge clk);
        cpu_req = 0;
        @(posedge clk);
        while (!cpu_rsp_valid) @(posedge clk);
        d = cpu_rsp_rdata;
    endtask

    integer i;
    reg [31:0] d;
    reg [19:0] ai;
    reg [31:0] pat;

    initial begin
        $display("=== ext_ram_arbiter unit test ===");
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // 1) CPU 先写入 16 个已知字（VGA 关闭）
        for (i = 0; i < 16; i = i + 1) begin
            ai  = i[19:0];
            pat = 32'hC0DE_0000 + i[31:0];
            cpu_write(ai, pat, 4'b0000);
        end

        // 2) CPU 整字读回
        cpu_read(20'd5, d);
        check32(d, 32'hC0DE_0005, "CPU 整字读回");

        // 3) CPU 字节使能部分写：地址 100 初值 deadbeef，只写 byte0
        cpu_write(20'd100, 32'h0000007F, 4'b1110);
        cpu_read(20'd100, d);
        check32(d, 32'hDEADBE7F, "CPU 字节使能部分写");

        // 4) 打开 VGA，让它在 CPU 争用下连续读
        dvi_en = 1;
        repeat (4000) @(posedge clk);

        // 5) 争用期间 CPU 仍能正确读写
        cpu_write(20'd200, 32'h1234_5678, 4'b0000);
        cpu_read(20'd200, d);
        check32(d, 32'h1234_5678, "争用下 CPU 写读");

        $display("DVI: req=%0d rsp=%0d drops=%0d lat_err=%0d data_err=%0d",
                 vga_reqs, vga_rsps, vga_drops, vga_lat_err, vga_data_err);
        if (vga_reqs == 0 || vga_reqs != vga_rsps || vga_drops != 0 ||
            vga_lat_err != 0 || vga_data_err != 0) begin
            $display("FAIL: DVI 通道检查不通过");
            errors = errors + 1;
        end else begin
            $display("PASS: DVI 零丢弃、2 拍响应、数据正确");
        end

        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

`default_nettype wire
