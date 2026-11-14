`default_nettype none
// ---------------------------------------------------------------------------
// thinpad_top.v —— 板级顶层（全 SoC）
//
// 板级引脚与赛方模板完全一致；内部只做三件事：
//   1. 把可用的板载引脚接到 SoC 核心（soc/soc_top.v）
//   2. 把本设计不用的外设（串口、Flash、备用时钟、时钟按钮）安全关掉
//   3. 视频时钟直接前向 clk_50M（单一 50 MHz 时钟域，无 CDC）
//
// SoC 核心：openLA500 + AXI 从设备桥 + 总线译码 + BaseRAM/ExtRAM 控制器
//           + ExtRAM 仲裁器 + VGA 扫描 + confreg
//
// 地址映射（soc/bus/soc_bus.v）：
//   0x1C00_0000 BaseRAM（别名 0x8000_0000）
//   0x1C40_0000 ExtRAM / FB0（别名 0xA000_0000）
//   0xBFD0_0000 confreg
// ---------------------------------------------------------------------------
module thinpad_top(
    input  wire        clk_50M,
    input  wire        clk_11M0592,   // 未使用
    input  wire        clock_btn,     // 未使用
    input  wire        reset_btn,

    input  wire [3:0]  touch_btn,
    input  wire [31:0] dip_sw,
    output wire [15:0] leds,
    output wire [7:0]  dpy0,
    output wire [7:0]  dpy1,

    // BaseRAM
    inout  wire [31:0] base_ram_data,
    output wire [19:0] base_ram_addr,
    output wire [3:0]  base_ram_be_n,
    output wire        base_ram_ce_n,
    output wire        base_ram_oe_n,
    output wire        base_ram_we_n,

    // ExtRAM
    inout  wire [31:0] ext_ram_data,
    output wire [19:0] ext_ram_addr,
    output wire [3:0]  ext_ram_be_n,
    output wire        ext_ram_ce_n,
    output wire        ext_ram_oe_n,
    output wire        ext_ram_we_n,

    // 串口（本设计不用）
    output wire        txd,
    input  wire        rxd,

    // Flash（本设计不用）
    output wire [22:0] flash_a,
    inout  wire [15:0] flash_d,
    output wire        flash_rp_n,
    output wire        flash_vpen,
    output wire        flash_ce_n,
    output wire        flash_oe_n,
    output wire        flash_we_n,
    output wire        flash_byte_n,

    // 视频
    output wire [2:0]  video_red,
    output wire [2:0]  video_green,
    output wire [1:0]  video_blue,
    output wire        video_hsync,
    output wire        video_vsync,
    output wire        video_clk,
    output wire        video_de
);

    // ---------------------------------------------------------------- SoC 核心
    soc_top u_soc (
        .clk_50M(clk_50M),
        .reset_btn(reset_btn),

        .base_ram_data(base_ram_data),
        .base_ram_addr(base_ram_addr),
        .base_ram_be_n(base_ram_be_n),
        .base_ram_ce_n(base_ram_ce_n),
        .base_ram_oe_n(base_ram_oe_n),
        .base_ram_we_n(base_ram_we_n),

        .ext_ram_data(ext_ram_data),
        .ext_ram_addr(ext_ram_addr),
        .ext_ram_be_n(ext_ram_be_n),
        .ext_ram_ce_n(ext_ram_ce_n),
        .ext_ram_oe_n(ext_ram_oe_n),
        .ext_ram_we_n(ext_ram_we_n),

        .video_red(video_red),
        .video_green(video_green),
        .video_blue(video_blue),
        .video_hsync(video_hsync),
        .video_vsync(video_vsync),
        .video_clk(video_clk),
        .video_de(video_de),

        .touch_btn(touch_btn),
        .dip_sw(dip_sw),
        .leds(leds),
        .dpy0(dpy0),
        .dpy1(dpy1),

        .dbg_wb_pc(dbg_wb_pc_unused)
    );

    wire [31:0] dbg_wb_pc_unused;   // 仅仿真观测用，板级不引出


    // ---------------------------------------------------------------- 未使用外设
    // 串口：TX 保持空闲高电平
    assign txd = 1'b1;

    // Flash：全部关闭（片选/读写使能高电平，复位与写保护释放）
    assign flash_a       = 23'd0;
    assign flash_d       = 16'bz;
    assign flash_rp_n    = 1'b1;
    assign flash_vpen    = 1'b1;
    assign flash_ce_n    = 1'b1;
    assign flash_oe_n    = 1'b1;
    assign flash_we_n    = 1'b1;
    assign flash_byte_n  = 1'b1;

    // clk_11M0592 / clock_btn / rxd 不使用

endmodule

`default_nettype wire
