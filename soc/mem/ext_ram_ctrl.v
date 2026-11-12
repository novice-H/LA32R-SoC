`default_nettype none
// ---------------------------------------------------------------------------
// ext_ram_ctrl.v —— ExtRAM 控制器封装
//
// 对应原设计的 EXT.sv，但**没有移植其中的 EXT_CACHE**（写直达、无写分配）。
// 原因：
//   1. 2048 项目用 openLA500，它自带 dcache，再叠一层外部缓存意义不大；
//   2. 帧缓冲按设计走 LA32R 的 uncached 窗口（0xA000_0000），CPU 写直接落到
//      SRAM，DVI 扫描器才能读到最新像素；
//   3. 少一层缓存 = 少一份一致性风险与延迟。
//
// 如果以后确实需要（例如把 ExtRAM 当 cached 数据区），可以把原工程的
// EXT_CACHE.sv 接在本模块与总线之间，接口层不受影响。
//
// 注意：DVI 扫描器也会读 ExtRAM，届时报文地址需经仲裁器再进本控制器。
// ---------------------------------------------------------------------------
module ext_ram_ctrl #(
    parameter integer CLK_FREQ = 50_000_000,
    parameter integer RAM_FREQ = 67_000_000
)(
    input  wire        clk,
    input  wire        rst,

    // 简单总线侧
    input  wire        req_valid,
    output wire        req_ready,
    input  wire [19:0] req_addr,
    input  wire        req_we,
    input  wire [3:0]  req_be_n,
    input  wire [31:0] req_wdata,
    output wire        rsp_valid,
    output wire [31:0] rsp_rdata,

    // 板级 ExtRAM 引脚（与 thinpad_top.v 同名）
    inout  wire [31:0] ext_ram_data,
    output wire [19:0] ext_ram_addr,
    output wire [3:0]  ext_ram_be_n,
    output wire        ext_ram_ce_n,
    output wire        ext_ram_oe_n,
    output wire        ext_ram_we_n
);

    sram_ctrl #(
        .CLK_FREQ(CLK_FREQ),
        .RAM_FREQ(RAM_FREQ)
    ) u_ctrl (
        .clk      (clk),
        .rst      (rst),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_addr (req_addr),
        .req_we   (req_we),
        .req_be_n (req_be_n),
        .req_wdata(req_wdata),
        .rsp_valid(rsp_valid),
        .rsp_rdata(rsp_rdata),
        .ram_data (ext_ram_data),
        .ram_addr (ext_ram_addr),
        .ram_be_n (ext_ram_be_n),
        .ram_ce_n (ext_ram_ce_n),
        .ram_oe_n (ext_ram_oe_n),
        .ram_we_n (ext_ram_we_n)
    );

endmodule

`default_nettype wire
