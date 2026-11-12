`default_nettype none
// ---------------------------------------------------------------------------
// base_ram_ctrl.v —— BaseRAM 控制器封装
//
// 对应原设计的 BSE.sv（BaseRAM wrapper）：把共享的 sram_ctrl 直接接到
// 板级 base_ram_* 引脚。原封装的 IFU/XIU 双端口与 hold 逻辑属于 CPU 的 LSU，
// 移植后由上层总线桥提供单请求流。
// ---------------------------------------------------------------------------
module base_ram_ctrl #(
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

    // 板级 BaseRAM 引脚（与 thinpad_top.v 同名）
    inout  wire [31:0] base_ram_data,
    output wire [19:0] base_ram_addr,
    output wire [3:0]  base_ram_be_n,
    output wire        base_ram_ce_n,
    output wire        base_ram_oe_n,
    output wire        base_ram_we_n
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
        .ram_data (base_ram_data),
        .ram_addr (base_ram_addr),
        .ram_be_n (base_ram_be_n),
        .ram_ce_n (base_ram_ce_n),
        .ram_oe_n (base_ram_oe_n),
        .ram_we_n (base_ram_we_n)
    );

endmodule

`default_nettype wire
