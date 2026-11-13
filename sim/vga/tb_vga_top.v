`default_nettype none
// ---------------------------------------------------------------------------
// tb_vga_top.v —— VGA 验证环境的仿真顶层（真实存储链路）
//
//   vga_dut ──DVI──┐
//                  ├─ ext_ram_arbiter ─ ext_ram_ctrl ─ 异步 SRAM 模型
//   cpu_noise ─CPU─┘
//
// 这样仿真走的就是上板时的真实路径：仲裁器 + 2 拍延迟的 SRAM 控制器，
// 而不是一个理想化的 1 拍 RAM 模型。
//
// 待测模块由 Makefile 的 DUT 变量选择（占位实现或 vga/dut_vga_fb.v）。
// ---------------------------------------------------------------------------
module tb_vga_top(
    input  wire       clk,
    input  wire       rst,
    input  wire       fb_sel,
    input  wire       noise_en,

    output wire [2:0] vga_red,
    output wire [2:0] vga_green,
    output wire [1:0] vga_blue,
    output wire       vga_hsync,
    output wire       vga_vsync,
    output wire       vga_de,
    output wire       vsync_start,

    output wire [31:0] noise_grants,
    output wire [31:0] noise_errors,
    output wire [31:0] dvi_reqs,
    output wire [31:0] dvi_rsps,
    output wire [31:0] dvi_stalls,
    output wire [31:0] dvi_latency_err
);

    // ---- DVI 主机 ----
    wire [19:0] dvi_addr;
    wire        dvi_req, dvi_next, dvi_ready;
    wire [31:0] dvi_rdata;
    wire        dvi_rsp_valid;

    // ---- CPU 噪声主机 ----
    wire        cpu_req;
    wire [19:0] cpu_addr;
    wire        cpu_we;
    wire [3:0]  cpu_be_n;
    wire [31:0] cpu_wdata;
    wire        cpu_ready;
    wire [31:0] cpu_rsp_rdata;
    wire        cpu_rsp_valid;

    // ---- 仲裁器 -> 控制器 ----
    wire        mem_req;
    wire [19:0] mem_addr;
    wire        mem_we;
    wire [3:0]  mem_be_n;
    wire [31:0] mem_wdata;
    wire        mem_ready;
    wire        mem_rsp_valid;
    wire [31:0] mem_rsp_rdata;

    // ---- 板级 ExtRAM 引脚 ----
    wire [31:0] ext_ram_data;
    wire [19:0] ext_ram_addr;
    wire [3:0]  ext_ram_be_n;
    wire        ext_ram_ce_n, ext_ram_oe_n, ext_ram_we_n;

    vga_dut u_dut (
        .clk        (clk),
        .rst        (rst),
        .fb_sel     (fb_sel),
        .ram_addr   (dvi_addr),
        .ram_req    (dvi_req),
        .ram_rdata  (dvi_rdata),
        .vga_red    (vga_red),
        .vga_green  (vga_green),
        .vga_blue   (vga_blue),
        .vga_hsync  (vga_hsync),
        .vga_vsync  (vga_vsync),
        .vga_de     (vga_de),
        .vsync_start(vsync_start),
        .dvi_next   (dvi_next)
    );

    ext_ram_arbiter u_arb (
        .clk          (clk),
        .rst          (rst),
        .dvi_req      (dvi_req),
        .dvi_next     (dvi_next),
        .dvi_addr     (dvi_addr),
        .dvi_ready    (dvi_ready),
        .dvi_rdata    (dvi_rdata),
        .dvi_rsp_valid(dvi_rsp_valid),
        .cpu_req      (cpu_req),
        .cpu_addr     (cpu_addr),
        .cpu_we       (cpu_we),
        .cpu_be_n     (cpu_be_n),
        .cpu_wdata    (cpu_wdata),
        .cpu_ready    (cpu_ready),
        .cpu_rsp_rdata(cpu_rsp_rdata),
        .cpu_rsp_valid(cpu_rsp_valid),
        .mem_req      (mem_req),
        .mem_addr     (mem_addr),
        .mem_we       (mem_we),
        .mem_be_n     (mem_be_n),
        .mem_wdata    (mem_wdata),
        .mem_ready    (mem_ready),
        .mem_rsp_valid(mem_rsp_valid),
        .mem_rsp_rdata(mem_rsp_rdata)
    );

    ext_ram_ctrl #(
        .CLK_FREQ(50_000_000),
        .RAM_FREQ(67_000_000)
    ) u_ctrl (
        .clk       (clk),
        .rst       (rst),
        .req_valid (mem_req),
        .req_ready (mem_ready),
        .req_addr  (mem_addr),
        .req_we    (mem_we),
        .req_be_n  (mem_be_n),
        .req_wdata (mem_wdata),
        .rsp_valid (mem_rsp_valid),
        .rsp_rdata (mem_rsp_rdata),
        .ext_ram_data(ext_ram_data),
        .ext_ram_addr(ext_ram_addr),
        .ext_ram_be_n(ext_ram_be_n),
        .ext_ram_ce_n(ext_ram_ce_n),
        .ext_ram_oe_n(ext_ram_oe_n),
        .ext_ram_we_n(ext_ram_we_n)
    );

    async_sram_model #(
        .WORDS    (1048576),
        .LOAD_INIT(1'b1),
        .INIT_FILE("fb0.hex"),
        .FILL_WORD(32'd0)
    ) u_ram (
        .clk  (clk),
        .addr (ext_ram_addr),
        .be_n (ext_ram_be_n),
        .ce_n (ext_ram_ce_n),
        .oe_n (ext_ram_oe_n),
        .we_n (ext_ram_we_n),
        .data (ext_ram_data)
    );

    cpu_noise #(.BASE(300000)) u_noise (
        .clk      (clk),
        .rst      (rst),
        .en       (noise_en),
        .req      (cpu_req),
        .addr     (cpu_addr),
        .we       (cpu_we),
        .be_n     (cpu_be_n),
        .wdata    (cpu_wdata),
        .ready    (cpu_ready),
        .rsp_valid(cpu_rsp_valid),
        .rsp_rdata(cpu_rsp_rdata),
        .grants   (noise_grants),
        .errors   (noise_errors)
    );

    // ---- DVI 监视：请求不得被丢、响应必须恰好 2 拍后到达 ----
    reg [31:0] req_cnt, rsp_cnt, stall_cnt, lat_err;
    reg        req_d1, req_d2;

    always @(posedge clk) begin
        if (rst) begin
            req_cnt <= 32'd0; rsp_cnt <= 32'd0;
            stall_cnt <= 32'd0; lat_err <= 32'd0;
            req_d1 <= 1'b0; req_d2 <= 1'b0;
        end else begin
            req_d1 <= dvi_req;
            req_d2 <= req_d1;
            if (dvi_req)                req_cnt   <= req_cnt + 32'd1;
            if (dvi_rsp_valid)          rsp_cnt   <= rsp_cnt + 32'd1;
            if (dvi_req && !dvi_ready)  stall_cnt <= stall_cnt + 32'd1;
            // 同一时刻最多一个 DVI 事务在途，所以响应应与"两拍前的请求"逐拍对齐
            if (dvi_rsp_valid != req_d2) lat_err <= lat_err + 32'd1;
        end
    end

    assign dvi_reqs       = req_cnt;
    assign dvi_rsps       = rsp_cnt;
    assign dvi_stalls     = stall_cnt;
    assign dvi_latency_err = lat_err;

endmodule

`default_nettype wire
