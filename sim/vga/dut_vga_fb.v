`default_nettype none

// 仿真包装器：把 soc/vga_fb.v 接到 sim/vga 的统一 vga_dut 契约。
module vga_dut (
    input  wire        clk,
    input  wire        rst,
    input  wire        fb_sel,
    output wire [19:0] ram_addr,
    output wire        ram_req,
    input  wire [31:0] ram_rdata,
    output wire [2:0]  vga_red,
    output wire [2:0]  vga_green,
    output wire [1:0]  vga_blue,
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire        vga_de
);
    vga_fb u_vga_fb (
        .clk       (clk),
        .rst       (rst),
        .fb_sel    (fb_sel),
        .ram_addr  (ram_addr),
        .ram_req   (ram_req),
        .ram_rdata (ram_rdata),
        .vga_red   (vga_red),
        .vga_green (vga_green),
        .vga_blue  (vga_blue),
        .vga_hsync (vga_hsync),
        .vga_vsync (vga_vsync),
        .vga_de    (vga_de)
    );
endmodule

`default_nettype wire
