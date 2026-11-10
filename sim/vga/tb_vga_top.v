`default_nettype none
// ---------------------------------------------------------------------------
// tb_vga_top.v —— VGA 验证环境的仿真顶层
//
// 结构：
//   ram_model(4 MB) --1 拍读--> vga_dut --RGB332/同步--> 仿真器
//
// 其中 vga_dut 是"待测模块"，由 Makefile 的 DUT 变量选择：
//   默认：vga/dut_placeholder.v（占位实现，用来跑通环境）
//   以后：make DUT=vga/dut_<你的模块>.v
//
// DUT 契约（详见 README.md）：
//   input  clk, rst
//   input  fb_sel                0=FB0, 1=FB1
//   output [19:0] ram_addr       ExtRAM 字地址
//   output        ram_req        读请求（单拍）
//   input  [31:0] ram_rdata      1 拍延迟返回
//   output [2:0]  vga_red/green, [1:0] vga_blue
//   output        vga_hsync, vga_vsync, vga_de
// ---------------------------------------------------------------------------
module tb_vga_top(
    input  wire       clk,
    input  wire       rst,
    input  wire       fb_sel,
    output wire [2:0] vga_red,
    output wire [2:0] vga_green,
    output wire [1:0] vga_blue,
    output wire       vga_hsync,
    output wire       vga_vsync,
    output wire       vga_de
);

    wire [19:0] ram_addr;
    wire        ram_req;
    wire [31:0] ram_rdata;

    ram_model #(
        .WORDS(1048576),
        .INIT_FILE("fb0.hex")
    ) u_ram (
        .clk  (clk),
        .addr (ram_addr),
        .req  (ram_req),
        .rdata(ram_rdata)
    );

    vga_dut u_dut (
        .clk      (clk),
        .rst      (rst),
        .fb_sel   (fb_sel),
        .ram_addr (ram_addr),
        .ram_req  (ram_req),
        .ram_rdata(ram_rdata),
        .vga_red  (vga_red),
        .vga_green(vga_green),
        .vga_blue (vga_blue),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync),
        .vga_de   (vga_de)
    );

endmodule

`default_nettype wire
